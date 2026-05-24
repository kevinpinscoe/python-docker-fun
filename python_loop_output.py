# Kevin test loop
# Used for debugging and testing Kubernetes pods

import os
import signal
import sys
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

version = "4.0"

POD_NAME      = os.getenv("POD_NAME", "unknown")
POD_NAMESPACE = os.getenv("POD_NAMESPACE", "unknown")
NODE_NAME     = os.getenv("NODE_NAME", "unknown")

shutdown_event = threading.Event()


def handle_shutdown(signum, frame):
    current_time = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"[{current_time}] Received signal {signum}, shutting down gracefully...")
    shutdown_event.set()


signal.signal(signal.SIGTERM, handle_shutdown)
signal.signal(signal.SIGINT, handle_shutdown)


class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # suppress HTTP access logs


threading.Thread(target=lambda: HTTPServer(("", 8080), HealthHandler).serve_forever(), daemon=True).start()

print(f"Version {version} starting | pod={POD_NAME} namespace={POD_NAMESPACE} node={NODE_NAME}")
print(f"Health endpoint listening on :8080/health")

i = 0
while True:
    current_time = datetime.now(timezone.utc).strftime("%H:%M:%S")
    print(f"Version: {version}: [{i}] pod={POD_NAME} node={NODE_NAME} Current Time = {current_time}")
    i += 1
    if shutdown_event.wait(timeout=60):
        break

print(f"[{datetime.now(timezone.utc).strftime('%H:%M:%S')}] Shutdown complete.")
sys.exit(0)
