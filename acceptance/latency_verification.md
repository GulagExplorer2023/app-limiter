# Version 0.3.6 latency check

The installed service binary matched the newly built service binary by SHA-256.
The service remained running after the checks. Each run temporarily added a
3 MiB/s upload and download rule for `curl.exe`, compared it with the same
service without that rule, and restored the original configuration bytes.
The restored service reported zero rules.

| Trial | New connection median added | Reused connection median added | Reused connection limited p95 | 4 MiB download | Dropped packets |
| --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 3.325 ms | 0.818 ms | 30.157 ms | 1.201 s | 0 |
| 2 | 1.176 ms | 0.490 ms | 8.950 ms | 1.163 s | 0 |
| 3 | -0.773 ms | 0.687 ms | 8.855 ms | 1.183 s | 0 |

The first trial included one 233.052 ms reused-connection outlier. It did not
recur in the next two trials; the source of that stall is undetermined. The
comparison uses live internet endpoints (`example.com` and Cloudflare's speed
test) and is affected by remote-server and network variation. It shows that
the previous roughly 20 ms idle penalty is not sustained in these controlled
checks, but cannot guarantee a fixed internet RTT or zero jitter on every
machine and connection.

The service recorded immediate packet reinjection, queued paced packets, and
zero packet drops in all three runs. On this Windows installation, creating a
high resolution waitable timer returned error 87, so the paced sender used a
normal waitable timer while requesting 1 ms resolution only when the queue
was active. A local timer probe observed most 2 ms waits completing in roughly
2-3 ms with that request, compared with roughly 16 ms at default resolution.
