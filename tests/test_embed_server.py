import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("embed_server", Path(__file__).resolve().parent.parent / "scripts" / "embed_server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class EmbedTests(unittest.TestCase):
    def test_provider_routes(self):
        cases = [
            ("https://www.instagram.com/p/abc/", "instagram"),
            ("https://www.threads.net/@threads/post/abc/", "threads"),
            ("https://x.com/user/status/12345", "x"),
            ("https://www.facebook.com/user/posts/pfbid123/", "facebook"),
            ("https://youtu.be/M7lc1UVf-VE?t=80", "youtube"),
            ("https://www.tiktok.com/@scout2015/video/6718335390845095173", "tiktok"),
            ("https://vimeo.com/76979871/abc123", "vimeo"),
            ("https://open.spotify.com/track/0Lr4kGOYn9l83EjuK6cZFQ", "spotify"),
        ]
        for url, provider in cases:
            self.assertEqual(server.descriptor(url)["provider"], provider)

    def test_threads_share_resolution(self):
        source = "https://www.threads.com/share/BAVHcta3-N"
        self.assertTrue(server.descriptor(source)["resolve_share"])
        redirect = server.urllib.error.HTTPError(source, 302, "Found", {"Location": "https://www.threads.com/@x.5irius/post/DfUyW25Eroh?tracking=1"}, None)
        with patch.object(server.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = redirect
            result = server.resolve_threads_share(source)
            self.assertEqual(result["url"], "https://www.threads.com/t/DfUyW25Eroh/")
            self.assertEqual(build.return_value.open.call_count, 1)
        for target in ["http://127.0.0.1/private", "https://evil.test/", "https://www.threads.com/", "https://www.threads.com@evil.test/share/a"]:
            redirect.headers = {"Location": target}
            with patch.object(server.urllib.request, "build_opener") as build:
                build.return_value.open.side_effect = redirect
                with self.assertRaises(ValueError):
                    server.resolve_threads_share(source)
                self.assertEqual(build.return_value.open.call_count, 1)

    def test_facebook_share_resolution(self):
        source = "https://www.facebook.com/share/p/1LLk5pK1q8/"
        self.assertTrue(server.descriptor(source)["resolve_share"])
        redirect = server.urllib.error.HTTPError(source, 302, "Found", {"Location": "https://www.facebook.com/story.php?story_fbid=1671629630999953&id=100044587952620&mibextid=tracking"}, None)
        with patch.object(server.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = redirect
            result = server.resolve_facebook_share(source)
            self.assertEqual(result["url"], "https://www.facebook.com/100044587952620/posts/1671629630999953/")
            self.assertEqual(build.return_value.open.call_count, 1)
        for target in ["http://127.0.0.1/private", "https://evil.test/", "https://www.facebook.com/login/?next=https://evil.test", "https://user:pass@www.facebook.com/a/posts/123"]:
            redirect.headers = {"Location": target}
            with patch.object(server.urllib.request, "build_opener") as build:
                build.return_value.open.side_effect = redirect
                with self.assertRaises(ValueError):
                    server.resolve_facebook_share(source)
                self.assertEqual(build.return_value.open.call_count, 1)

    def test_no_arbitrary_fetch(self):
        for url in ["http://127.0.0.1/private", "http://169.254.169.254/", "https://instagram.com.evil.test/p/abc/", "https://user:pass@www.instagram.com/p/abc/", "https://www.instagram.com:8765/p/abc/", "file:///private/test"]:
            with self.assertRaises(ValueError):
                server.descriptor(url)
        self.assertIsNone(server.safe_url("https://evil.test/", server.API_HOSTS))

    def test_sanitizer(self):
        parser = server.EmbedHTML()
        parser.feed('<script>alert(1)</script><script src="https://evil.test/x.js"></script><script async src="https://www.instagram.com/embed.js"></script><img src="https://example.com/image.jpg" onerror="alert(1)"><a href="javascript:alert(2)">link</a><iframe src="http://127.0.0.1/private"></iframe>')
        output = "".join(parser.output)
        self.assertNotIn("alert(", output)
        self.assertNotIn("evil.test", output)
        self.assertNotIn("127.0.0.1", output)
        self.assertIn("https://www.instagram.com/embed.js", output)
        self.assertIn('rel="noopener noreferrer"', output)

    def test_current_official_provider_script_hosts(self):
        parser = server.EmbedHTML()
        parser.feed('<script async src="//platform.instagram.com/en_US/embeds.js"></script><script async src="https://platform.x.com/widgets.js"></script>')
        output = "".join(parser.output)
        self.assertIn("https://platform.instagram.com/en_US/embeds.js", output)
        self.assertIn("https://platform.x.com/widgets.js", output)
        self.assertEqual(server.descriptor("https://x.com/user/status/12345")["api"], "https://publish.x.com/oembed")

    def test_isolated_document_and_error_signal(self):
        doc, csp = server.render_document("", "http://127.0.0.1:8765", "test-token-123456", failed=True)
        self.assertIn(b"report('error');", doc)
        self.assertIn(b"test-token-123456", doc)
        self.assertIn("frame-ancestors http://127.0.0.1:8765", csp)
        self.assertIn("base-uri 'none'", csp)
        self.assertIn("script-src 'nonce-", csp)
        self.assertNotIn("script-src 'unsafe-inline'", csp)

    def test_provider_error_does_not_create_fake_post(self):
        with patch.object(server.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = TimeoutError("provider timed out")
            with self.assertRaises(TimeoutError):
                server.provider_html(server.descriptor("https://www.instagram.com/p/timeout-test/"))

    def test_requests_actual_article_width(self):
        with patch.object(server.urllib.request, "build_opener") as build:
            build.return_value.open.return_value.read.return_value = b'{"html":"<blockquote>Fixture</blockquote>"}'
            server.provider_html(server.descriptor("https://www.threads.com/t/width-test/"), 370)
            request = build.return_value.open.call_args.args[0]
            query = server.urllib.parse.parse_qs(server.urllib.parse.urlsplit(request.full_url).query)
            self.assertEqual(query["maxwidth"], ["370"])


if __name__ == "__main__":
    unittest.main()
