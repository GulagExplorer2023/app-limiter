# Bidirectional cap feasibility spike

Status: **passed on this Windows 11 machine** on 2026-09-25. This is a
backend proof, not the finished desktop application.

## Backend decision

The spike uses [WinDivert 2.2.2-A](https://github.com/basil00/WinDivert/releases/tag/v2.2.2),
downloaded from the author's release. The archive SHA-256 is
`63CB41763BB4B20F600B6DE04E991A9C2BE73279E317D4D82F237B150C5F3F15`.
The included `WinDivert64.sys` signature verifies on this machine. The
package is dual licensed under LGPL 3.0 or GPL 2.0; the planned distribution
uses the LGPL 3.0 option and retains its bundled `LICENSE` and source link.

WinDivert uses a signed kernel driver plus a user mode DLL. The service
process that calls `WinDivertOpen` must run with administrator rights.
The Lazarus panel can stay unelevated. Windows 11 is not named in the
2.2 documentation, so compatibility is established by the test below rather
than assumed from the documentation. Rebuilding the driver would require
Windows driver signing; the pinned package already includes a signed driver.

WinDivert's FLOW layer reports process identity, while its NETWORK layer
captures and reinjects packets in either direction. The spike joins flow
events to packets by protocol, IP family and local/remote ports, then delays
the target executable's packets using one aggregate schedule per direction.
Its queue is bounded to 2 MiB and 1.5 seconds of scheduled delay. The
probe exits after a fixed duration, closing its capture handles.

## Observed proof

Target executable: `C:\Windows\System32\curl.exe`.
Endpoint: Cloudflare's public `__down` and `__up` speed test endpoints.
Each transfer moved 1,000,000 application bytes. Configured cap:
128 KiB/s = 131,072 B/s in each direction.

| Direction | Baseline | With cap | Observed capped rate |
| --- | ---: | ---: | ---: |
| Download | 0.526 s, 1,901,072 B/s | 8.162 s | 122,523 B/s |
| Upload | 0.181 s, 5,538,693 B/s | 8.119 s | 123,169 B/s |

The capped run logged two matching `curl.exe` TCP flows. It queued and sent
1,085,882 inbound bytes and 1,080,367 outbound bytes, with zero dropped
packets. Packet totals include protocol overhead and traffic in the reverse
direction, so they exceed the application payload size. Rates are below the
configured cap because handshake latency and scheduling overhead are included.

## Scope and remaining engineering

The probe is intentionally single-rule and short lived. It proves that both
directions can be delayed for a process identified by full executable path.
It does not yet provide a persistent service, multi-rule aggregation, a
desktop panel, an installer, or full acceptance testing. Flow events that
predate opening the FLOW handle are not reported by WinDivert. The spike's
port-based join could collide with another flow that happens to use the same
ports and IP family; the production engine needs the full 5-tuple. It excludes
loopback packets. VPNs and tunnels may alter attribution, and LAN versus
internet classification still needs implementation.

Sources: [WinDivert documentation](https://github.com/basil00/WinDivert/blob/v2.2.2/doc/windivert.html),
[WinDivert license](https://github.com/basil00/WinDivert/blob/v2.2.2/LICENSE),
[Cloudflare speed-test endpoints](https://github.com/cloudflare/speedtest/blob/main/README.md).
