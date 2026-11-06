"""Static prototype server. Revalidate source files during local development."""
import functools
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

class ReaderHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()


def make_server():
    root = Path(__file__).resolve().parent.parent
    return ThreadingHTTPServer(('127.0.0.1', 8765), functools.partial(ReaderHandler, directory=str(root)))


if __name__ == '__main__':
    server = make_server()
    print('Reader: http://127.0.0.1:8765/prototype/', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
