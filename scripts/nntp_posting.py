"""Build and submit a single NNTP article; no automatic retry after ambiguity."""
import base64
import hashlib
import io
import json
import nntplib
import re
import threading
from email import policy
from email.message import EmailMessage
from email.parser import BytesParser
from email.utils import formataddr, formatdate

MESSAGE_ID = re.compile(r'^<[^<>\s\r\n]{1,240}>$')
_lock = threading.Lock()
_receipts = {}


def clean(value, label, maximum=998):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum or any(c in value for c in '\r\n\x00'):
        raise ValueError('Invalid ' + label)
    return value.strip()


def split_history(body):
    match = re.search(r"^(?:On [^\r\n]+ wrote:[ \t]*\r?\n(?=(?:[ \t]*\r?\n)*[ \t]*>)|[ \t]*>)", body, re.MULTILINE)
    return (body[:match.start()],body[match.start():]) if match else (body,'')


def build_article(data, image_type):
    group = clean(data.get('group'), 'group', 151)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.+-]{0,150}', group):
        raise ValueError('Invalid group')
    name = clean(data.get('name'), 'Name', 100)
    address = clean(data.get('email'), 'Email', 254)
    if not re.fullmatch(r'[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+', address):
        raise ValueError('Invalid Email')
    subject = clean(data.get('subject'), 'Subject')
    token = clean(data.get('postId'), 'postId', 36)
    if not re.fullmatch(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', token):
        raise ValueError('Invalid postId')
    body = data.get('body')
    if not isinstance(body, str) or not body.strip() or len(body.encode('utf-8')) > 1024*1024:
        raise ValueError('請填寫正文（最多 1 MB）')
    encoding = data.get('encoding', 'utf-8')
    if encoding not in ('big5', 'utf-8'):
        raise ValueError('Invalid encoding')
    body = body.rstrip() + '\n\n-- \nyrNewsEx\n'
    try:
        body.encode(encoding)
    except UnicodeEncodeError:
        encoding = 'utf-8'  # Preserve emoji and unsupported characters exactly.
    message = EmailMessage(policy=policy.SMTP)
    message['From'] = formataddr((name, address), charset='utf-8')
    message['Newsgroups'] = group
    message['Subject'] = subject
    message['Date'] = formatdate(localtime=True)
    message['Message-ID'] = '<yrnewsex.' + token + '@yrnewsex.invalid>'
    message['User-Agent'] = 'yrNewsEx prototype'
    refs = data.get('references', [])
    if not isinstance(refs, list) or len(refs) > 100 or any(not isinstance(r,str) or not MESSAGE_ID.fullmatch(r) for r in refs):
        raise ValueError('Invalid References')
    parent = data.get('replyTo')
    if parent:
        if not isinstance(parent,str) or not MESSAGE_ID.fullmatch(parent):
            raise ValueError('Invalid reply target')
        refs = list(dict.fromkeys([*refs, parent]))
        message['In-Reply-To'] = parent
    if refs:
        message['References'] = ' '.join(refs)
    own, history = split_history(body) if data.get('replyTo') else (body,'')
    message.set_content(own, charset=encoding, cte='base64')
    images = data.get('images', [])
    if not isinstance(images,list) or len(images) > 3:
        raise ValueError('最多只可以加 3 張相')
    for i, src in enumerate(images):
        if not isinstance(src,str) or not re.fullmatch(r'data:image/(jpeg|png|gif|webp);base64,[A-Za-z0-9+/=\r\n]+',src):
            raise ValueError('附件只支援 JPEG、PNG、GIF、WebP')
        try:
            raw = base64.b64decode(src.split(',',1)[1], validate=True)
        except (ValueError, base64.binascii.Error):
            raise ValueError('圖片資料無效')
        mime = image_type(raw)
        if not mime or mime != src.split(';')[0][5:] or len(raw) > 5*1024*1024:
            raise ValueError('圖片格式無效或超出 5 MB')
        message.add_attachment(raw,maintype='image',subtype=mime.split('/')[1],filename='photo-{}.{}'.format(i+1,mime.split('/')[1]))
    if history:
        history_part = EmailMessage(policy=policy.SMTP)
        history_part.set_content(history, charset=encoding, cte='base64')
        if not message.is_multipart():
            message.make_mixed()
        message.attach(history_part)
    return message, encoding


def content_signature(message):
    """Compare the article we can read, including every attachment byte."""
    headers = tuple(' '.join(str(message.get(k,'')).split()) for k in
                    ('From','Newsgroups','Subject','References','In-Reply-To'))
    texts, binaries = [], []
    for part in message.walk():
        if part.is_multipart():
            continue
        payload = part.get_payload(decode=True) or b''
        if part.get_content_type() == 'text/plain':
            text = payload.decode(part.get_content_charset() or 'utf-8').replace('\r\n','\n').strip()
            if text:
                texts.append(text)
        else:
            binaries.append((part.get_content_type(),hashlib.sha256(payload).hexdigest()))
    # Splitting text around images changes MIME segmentation, not its content.
    text_hash = hashlib.sha256('\n\n'.join(texts).encode('utf-8')).hexdigest()
    return headers, text_hash, tuple(binaries)



def existing_matches(client, mid, message):
    try:
        client.stat(mid)
        _, article = client.article(mid)
    except nntplib.NNTPTemporaryError as error:
        if str(error).startswith('430'):
            return None
        raise
    parsed = BytesParser(policy=policy.default).parsebytes(b'\r\n'.join(article.lines))
    return content_signature(parsed) == content_signature(message)


class DuplicatePost(Exception):
    pass


class UncertainPost(Exception):
    pass


def duplicate_error():
    return DuplicatePost('Server 拒絕重複發送識別碼，但未能讀到相同內容。草稿同附件已保留；先 Refresh 檢查，確認冇重複後可用新識別碼再試。')


def submit(client, data, image_type):
    message, encoding = build_article(data,image_type)
    mid = str(message['Message-ID'])
    digest = hashlib.sha256(json.dumps(data,sort_keys=True,ensure_ascii=False).encode('utf-8')).hexdigest()
    key=(data.get('host','news.twonil.hk'),int(data.get('port') or 119),mid)
    with _lock:
        prior = _receipts.get(key)
        if prior and prior['digest'] != digest:
            raise DuplicatePost('草稿內容或附件已改變，需要用新發送識別碼；草稿已保留。')
        if prior and prior['status'] == 'accepted':
            return dict(id=mid,encoding=encoding,accepted=True)
        match = existing_matches(client,mid,message)
        if match is True:
            _receipts[key] = {'digest':digest,'status':'accepted'}
            return dict(id=mid,encoding=encoding,accepted=True)
        if match is False:
            raise DuplicatePost('相同識別碼嘅文章內容／附件唔一致；草稿已保留，請檢查後用新識別碼再試。')
        if prior:
            if prior['status'] == 'duplicate':
                raise duplicate_error()
            raise UncertainPost('發送結果未確認，請先 Refresh 檢查；草稿已保留。')
        _receipts[key] = {'digest':digest,'status':'pending'}
        try:
            response = client.post(io.BytesIO(message.as_bytes()))
        except Exception as error:
            if re.search(r'\bduplicate\b', str(error), re.IGNORECASE):
                # INN history can remember an ID even when ARTICLE/STAT says 430.
                # Only a matching readable article proves successful delivery.
                _receipts[key]['status'] = 'duplicate'
                try:
                    match = existing_matches(client,mid,message)
                except (nntplib.NNTPError,OSError,EOFError):
                    match = None
                if match is True:
                    _receipts[key]['status'] = 'accepted'
                    return dict(id=mid,encoding=encoding,accepted=True)
                raise duplicate_error()
            if getattr(error,'response',None) or str(error).startswith(('4','5')):
                _receipts.pop(key,None)
                raise
            raise UncertainPost('連線中斷，發送結果未確認，請先 Refresh 檢查；草稿已保留。')
        if not response.startswith('240'):
            _receipts.pop(key,None)
            raise ValueError(response)
        _receipts[key]['status'] = 'accepted'
        return dict(id=mid,encoding=encoding,accepted=True)
