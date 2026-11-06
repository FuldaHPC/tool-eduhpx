#!/usr/bin/env python3
"""NTP-style clock offset between this node and a server node: clock_offset.py server <port> | client <host> <port>.
Offset = (server clock - client clock), estimated from the sample with the shortest round trip."""
import socket, struct, sys, time

def ns(): return time.time_ns()

if sys.argv[1] == "server":
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("", int(sys.argv[2]))); s.listen(1)
    c, _ = s.accept(); c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    while True:
        d = c.recv(8)
        if not d: break
        t2 = ns(); t3 = ns()
        c.sendall(struct.pack("!qq", t2, t3))
else:
    c = socket.create_connection((sys.argv[2], int(sys.argv[3]))); c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    best = None
    for i in range(400):
        t1 = ns(); c.sendall(b"12345678"); t2, t3 = struct.unpack("!qq", c.recv(16)); t4 = ns()
        rtt = (t4 - t1) - (t3 - t2); off = ((t2 - t1) + (t3 - t4)) / 2
        if best is None or rtt < best[0]: best = (rtt, off)
    print("%s -> server %s: offset (server - client) %+.0f us, round trip %.0f us" % (socket.gethostname(), sys.argv[2], best[1] / 1000, best[0] / 1000))
