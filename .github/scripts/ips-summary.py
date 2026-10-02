#!/usr/bin/env python3
"""Print the readable part of a crash report (.ips): what killed the process and the
crashed thread's stack. A failed UI test only says the app "does not exist"; the
report next to it on the runner says why (2026-10-02: the templates gallery dies on
GitHub runners and nobody had seen its stack)."""

import json
import sys


def frame_line(frame, images):
    image = images[frame["imageIndex"]] if frame.get("imageIndex", -1) < len(images) else {}
    name = image.get("name") or image.get("path", "?").rsplit("/", 1)[-1]
    symbol = frame.get("symbol")
    if symbol:
        return f"{name}  {symbol} + {frame.get('symbolLocation', 0)}"
    return f"{name}  +{frame.get('imageOffset', 0):#x}"


def main(path):
    with open(path) as handle:
        header_line, _, body_text = handle.read().partition("\n")
    header = json.loads(header_line)
    print(f"{header.get('app_name')} {header.get('app_version', '')} — {header.get('timestamp', '')}")
    if not body_text.strip():
        return
    body = json.loads(body_text)
    images = body.get("usedImages", [])
    print("exception:", json.dumps(body.get("exception", {})))
    if "termination" in body:
        print("termination:", json.dumps(body["termination"]))
    for key in ("asi", "ktriageinfo"):
        if key in body:
            print(f"{key}:", json.dumps(body[key])[:2000])
    backtrace = body.get("lastExceptionBacktrace")
    if backtrace:
        print("last exception backtrace:")
        for index, frame in enumerate(backtrace[:60]):
            print(f"  {index:2} {frame_line(frame, images)}")
    threads = body.get("threads", [])
    crashed = body.get("faultingThread", 0)
    # The crashed thread first, then every other thread: a crash on a worker (a
    # `dispatch_apply` slice) only shows who started the work on the caller's thread.
    order = [crashed] + [index for index in range(len(threads)) if index != crashed]
    for number in order:
        if number >= len(threads):
            continue
        thread = threads[number]
        frames = thread.get("frames", [])
        label = "crashed thread" if number == crashed else "thread"
        print(f"{label} {number} ({thread.get('queue', thread.get('name', ''))}):")
        limit = 80 if number == crashed else 40
        for index, frame in enumerate(frames[:limit]):
            print(f"  {index:2} {frame_line(frame, images)}")


if __name__ == "__main__":
    for argument in sys.argv[1:]:
        try:
            main(argument)
        except (ValueError, KeyError, IndexError) as error:
            print(f"{argument}: not a readable .ips ({error})")
