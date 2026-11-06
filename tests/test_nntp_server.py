import sys
import unittest
import base64
from unittest.mock import patch
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import nntp_server
from nntp_server import header, article_body, article_content, overview

class DecodeTests(unittest.TestCase):
    def test_encoded_header(self):
        self.assertEqual(header('=?UTF-8?B?5Lit5paH?='), '中文')
    def test_raw_big5_header(self):
        raw='繁體中文'.encode('big5').decode('utf-8', 'surrogateescape')
        self.assertEqual(header(raw), '繁體中文')
    def test_big5_body(self):
        body='繁體中文測試'.encode('big5')
        self.assertEqual(article_body([b'Content-Type: text/plain; charset=big5', b'', body]), '繁體中文測試')
    def test_multipart_ignores_attachment(self):
        raw=b'Content-Type: multipart/mixed; boundary=x\r\n\r\n--x\r\nContent-Type: text/plain\r\n\r\nHello\r\n--x\r\nContent-Type: text/plain\r\nContent-Disposition: attachment\r\n\r\nSECRET\r\n--x--'
        self.assertEqual(article_body(raw.split(b'\r\n')), 'Hello')
    def test_header_relationship(self):
        m=overview('3', {'message-id':'<c>', 'subject':'Re: Test', 'from':'A <a@example.invalid>', 'date':'bad', 'references':'<a> <b>', ':bytes':'200'})
        self.assertEqual(m['references'], ['<a>', '<b>'])
        self.assertIsNone(m['createdAt'])

class ImageTests(unittest.TestCase):
    def message(self, parts):
        from email.message import EmailMessage
        m=EmailMessage();m.set_content('繁體中文內容',charset='utf-8')
        for payload,kind in parts:
            m.add_attachment(payload,maintype='image',subtype=kind,filename='photo.'+kind)
        return m.as_bytes().replace(b'\r\n',b'\n').split(b'\n')

    def test_mime_images_preserve_bytes_and_order(self):
        images=[(b'\xff\xd8\xffjpeg', 'jpeg'),(b'\x89PNG\r\n\x1a\nimage','png'),(b'GIF89aimage','gif')]
        result=article_content(self.message(images))
        self.assertIn('繁體中文內容',result['body'])
        self.assertEqual(len(result['images']),3)
        for src,(payload,kind) in zip(result['images'],images):
            self.assertTrue(src.startswith('data:image/'+kind+';base64,'))
            self.assertEqual(base64.b64decode(src.split(',')[1]),payload)
        self.assertEqual(result['imageWarnings'],[])

    def test_image_only_and_webp_octet_stream(self):
        raw=[b'Content-Type: application/octet-stream',b'Content-Transfer-Encoding: base64',b'',base64.b64encode(b'RIFF1234WEBPimage')]
        result=article_content(raw)
        self.assertEqual(result['body'],'')
        self.assertTrue(result['images'][0].startswith('data:image/webp;'))

    def test_reject_active_content_and_enforce_sizes(self):
        result=article_content(self.message([(b'<svg onload="bad"/>','svg+xml'),(b'<html>bad</html>','jpeg')]))
        self.assertEqual(result['images'],[])
        self.assertTrue(result['imageWarnings'])
        with patch.object(nntp_server,'MAX_IMAGE_BYTES',4):
            result=article_content(self.message([(b'GIF89a12345','gif')]))
            self.assertFalse(result['images'])
        with patch.object(nntp_server,'MAX_ARTICLE_IMAGE_BYTES',10):
            result=article_content(self.message([(b'GIF89a1','gif'),(b'GIF89a2','gif')]))
            self.assertEqual(len(result['images']),1)
            self.assertTrue(result['imageWarnings'])
