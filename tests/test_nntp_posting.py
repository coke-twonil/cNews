import sys
import io
import json
import uuid
import unittest
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
from email.parser import BytesParser
from email import policy
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
import nntp_posting as post
import nntp_server as bridge

class Client:
    def __init__(self): self.sent=[]; self.fail=None; self.exists=False
    def post(self,stream):
        self.sent.append(stream.read())
        if self.fail: raise self.fail
        return '240 Article received'
    def stat(self,mid):
        if not self.exists: raise bridge.nntplib.NNTPTemporaryError('430 not found')
        return '223',1,mid
    def article(self,mid):
        raw=getattr(self,'existing',None) or self.sent[-1]
        return '220',SimpleNamespace(lines=raw.split(b'\r\n'))
    def __enter__(self): return self
    def __exit__(self,*args): return False

class PostingTests(unittest.TestCase):
    def data(self,**extra):
        return dict(group='test.test',name='cNews Test',email='cnews-test@example.invalid',subject='測試',body='繁體中文內容',postId=str(uuid.uuid4()),encoding='big5',images=[],**extra)
    def test_renamed_delivery_identity(self):
        d = self.data()
        current, _ = post.build_article(d, bridge.image_type)
        self.assertTrue(str(current['Message-ID']).startswith('<cnews.'))
        d['postBrand'] = 'yrnewsex'
        legacy, _ = post.build_article(d, bridge.image_type)
        self.assertTrue(str(legacy['Message-ID']).startswith('<yrnewsex.'))
        self.assertIn('yrNewsEx', bridge.article_body(legacy.as_bytes().split(b'\r\n')))
        d['postBrand'] = 'untrusted'
        with self.assertRaises(ValueError): post.build_article(d, bridge.image_type)
    def test_mime_roundtrip_big5_utf8_and_three_images(self):
        d=self.data();d['images']=['data:image/png;base64,iVBORw0KGgo=']*3
        message,encoding=post.build_article(d,bridge.image_type)
        self.assertEqual(encoding,'big5')
        parsed=BytesParser(policy=policy.default).parsebytes(message.as_bytes())
        self.assertEqual(str(parsed['Subject']),'測試')
        content=bridge.article_content(message.as_bytes().split(b'\r\n'))
        self.assertIn('繁體中文內容',content['body']);self.assertEqual(len(content['images']),3)
        d['body']='廣東話 😀';message,encoding=post.build_article(d,bridge.image_type)
        self.assertEqual(encoding,'utf-8');self.assertIn('😀',bridge.article_body(message.as_bytes().split(b'\r\n')))
    def test_images_are_between_new_text_and_quoted_history_on_wire_and_readback(self):
        d=self.data(replyTo='<parent@test>')
        d['body']='我新寫嘅內容\n\nOn 15:00 05/11, Parent wrote:\n> 父訊息 history'
        d['images']=['data:image/png;base64,iVBORw0KGgo=']*2
        message,_=post.build_article(d,bridge.image_type)
        result=bridge.article_content(message.as_bytes().split(b'\r\n'))
        self.assertEqual([p['type'] for p in result['contentParts']],['text','image','image','text'])
        self.assertIn('我新寫嘅內容',result['contentParts'][0]['text'])
        self.assertNotIn('history',result['contentParts'][0]['text'])
        self.assertIn('父訊息 history',result['contentParts'][-1]['text'])
        self.assertIn('我新寫嘅內容',result['body'])
        self.assertIn('父訊息 history',result['body'])
        self.assertEqual(result['contentVersion'],3)
    def test_mime_text_segmentation_does_not_break_duplicate_check(self):
        d=self.data(replyTo='<parent@test>');d['body']='新內容\n\nOn now, Parent wrote:\n> 引用'
        message,_=post.build_article(d,bridge.image_type)
        old=BytesParser(policy=policy.default).parsebytes(message.as_bytes())
        # Same headers/body as the old single-text representation.
        old.clear_content();old.set_content(d['body']+'\n\n-- \ncNews\n',charset='big5',cte='base64')
        self.assertEqual(post.content_signature(message),post.content_signature(old))
    def test_reply_headers_are_actual_parent_chain(self):
        d=self.data(references=['<root@test>','<parent@test>'],replyTo='<parent@test>')
        message,_=post.build_article(d,bridge.image_type)
        self.assertEqual(str(message['References']),'<root@test> <parent@test>')
        self.assertEqual(str(message['In-Reply-To']),'<parent@test>')
    def test_reject_injection_extra_images_and_active_content(self):
        for changes in [dict(subject='hello\r\nNewsgroups: evil'),dict(name='A\nB'),dict(group='test.test,other'),dict(email='bad'),dict(references=['<x>\nY: injected']),dict(replyTo='not-id'),dict(images=['data:image/png;base64,iVBORw0KGgo=']*4),dict(images=['data:image/svg+xml;base64,PHN2Zy8+'])]:
            d=self.data();d.update(changes)
            with self.assertRaises(ValueError): post.build_article(d,bridge.image_type)
    def test_accept_receipt_deduplicates_without_posting_twice(self):
        d=self.data();c=Client()
        a=post.submit(c,d,bridge.image_type);b=post.submit(c,d,bridge.image_type)
        self.assertEqual(a,b);self.assertEqual(len(c.sent),1)
        d['body']='changed'
        with self.assertRaises(post.DuplicatePost): post.submit(c,d,bridge.image_type)
    def test_existing_message_after_restart_is_not_posted_again(self):
        d=self.data();c=Client();c.exists=True;c.existing=post.build_article(d,bridge.image_type)[0].as_bytes()
        self.assertTrue(post.submit(c,d,bridge.image_type)['accepted'])
        self.assertEqual(c.sent,[])
    def test_unknown_result_only_checks_server_and_keeps_same_id(self):
        d=self.data();c=Client();c.fail=TimeoutError('interrupted')
        with self.assertRaises(post.UncertainPost): post.submit(c,d,bridge.image_type)
        c.fail=None
        with self.assertRaises(post.UncertainPost): post.submit(c,d,bridge.image_type)
        self.assertEqual(len(c.sent),1)
        c.exists=True;self.assertTrue(post.submit(c,d,bridge.image_type)['accepted'])
        self.assertEqual(len(c.sent),1)
    def test_duplicate_history_without_readable_article_is_not_success_or_resent(self):
        d=self.data();c=Client();c.fail=bridge.nntplib.NNTPTemporaryError('441 435 Duplicate (Article not posted.)')
        with self.assertRaises(post.DuplicatePost): post.submit(c,d,bridge.image_type)
        with self.assertRaises(post.DuplicatePost): post.submit(c,d,bridge.image_type)
        self.assertEqual(len(c.sent),1)
    def test_duplicate_response_is_success_only_after_matching_article_is_readable(self):
        class LateClient(Client):
            def post(self,stream):
                self.sent.append(stream.read());self.exists=True
                raise bridge.nntplib.NNTPTemporaryError('441 435 Duplicate')
        d=self.data();c=LateClient()
        self.assertTrue(post.submit(c,d,bridge.image_type)['accepted'])
        self.assertEqual(len(c.sent),1)
    def test_same_id_with_different_attachment_does_not_discard_new_photo(self):
        d=self.data();c=Client();c.exists=True;c.existing=post.build_article(d,bridge.image_type)[0].as_bytes()
        d['images']=['data:image/png;base64,iVBORw0KGgo=']
        with self.assertRaises(post.DuplicatePost):post.submit(c,d,bridge.image_type)
        self.assertEqual(c.sent,[])
    def test_post_handler_guards_origin_and_validates_before_connecting(self):
        d=self.data();raw=json.dumps(d).encode()
        class Handler:
            path='/post';headers={'Origin':bridge.ORIGIN,'X-cNews':'reader','Content-Type':'application/json','Content-Length':str(len(raw))};rfile=io.BytesIO(raw)
            def reply(self,status,value):self.result=(status,value)
        h=Handler()
        with patch.object(bridge,'open_client',return_value=Client()) as connect:
            bridge.Handler.do_POST(h);self.assertEqual(h.result[0],200);self.assertEqual(connect.call_count,1)
        h=Handler();h.headers={**h.headers,'Origin':'https://evil.test'}
        with patch.object(bridge,'open_client') as connect:
            bridge.Handler.do_POST(h);self.assertEqual(h.result[0],403);connect.assert_not_called()
