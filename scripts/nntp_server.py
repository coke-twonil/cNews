"""Local NNTP bridge. Fixed destination; origin-checked reading and posting."""
import json
import base64
import nntplib
import re
from email import policy
from email.parser import BytesParser
from email.header import decode_header
from email.utils import parseaddr, parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from nntp_posting import submit, MESSAGE_ID, UncertainPost, DuplicatePost
from nntp_connection import open_client
from nntp_ranges import article_numbers, selected_headers

HOST = 'news.twonil.hk'
ORIGIN = 'http://127.0.0.1:8765'
GROUP = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.+-]{0,150}$')


def header(value):
    # NNTP uses surrogateescape for unlabelled 8-bit legacy headers.
    if any(0xDC80 <= ord(c) <= 0xDCFF for c in value):
        value = value.encode('utf-8', 'surrogateescape').decode('big5', 'replace')
    result = ''
    for part, charset in decode_header(value):
        if isinstance(part, bytes):
            for encoding in [charset, 'utf-8', 'big5', 'cp950']:
                if not encoding:
                    continue
                try:
                    part = part.decode(encoding)
                    break
                except (UnicodeError, LookupError):
                    pass
            if isinstance(part, bytes):
                part = part.decode('utf-8', 'replace')
        result += part
    return result


def overview(number, row):
    author, address = parseaddr(header(row['from']))
    try:
        created = parsedate_to_datetime(row['date']).isoformat()
    except (ValueError, TypeError, OverflowError):
        created = None
    return dict(id=row['message-id'], number=int(number), subject=header(row['subject']),
                author=author or address, email=address, createdAt=created,
                references=re.findall(r'<[^<>\s]+>', row['references']),
                bytes=int(row.get(':bytes', '0') or 0))


MAX_IMAGE_BYTES = 10 * 1024 * 1024
MAX_ARTICLE_IMAGE_BYTES = 20 * 1024 * 1024


def image_type(payload):
    # Raster signatures only: never inline SVG/HTML supplied as an attachment.
    if payload.startswith(b'\xff\xd8\xff'):
        return 'image/jpeg'
    if payload.startswith(b'\x89PNG\r\n\x1a\n'):
        return 'image/png'
    if payload[:6] in (b'GIF87a', b'GIF89a'):
        return 'image/gif'
    if payload.startswith(b'RIFF') and payload[8:12] == b'WEBP':
        return 'image/webp'
    return None


def article_content(lines):
    article = BytesParser(policy=policy.default).parsebytes(b'\r\n'.join(lines))
    bodies, images, warnings, content_parts = [], [], [], []
    total = 0
    for part in article.walk():
        if part.is_multipart():
            continue
        payload = part.get_payload(decode=True) or b''
        mime = image_type(payload)
        if part.get_content_maintype() == 'image' or mime:
            if not mime:
                warnings.append('有圖片格式暫未支援或資料已損壞。')
            elif len(payload) > MAX_IMAGE_BYTES or total + len(payload) > MAX_ARTICLE_IMAGE_BYTES:
                warnings.append('有圖片超出載入大小上限，未能顯示。')
            else:
                total += len(payload)
                images.append('data:' + mime + ';base64,' + base64.b64encode(payload).decode('ascii'))
                content_parts.append({'type':'image','index':len(images)-1})
            continue
        if part.get_content_type() != 'text/plain' or part.get_content_disposition() == 'attachment':
            continue
        for encoding in [part.get_content_charset(), 'utf-8', 'big5', 'cp950']:
            if not encoding:
                continue
            try:
                bodies.append(payload.decode(encoding))
                break
            except (UnicodeError, LookupError):
                pass
        else:
            bodies.append(payload.decode('utf-8', 'replace'))
        content_parts.append({'type':'text','text':bodies[-1]})
    body = '\n\n'.join(bodies)
    if not bodies and not images:
        body = '此文章冇可顯示嘅純文字或圖片；暫未支援 HTML-only／其他二進制附件。'
    if not content_parts:
        content_parts.append({'type':'text','text':body})
    return dict(body=body, images=images, contentParts=content_parts, imageWarnings=list(dict.fromkeys(warnings)), contentVersion=3)


def article_body(lines):
    return article_content(lines)['body']


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        # Require the reader origin and a custom header: other sites cannot drive
        # even read-only queries through this local service.
        if self.headers.get('Origin') != ORIGIN or self.headers.get('X-yrNewsEx') != 'reader':
            self.reply(403, {'error': 'Reader origin required'})
            return
        try:
            parsed = urlparse(self.path)
            q = parse_qs(parsed.query)
            connection = {key:values[0] for key,values in q.items() if key in ('host','port','tls')}
            with open_client(connection) as client:
                if parsed.path == '/groups':
                    _, rows = client.list()
                    result = {'groups': [row.group for row in rows]}
                elif parsed.path in ('/numbers', '/headers', '/article'):
                    group = q.get('group', [''])[0]
                    if not GROUP.fullmatch(group):
                        raise ValueError('Invalid group')
                    _, count, first, last, _ = client.group(group)
                    if parsed.path == '/numbers':
                        numbers=article_numbers(client,group)
                        result=dict(count=len(numbers),first=int(first),last=int(last),numbers=numbers)
                    elif parsed.path == '/headers':
                        limit = max(1, min(2000, int(q.get('limit', ['500'])[0])))
                        end = min(int(last), int(q.get('before', [str(int(last)+1)])[0])-1)
                        start = max(int(first), end-limit+1)
                        rows = client.over((start, end))[1] if end >= start and int(count) else []
                        result = dict(count=int(count), first=int(first), last=int(last), start=start,
                                      messages=[overview(n, row) for n, row in rows])
                    else:
                        selector = q.get('id', [None])[0]
                        if selector is not None:
                            if not MESSAGE_ID.fullmatch(selector):
                                raise ValueError('Invalid Message-ID')
                        else:
                            selector = int(q.get('number', ['0'])[0])
                        _, info = client.article(selector)
                        parsed_article = BytesParser(policy=policy.default).parsebytes(b'\r\n'.join(info.lines))
                        meta = overview(info.number, {'message-id':info.message_id,'subject':str(parsed_article.get('Subject','')),'from':str(parsed_article.get('From','')),'date':str(parsed_article.get('Date','')),'references':str(parsed_article.get('References','')),':bytes':str(sum(len(line)+2 for line in info.lines))})
                        content = article_content(info.lines)
                        if q.get('images') == ['0']:
                            content.pop('images',None)
                        result = {'id': info.message_id, 'meta':meta, **content}
                else:
                    self.reply(404, {'error': 'Not found'})
                    return
            self.reply(200, result)
        except (ValueError, nntplib.NNTPError, OSError, EOFError) as error:
            self.reply(502, {'error': str(error)[:220]})

    def do_POST(self):
        if self.path not in ('/post','/headers'):
            self.reply(404, {'error':'Not found'}); return
        if self.headers.get('Origin') != ORIGIN or self.headers.get('X-yrNewsEx') != 'reader':
            self.reply(403, {'error':'Reader origin required'}); return
        try:
            length = int(self.headers.get('Content-Length','0'))
            if not 0 < length <= 24*1024*1024:
                raise ValueError('發送內容太大')
            if self.headers.get('Content-Type','').split(';')[0] != 'application/json':
                raise ValueError('Expected JSON')
            data = json.loads(self.rfile.read(length))
            if not isinstance(data,dict):
                raise ValueError('Invalid request')
            if self.path == '/headers':
                group=data.get('group','')
                if not isinstance(group,str) or not GROUP.fullmatch(group):
                    raise ValueError('Invalid group')
                numbers=data.get('numbers')
                if not isinstance(numbers,list) or len(numbers)>500 or any(type(n) is not int or n<=0 for n in numbers):
                    raise ValueError('每批最多 500 個有效文章編號')
                with open_client(data) as client:
                    _,count,first,last,_=client.group(group)
                    result=dict(count=int(count),messages=[overview(n,row) for n,row in selected_headers(client,numbers)])
            else:
                from nntp_posting import build_article
                build_article(data,image_type)
                with open_client(data,timeout=25) as client:
                    result=submit(client,data,image_type)
            self.reply(200,result)
        except DuplicatePost as error:
            self.reply(409, {'error':str(error),'duplicate':True})
        except UncertainPost as error:
            self.reply(409, {'error':str(error),'uncertain':True})
        except (ValueError, UnicodeError) as error:
            self.reply(400, {'error':str(error)[:220]})
        except (nntplib.NNTPError,OSError,EOFError) as error:
            self.reply(502, {'error':str(error)[:220]})

    def do_OPTIONS(self):
        if self.headers.get('Origin') != ORIGIN:
            self.send_error(403)
            return
        self.send_response(204)
        self.send_header('Access-Control-Allow-Origin', ORIGIN)
        self.send_header('Access-Control-Allow-Headers', 'X-yrNewsEx, Content-Type')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST')
        self.end_headers()

    def reply(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Access-Control-Allow-Origin', ORIGIN)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


def make_server():
    return ThreadingHTTPServer(('127.0.0.1', 8767), Handler)


if __name__ == '__main__':
    server = make_server()
    print('NNTP bridge: http://127.0.0.1:8767', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
