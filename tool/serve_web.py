"""Optional local preview with a read-only legacy API bridge.

Usage: python3 tool/serve_web.py --port 8080
Build with: flutter build web --dart-define=DIVAN_API_URL=/legacy/api.php
The normal app path uses the public API directly; this helper is only for
hosts where browser CORS prevents that direct request. The upstream is fixed;
no credentials or write requests are forwarded.
"""
import argparse
import mimetypes
import subprocess
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs, urlencode

ROOT = Path(__file__).resolve().parents[1] / "build" / "web"
UPSTREAM = "http://divanhajghasem.ir"


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        parsed = urlsplit(self.path)
        if not parsed.path.startswith("/legacy/"):
            return super().do_GET()
        path = parsed.path.removeprefix("/legacy")
        if path == "/api.php":
            query = parse_qs(parsed.query)
            if any(key not in {"cat_id", "nid", "latest_news"} for key in query):
                return self.send_error(400)
            if any(len(values) != 1 or not values[0].isascii() or not values[0].isdigit()
                   for values in query.values()):
                return self.send_error(400)
            target = UPSTREAM + path
            if query:
                target += "?" + urlencode({key: values[0] for key, values in query.items()})
        elif (path.startswith("/upload/") and ".." not in path and "%" not in path
              and Path(path).suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp"}):
            target = UPSTREAM + path
        else:
            return self.send_error(404)
        try:
            # curl uses the host's working network route; urllib timed out on
            # this machine. Fixed host + validated path, no shell interpolation.
            result = subprocess.run([
                "curl", "--fail", "--silent", "--show-error", "--compressed", "--max-time", "18",
                "--max-filesize", "16777216", target,
            ], capture_output=True, timeout=20, check=True)
            data = result.stdout
            content_type = "application/json; charset=utf-8" if path == "/api.php" else (
                mimetypes.guess_type(path)[0] or "application/octet-stream")
            self.send_response(200)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)
        except (subprocess.SubprocessError, OSError):
            self.send_error(502, "Upstream temporarily unavailable")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    args = parser.parse_args()
    if not (ROOT / "index.html").exists():
        raise SystemExit("Build the Flutter web app first.")
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Divan preview: http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()
