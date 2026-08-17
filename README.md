# PingMenubar

A macOS menubar app that pings a host and shows the round-trip time at a fixed width, so the
menubar never shifts. Green is fine, orange is slow, yellow means DNS failed, red means no replies.

The dropdown adds a latency and packet-loss graph over the last minute, Ethernet and Wi-Fi details,
and a log of the last 20 network changes.

Needs macOS 13 or newer. Build with `make app`, run the checks with `make check`.
