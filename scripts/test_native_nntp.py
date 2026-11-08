"""Deterministic localhost NNTP transport fixture; never posts."""
import socketserver
import subprocess
import threading
import sys

class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b'200 Fixture ready\r\n')
        while True:
            line = self.rfile.readline().decode().strip()
            if not line:
                return
            if line == 'POST':
                self.wfile.write(b'340 send article\r\n')
                payload = []
                while True:
                    part = self.rfile.readline()
                    if part == b'.\r\n':
                        break
                    if not part:
                        return
                    if part.startswith(b'..'):
                        part = part[1:]
                    payload.append(part)
                self.posted = b''.join(payload)
                self.wfile.write(b'240 accepted\r\n')
                continue
            elif line.startswith('ARTICLE <'):
                self.wfile.write(b'220 article\r\n' + self.posted + b'.\r\n')
                continue
            elif line == 'LIST ACTIVE':
                response = '215 groups\r\ntest.fixture 3 1 y\r\n.\r\n'
            elif line.startswith('LISTGROUP '):
                response = '211 2 1 3 test.fixture\r\n1\r\n3\r\n.\r\n'
            elif line.startswith('GROUP '):
                self.group = line.split()[1]
                response = '211 2 1 3 test.fixture\r\n'
            elif line == 'OVER 1-1':
                response = '224 headers\r\n1\tRoot\tAuthor\tdate\t<root@fixture>\t\t100\t2\r\n.\r\n'
            elif line == 'OVER 3-3':
                response = '224 headers\r\n3\tRe: Root\tAuthor\tdate\t<reply@fixture>\t<root@fixture>\t100\t2\r\n.\r\n'
            elif line.startswith('HDR ') or line.startswith('XHDR '):
                field = line.split()[1]
                if self.group == 'test.head' or (self.group == 'test.xhdr' and line.startswith('HDR ')):
                    response = '500 unsupported\r\n'
                elif field == 'nntp-posting-host':
                    response = '225 headers\r\n1 192.0.2.24\r\n3 2001:db8::1\r\n.\r\n'
                else:
                    response = '225 headers\r\n.\r\n'
            elif line.startswith('HEAD '):
                response = '221 headers\r\nNNTP-Posting-Host: 198.51.100.18\r\n.\r\n'
            elif line == 'ARTICLE 1':
                response = '220 article\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nHello\r\n..dot stuffed\r\n.\r\n'
            else:
                response = '500 unexpected command\r\n'
            self.wfile.write(response.encode())

with socketserver.TCPServer(('127.0.0.1', 0), Handler) as server:
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        subprocess.run([sys.argv[1] if len(sys.argv) > 1 else '/tmp/cnews-network-tests', str(server.server_address[1])], check=True)
    finally:
        server.shutdown()
