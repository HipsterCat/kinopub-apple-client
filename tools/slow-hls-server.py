#!/usr/bin/env python3
# A slow CDN for the real-player fixtures: `python3 tools/slow-hls-server.py [seconds]`,
# then launch with `-KINOPUBFixtureStream http://127.0.0.1:8765/slow.m3u8`.
# PlayerTabsUITests.testInfoLeadsTheStripOnAnEarlyDown needs it running.
import http.server, time, sys
# Holds the master playlist back DELAY seconds, then redirects to Apple's sample. Variant
# playlists and segments asked for relative to this server go straight to the same path there.
DELAY=float(sys.argv[1]) if len(sys.argv)>1 else 5
BASE="https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9"
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith("/slow.m3u8"):
            time.sleep(DELAY)
            target=BASE+"/bipbop_16x9_variant.m3u8"
        else:
            target=BASE+self.path
        self.send_response(302); self.send_header("Location", target); self.end_headers()
    def log_message(self,*a): sys.stderr.write("GET %s\n"%self.path)
http.server.ThreadingHTTPServer(("127.0.0.1",8765),H).serve_forever()
