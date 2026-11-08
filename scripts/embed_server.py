"""Isolated, loopback-only embed renderer. No reader state or credentials here."""
import html
import json
import re
import secrets
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

APP_ORIGINS = {"http://127.0.0.1:8765", "http://localhost:8765"}
API_HOSTS = {"graph.facebook.com", "graph.threads.com", "publish.twitter.com", "publish.x.com"}
SCRIPT_HOSTS = {"www.instagram.com", "platform.instagram.com", "www.threads.com", "www.threads.net", "platform.twitter.com", "platform.x.com", "cdn.syndication.twimg.com", "syndication.twitter.com", "syndication.x.com", "connect.facebook.net"}
FRAME_HOSTS = {"www.instagram.com", "www.threads.com", "www.threads.net", "platform.twitter.com", "platform.x.com", "syndication.twitter.com", "syndication.x.com", "www.facebook.com", "www.youtube.com", "www.tiktok.com", "player.vimeo.com", "open.spotify.com"}
_cache = {}
_cache_lock = threading.Lock()


def descriptor(value):
    """Validate URLs again at the network boundary; never fetch arbitrary URLs."""
    u = urllib.parse.urlsplit(value)
    if u.scheme not in ("https", "http") or u.username or u.password or u.port:
        raise ValueError("Unsupported URL")
    host, path = u.hostname or "", u.path
    host = re.sub(r"^(www|m|mobile)\.", "", host)
    query = urllib.parse.parse_qs(u.query)
    match = re.fullmatch(r"/(p|reel|reels)/([A-Za-z0-9_-]+)/?", path)
    if host == "instagram.com" and match:
        canonical = "https://www.instagram.com/{}/{}/".format("p" if match[1] == "p" else "reel", match[2])
        return {"provider": "instagram", "url": canonical, "api": "https://graph.facebook.com/v25.0/instagram_oembed"}
    match = re.fullmatch(r"/(?:[A-Za-z0-9_]+/status|i/web/status|i/status)/(\d+)/?", path)
    if host in ("x.com", "twitter.com") and match:
        return {"provider": "x", "url": "https://twitter.com" + path.rstrip("/"), "api": "https://publish.x.com/oembed"}
    match = re.fullmatch(r"/share/([A-Za-z0-9_-]+)/?", path)
    if host in ("threads.com", "threads.net") and match:
        return {"provider": "threads", "url": "https://www.threads.com/share/" + match[1], "resolve_share": True}
    match = re.fullmatch(r"/(?:@[^/]+/post|t)/([A-Za-z0-9_-]+)/?", path)
    if host in ("threads.com", "threads.net") and match:
        return {"provider": "threads", "url": "https://www.threads.com/t/" + match[1] + "/", "api": "https://graph.threads.com/oembed"}
    match = re.fullmatch(r"/share/p/([A-Za-z0-9_-]+)/?", path)
    if host == "facebook.com" and match:
        return {"provider": "facebook", "url": "https://www.facebook.com/share/p/" + match[1] + "/", "resolve_share": True}
    if host == "facebook.com" and path == "/story.php":
        author, post = query.get("id", [""])[0], query.get("story_fbid", [""])[0]
        if re.fullmatch(r"\d+", author) and re.fullmatch(r"[A-Za-z0-9_-]+", post):
            return descriptor("https://www.facebook.com/{}/posts/{}/".format(author, post))
    match = re.fullmatch(r"/(?:[A-Za-z0-9._-]+/posts/([A-Za-z0-9_-]+)|reel/(\d+))/?", path)
    if host == "facebook.com" and match:
        endpoint = "oembed_post" if match[1] else "oembed_video"
        return {"provider": "facebook", "url": "https://www.facebook.com" + path, "api": "https://graph.facebook.com/v25.0/" + endpoint}
    video = None
    if host == "youtu.be":
        video = path.strip("/").split("/")[0]
    elif host == "youtube.com":
        video = query.get("v", [None])[0] if path == "/watch" else None
        match = re.match(r"/(?:embed|shorts|live)/([A-Za-z0-9_-]+)", path)
        if match:
            video = match[1]
    if video and re.fullmatch(r"[A-Za-z0-9_-]{11}", video):
        start = query.get("t", query.get("start", ["0"]))[0]
        if not re.fullmatch(r"\d+", start):
            raise ValueError("Invalid timestamp")
        return {"provider": "youtube", "frame": "https://www.youtube.com/embed/{}?autoplay=0&playsinline=1&start={}".format(video, int(start)), "height": 280}
    match = re.fullmatch(r"/@[A-Za-z0-9_.]+/(?:video|photo)/(\d{8,30})/?", path)
    if host == "tiktok.com" and match:
        return {"provider": "tiktok", "frame": "https://www.tiktok.com/player/v1/" + match[1] + "?autoplay=0&description=1&music_info=1", "height": 580}
    match = re.fullmatch(r"/(\d+)(?:/([A-Za-z0-9]+))?/?", path)
    if host == "vimeo.com" and match:
        return {"provider": "vimeo", "frame": "https://player.vimeo.com/video/" + match[1] + "?autoplay=0&dnt=1" + ("&h=" + match[2] if match[2] else ""), "height": 280}
    match = re.fullmatch(r"/(?:intl-[a-z-]+/)?(track|album|playlist|episode|show|artist)/([A-Za-z0-9]{22})/?", path)
    if host == "open.spotify.com" and match:
        return {"provider": "spotify", "frame": "https://open.spotify.com/embed/{}/{}?theme=0".format(match[1], match[2]), "height": 352}
    raise ValueError("No supported embed for this URL")


def safe_url(value, hosts=None):
    if value.startswith("//"):
        value = "https:" + value
    try:
        u = urllib.parse.urlsplit(value)
        if u.scheme != "https" or not u.hostname or u.username or u.password or u.port:
            return None
        if hosts is not None and u.hostname not in hosts:
            return None
        return value
    except ValueError:
        return None


class EmbedHTML(HTMLParser):
    """Keep provider markup, but reject inline scripts/handlers and unknown code."""
    allowed = {"div", "span", "p", "blockquote", "a", "img", "br", "iframe", "svg", "path", "circle", "line", "rect", "time", "strong", "em", "b", "i", "ul", "li"}

    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.output, self.in_script = [], False

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "script":
            self.in_script = True
            src = safe_url(attrs.get("src", ""), SCRIPT_HOSTS)
            if src:
                self.output.append('<script async src="{}"></script>'.format(html.escape(src, quote=True)))
            return
        if self.in_script or tag not in self.allowed:
            return
        clean = []
        for name, value in attrs.items():
            if value is None or name.startswith("on") or name in ("srcdoc", "formaction", "target", "rel"):
                continue
            if name in ("src", "href"):
                value = safe_url(value, FRAME_HOSTS if tag == "iframe" else None)
                if not value:
                    continue
            if name in ("class", "id", "style", "title", "role", "width", "height", "viewbox", "fill", "d", "cx", "cy", "r", "xmlns", "src", "href", "allow", "allowfullscreen", "frameborder", "scrolling") or name.startswith(("data-", "aria-")):
                clean.append('{}="{}"'.format(name, html.escape(value, quote=True)))
        if tag == "iframe" and not any(a.startswith('src="') for a in clean):
            return
        if tag == "a":
            clean.extend(['target="_blank"', 'rel="noopener noreferrer"'])
        self.output.append("<{}{}>".format(tag, " " + " ".join(clean) if clean else ""))

    def handle_endtag(self, tag):
        if tag == "script":
            self.in_script = False
        elif not self.in_script and tag in self.allowed:
            self.output.append("</{}>".format(tag))

    def handle_data(self, data):
        if not self.in_script:
            self.output.append(html.escape(data))

    def handle_entityref(self, name):
        if not self.in_script:
            self.output.append("&" + name + ";")

    def handle_charref(self, name):
        if not self.in_script:
            self.output.append("&#" + name + ";")


class ProviderRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not safe_url(newurl, API_HOSTS):
            raise ValueError("Provider redirected outside the API allowlist")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def resolve_threads_share(url):
    """Resolve official short links only; never follow an arbitrary destination."""
    for _ in range(4):
        if not safe_url(url, {"www.threads.com", "threads.com", "www.threads.net", "threads.net"}):
            raise ValueError("Invalid Threads redirect")
        item = descriptor(url)
        if item["provider"] != "threads":
            raise ValueError("Invalid Threads redirect")
        if not item.get("resolve_share"):
            return item
        request = urllib.request.Request(item["url"], method="HEAD", headers={"User-Agent": "cNews-Prototype/0.1"})
        try:
            with urllib.request.build_opener(NoRedirects()).open(request, timeout=5):
                raise ValueError("Threads share did not redirect to a post")
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307, 308):
                raise
            location = error.headers.get("Location")
            if not location:
                raise ValueError("Missing Threads destination")
            url = urllib.parse.urljoin(item["url"], location)
    raise ValueError("Too many Threads redirects")


def resolve_facebook_share(url):
    """Read only Facebook's official redirects; do not visit login or other sites."""
    for _ in range(4):
        if not safe_url(url, {"www.facebook.com", "facebook.com", "m.facebook.com", "mobile.facebook.com"}):
            raise ValueError("Invalid Facebook redirect")
        item = descriptor(url)
        if item["provider"] != "facebook":
            raise ValueError("Invalid Facebook redirect")
        if not item.get("resolve_share"):
            return item
        request = urllib.request.Request(item["url"], method="HEAD", headers={"User-Agent": "cNews-Prototype/0.1"})
        try:
            with urllib.request.build_opener(NoRedirects()).open(request, timeout=5):
                raise ValueError("Facebook share did not redirect to a post")
        except urllib.error.HTTPError as error:
            if error.code not in (301, 302, 303, 307, 308):
                raise
            location = error.headers.get("Location")
            if not location:
                raise ValueError("Missing Facebook destination")
            url = urllib.parse.urljoin(item["url"], location)
    raise ValueError("Too many Facebook redirects")


def provider_html(item, width=500):
    if item.get("resolve_share"):
        item = (resolve_facebook_share if item["provider"] == "facebook" else resolve_threads_share)(item["url"])
    if "frame" in item:
        return '<iframe src="{}" height="{}" title="{} player" allow="fullscreen; encrypted-media; picture-in-picture" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>'.format(html.escape(item["frame"], quote=True), item["height"], item["provider"])
    api = item["api"] + "?" + urllib.parse.urlencode({"url": item["url"], "maxwidth": max(220, min(700, width)), "dnt": "true"})
    with _cache_lock:
        entry = _cache.get(api)
        if entry and time.monotonic() - entry[0] < 300:
            return entry[1]
    request = urllib.request.Request(api, headers={"Accept": "application/json", "User-Agent": "cNews-Prototype/0.1"})
    response = urllib.request.build_opener(ProviderRedirects()).open(request, timeout=8)
    with response:
        raw = response.read(1024 * 1024 + 1)
    if len(raw) > 1024 * 1024:
        raise ValueError("Provider response too large")
    data = json.loads(raw)
    markup = data.get("html")
    if not isinstance(markup, str) or not markup.strip() or len(markup) > 512 * 1024:
        raise ValueError("Provider did not return an embed")
    parser = EmbedHTML()
    parser.feed(markup)
    result = "".join(parser.output)
    with _cache_lock:
        if len(_cache) >= 128:
            _cache.pop(next(iter(_cache)))
        _cache[api] = (time.monotonic(), result)
    return result


def render_document(markup, origin, token, failed=False):
    nonce = secrets.token_urlsafe(20)
    # Parent gets status/height only. Never expose reader state or accept a
    # URL/navigation command through this postMessage channel.
    control = """
const target=ORIGIN,token=TOKEN;let ready=false;
function report(status){parent.postMessage({type:'cnews-embed',token,status,height:Math.max(100,Math.min(1800,Math.ceil(document.body.getBoundingClientRect().height)))},target)}
function inspect(){for(const frame of document.querySelectorAll('iframe')){if(!frame.dataset.observed){frame.dataset.observed='1';frame.addEventListener('load',()=>{ready=true;report('ready')});frame.addEventListener('error',()=>report('error'))}}if(ready)report('ready')}
new MutationObserver(inspect).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['style','height','src']});
new ResizeObserver(()=>{if(ready)report('ready')}).observe(document.body);
window.addEventListener('message',e=>{const frames=[...document.querySelectorAll('iframe')];if(!frames.some(f=>f.contentWindow===e.source))return;let data=e.data;try{if(typeof data==='string')data=JSON.parse(data)}catch{return}if(data?.['x-tiktok-player']&&data.type==='onPlayerError')report('error')});
window.addEventListener('load',()=>{if(document.querySelector('iframe')){ready=true;report('ready')}});
inspect();setTimeout(()=>{if(!ready)report('error')},12000);INITIAL
""".replace("ORIGIN", json.dumps(origin)).replace("TOKEN", json.dumps(token)).replace("INITIAL", "report('error');" if failed else "")
    document = '<!doctype html><html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}body{display:flow-root}iframe{display:block;border:0;width:100%;min-width:0!important;max-width:100%!important}blockquote{min-width:0!important;max-width:100%!important;box-sizing:border-box}a{color:#0a84ff}</style><body>' + markup + '<script nonce="' + nonce + '">' + control + '</script></body></html>'
    scripts = " ".join("https://" + h for h in sorted(SCRIPT_HOSTS))
    frames = " ".join("https://" + h for h in sorted(FRAME_HOSTS))
    csp = "default-src 'none'; script-src 'nonce-{}' {}; style-src 'unsafe-inline' https:; frame-src {}; connect-src https:; img-src https: data:; media-src https: blob:; font-src https: data:; base-uri 'none'; form-action 'none'; frame-ancestors {}".format(nonce, scripts, frames, " ".join(sorted(APP_ORIGINS)))
    return document.encode("utf-8"), csp


class EmbedHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        if parsed.path != "/embed":
            self.send_error(404)
            return
        params = urllib.parse.parse_qs(parsed.query)
        origin, token = params.get("origin", [""])[0], params.get("token", [""])[0]
        if origin not in APP_ORIGINS or not re.fullmatch(r"[A-Za-z0-9-]{12,80}", token):
            self.send_error(400, "Invalid embed context")
            return
        failed = False
        try:
            item = descriptor(params.get("url", [""])[0])
            width = max(220, min(700, int(params.get("width", ["500"])[0])))
            markup = provider_html(item, width)
        except Exception:
            # Private/deleted/rate-limited/provider failures all retain the
            # original link in the reader; do not substitute invented content.
            failed, markup = True, ""
        data, csp = render_document(markup, origin, token, failed)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Content-Security-Policy", csp)
        self.send_header("Referrer-Policy", "strict-origin-when-cross-origin")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass  # URLs may come from private articles. Do not log them.


def make_server():
    return ThreadingHTTPServer(("127.0.0.1", 8766), EmbedHandler)


if __name__ == "__main__":
    server = make_server()
    print("Embed renderer: http://127.0.0.1:8766", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
