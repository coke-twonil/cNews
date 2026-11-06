"""Run the reader and its isolated embed origin together."""
import threading
from reader_server import make_server as make_reader
from embed_server import make_server
from nntp_server import make_server as make_nntp_server

reader = make_reader()
try:
    embeds = make_server()
    nntp = make_nntp_server()
except Exception:
    reader.server_close()
    raise
threading.Thread(target=embeds.serve_forever, daemon=True).start()
threading.Thread(target=nntp.serve_forever, daemon=True).start()
print("Reader: http://127.0.0.1:8765/prototype/", flush=True)
try:
    reader.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    nntp.shutdown()
    nntp.server_close()
    embeds.shutdown()
    embeds.server_close()
    reader.server_close()
