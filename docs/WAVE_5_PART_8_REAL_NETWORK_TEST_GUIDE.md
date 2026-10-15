# W5.8 real network test guide

Owner scope amendment, 2026-10-15: **W5.9 may proceed under revised LAN-first
Wave 5 scope. Direct WAN owner acceptance is deferred to Wave 17.** The original
WAN instructions below remain future-reference material for the historical
W5.8 build. Use the W5.9 guide/compatible kit for current LAN acceptance.
W5.8 automated certification and localhost owner test passed. Two-computer
connectivity is owner-reported with topology/details still to capture; no direct
LAN or WAN PASS is inferred. See the scope amendment and ADR-0008.

Use the exact certified 0.6.0-wave5-w5.8 / protocol 7 build on both PCs.
Historical receipt: **REAL_WAN_OWNER_TEST_REQUIRED = true**. That uncompleted
human WAN requirement is deferred to Wave 17; no historical receipt is rewritten.
Invite and public address are shared privately; omit both from reports.

## LOCALHOST REGRESSION

From repository root:
~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\run_wave_5_part_8_host.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\run_wave_5_part_8_join.ps1
~~~
HOST uses world wave5-w58-owner-test, seed 184552221, canonical owner identity;
JOIN uses the same durable development Client 2 identity. HOST F8 shows the
invite; enter it at JOIN's masked prompt. Same-PC testing is regression only.
F8 opens/closes HOST session panel; Copy Invite copies private connection data.

## LAN TWO-PC TEST

Run HOST normally on PC A. Allow inbound game UDP on its active firewall profile.
Use its LAN/private address on PC B with the portable friend kit:
~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_wave_5_part_8_remote_join.ps1 -Address '<HOST LAN ADDRESS>' -Port 25652
~~~
Enter invite separately. Check shared gameplay, reconnect and HOST F10 removal
of JOIN world. Record whether the PCs were actually separate. No UPnP is needed.

## WAN MANUAL PORT-FORWARD TEST

HOST command remains:
~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\run_wave_5_part_8_host.ps1
~~~
On your router forward external **UDP 25652** to HOST PC private LAN address /
UDP 25652 (or consistently use your chosen Port). Permit inbound HOST/game UDP
on the active Windows firewall profile. Obtain your WAN endpoint from router/ISP
information and share it privately with your friend. No TCP gameplay forwarding.
The host panel/listener does not prove the public route. CGNAT/double NAT may
require ISP/router changes; W5.8 has no relay fallback.

## WAN UPNP TEST

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\run_wave_5_part_8_host.ps1 -EnableUpnp
~~~
HOST F8 shows discovery/mapping/failure and gateway WAN candidate if known.
Mapped means a UDP lease was requested, not proven internet reachability.
Failure keeps HOST running; use manual forwarding. Possible CGNAT/double-NAT
warning is provisional. No unrelated public-IP lookup or firewall mutation.

## FRIEND / REMOTE TESTER

After full automated certification and source commit, build an ignored kit:
~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\build_wave_5_part_8_remote_join_kit.ps1
~~~
Send that whole kit privately. Do not send saves, profiles, logs or invites in
files. Friend extracts to a writable path; Git/Python/Godot installation is not
needed with the bundled Windows runtime. `kit_manifest.json` records source SHA
and hashes. Friend's own stable identity is created locally.

Friend uses a **different internet connection** (different home/ISP or mobile
hotspot). Same router/VPN/overlay does not count as direct WAN.
~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_wave_5_part_8_remote_join.ps1 -Address '<HOST WAN ADDRESS>' -Port 25652
~~~
Invite is a separate masked prompt. First use a wrong invite: private session
denied, no gameplay/world. Then launch with current invite. Play 10–15 minutes:
movement/presence, travel beyond HOST camera, both voxel breaks, drops/pickup,
inventory/placement/crafting, Workbench/storage/Kiln, survival and a contested
single drop (one winner). Record displayed Ping and subjective quality.

Friend leaves/reconnects in the same process: same character. HOST F5 saves
while friend remains connected. HOST F10 saves/exits; friend must leave gameplay
and see Host ended session. HOST restarts with new invite; enter it in ended
screen and Reconnect. Same world-local character/durable state returns. A friend
process restart also requires invite again and retains their local identity.

Record build/SHA, approximate connection types, separate networks, direct method
(manual/UPnP/global IPv6), approximate ping, duration, completed gameplay checks,
contention/reconnect/shutdown/restart, issues and quality (smooth/acceptable/delay/
problematic). No public IP/secret required. Owner acceptance requires this actual
human report for direct WAN acceptance (now deferred to Wave 17). Optional
two-friend smoke is useful. Broader W5.9 local/LAN certification is now authorized
under the amendment above.

## TROUBLESHOOTING

Timeout: verify HOST address/port, UDP forward, listening HOST and firewall;
consider CGNAT/double NAT/restrictive policy. Public route can remain impossible.
Private session denied: wrong, missing or old invite; ask HOST for current code.
Protocol/build mismatch: use exact certified kit. Content mismatch: files differ.
Different world: reconnect-world fence rejected a different world; choose the
intended HOST world. HOST disappearance: session ends; no host migration.

Read-only owner diagnostics:
~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\check_wave_5_part_8_network.ps1 -Port 25652
~~~
The helper changes no router/firewall rules. Routing failures are connectivity
failures; do not weaken gameplay/security rules to work around them.
