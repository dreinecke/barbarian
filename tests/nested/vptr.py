#!/usr/bin/env python3
"""Minimal zwlr_virtual_pointer_v1 client for driving the nested test compositor.

usage: vptr.py WIDTH HEIGHT cmd...   (WIDTH/HEIGHT = the output layout's extent)
  move X Y        absolute position in layout pixels
  glide X Y N     move there in N steps from the last position
  down / up       left button
  rdown / rup     right button
  sleep MS
"""
import os
import socket
import struct
import sys
import time

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(os.path.join(os.environ["XDG_RUNTIME_DIR"], os.environ.get("WAYLAND_DISPLAY", "wayland-0")))
next_id = [2]


def new_id():
    next_id[0] += 1
    return next_id[0] - 1


def pad_string(text):
    raw = text.encode() + b"\0"
    raw += b"\0" * ((4 - len(raw) % 4) % 4)
    return struct.pack("<I", len(text) + 1) + raw


def send(obj, opcode, payload=b""):
    size = 8 + len(payload)
    sock.sendall(struct.pack("<II", obj, (size << 16) | opcode) + payload)


def read_events(until_callback):
    buf = b""
    globals_ = {}
    done = False
    sock.settimeout(2)
    while not done:
        chunk = sock.recv(65536)
        if not chunk:
            break
        buf += chunk
        while len(buf) >= 8:
            obj, word = struct.unpack("<II", buf[:8])
            size, opcode = word >> 16, word & 0xFFFF
            if len(buf) < size:
                break
            body = buf[8:size]
            buf = buf[size:]
            if obj == 2 and opcode == 0:  # wl_registry.global
                name = struct.unpack("<I", body[:4])[0]
                length = struct.unpack("<I", body[4:8])[0]
                iface = body[8:8 + length - 1].decode()
                off = 8 + length + ((4 - length % 4) % 4)
                version = struct.unpack("<I", body[off:off + 4])[0]
                globals_[iface] = (name, version)
            if obj == until_callback:
                done = True
    return globals_


registry = new_id()           # 2
send(1, 1, struct.pack("<I", registry))       # wl_display.get_registry
callback = new_id()
send(1, 0, struct.pack("<I", callback))       # wl_display.sync
globals_ = read_events(callback)

def bind(iface, version):
    name, have = globals_[iface]
    oid = new_id()
    send(registry, 0, struct.pack("<I", name) + pad_string(iface) + struct.pack("<II", min(version, have), oid))
    return oid

seat = bind("wl_seat", 1)
manager = bind("zwlr_virtual_pointer_manager_v1", 1)
pointer = new_id()
send(manager, 0, struct.pack("<II", seat, pointer))   # create_virtual_pointer

W, H = int(sys.argv[1]), int(sys.argv[2])
args = sys.argv[3:]
start = time.monotonic()
pos = [0, 0]


def ms():
    return int((time.monotonic() - start) * 1000) & 0xFFFFFFFF


def frame():
    send(pointer, 4)


def move(x, y):
    pos[0], pos[1] = x, y
    send(pointer, 1, struct.pack("<IIIII", ms(), int(x), int(y), W, H))
    frame()


def button(code, pressed):
    send(pointer, 2, struct.pack("<III", ms(), code, 1 if pressed else 0))
    frame()


i = 0
while i < len(args):
    cmd = args[i]
    if cmd == "move":
        move(float(args[i + 1]), float(args[i + 2])); i += 3
    elif cmd == "glide":
        tx, ty, n = float(args[i + 1]), float(args[i + 2]), int(args[i + 3])
        fx, fy = pos
        for k in range(1, n + 1):
            move(fx + (tx - fx) * k / n, fy + (ty - fy) * k / n)
            time.sleep(0.016)
        i += 4
    elif cmd in ("down", "up"):
        button(0x110, cmd == "down"); i += 1
    elif cmd in ("rdown", "rup"):
        button(0x111, cmd == "rdown"); i += 1
    elif cmd == "sleep":
        time.sleep(int(args[i + 1]) / 1000); i += 2
    else:
        sys.exit("unknown command " + cmd)
    time.sleep(0.01)

cb = new_id()
send(1, 0, struct.pack("<I", cb))
read_events(cb)
