# App Limiter release review

## Code findings and fixes

- Flow entries used open addressing with deletion markers. A long-running
  service could accumulate enough deleted entries for misses to scan the
  whole table; a full table could replace a live entry. The service now
  compacts the table after 4096 deleted entries and rejects insertion when
  all slots are live. `flowTableRebuilds` and `flowTableFull` expose both
  conditions in backend state.
- The tray Exit fallback could close the panel even if its pause setting
  failed to save. It now remains open and shows the save error.
- Packet reinjection failures and short sends are now counted as dropped
  packets in status, for both immediate and queued sends.
- The installer's non-admin platform check depended on WMI, which was denied
  in this environment. It now reads the native architecture through
  `IsWow64Process2` and the OS build through the Windows runtime.
- NSIS `ExecShellWait` could not report the elevated installer's exit code.
  Setup now waits on the elevated process handle and propagates failure to
  silent deployment tools.
- The service recomputed both sides of its active-limit comparison at the
  current time, so a weekly schedule edge could leave the network capture
  handle in the previous mode until another event woke it. It now compares
  the new mode with the previously requested mode and switches on schedule
  transitions.
- The first 1.0.0 setup exposed a Windows PowerShell 5.1 incompatibility:
  `[ushort]` was not recognized in its platform check. The script now uses
  `[System.UInt16]` and the platform check has been run with the Windows
  PowerShell executable used by setup.

## Local verification

- The service compiled with FPC `-O2 -Xs`; the Lazarus panel compiled in its
  `Release` mode with `-O3 -Xs`, without debug information.
- `flow_table_test` passed with range checking enabled. It exercises
  compaction, deletion, filling the table, and refusal to overwrite a live
  flow.
- Destination parser and rule schedule/quota tests passed.
- A schedule mode test passed with an unchanged configuration and a simulated
  prior capture mode on each side of a schedule transition.
- Speed limit dialog, compact panel/activity layout, and quota dialog smoke
  checks passed at 168 DPI with simulated compact window sizes.
- The package build validated x64 PE machine types, version 1.0.0.0 in both
  executables, the signed WinDivert driver, and the pinned NSIS compiler.
  The generated SHA-256 file matches the setup EXE.
- `IsWow64Process2` returned native x64 on this Windows 11 build 26200
  machine without administrator rights.
- A silent NSIS probe used the same process-wait helper with a non-elevated
  `cmd.exe` exit code of 7; the helper returned 7. Manual UAC installation
  succeeded; unattended UAC deployment remains untested.
- The user installed the corrected 1.0.0 setup on the development machine.
  Both installed executables report file version 1.0.0.0, the installed
  service hash matches the release build, and the service runs with a live
  backend state file.
- Against that installed service, the 3 MiB/s curl rule yielded a 0.709 ms
  median added time on reused HTTPS connections. A 4 MiB transfer completed,
  1098 packets used immediate reinjection, 1737 were queued, and zero were
  dropped. The test restored the original empty rule set.
- An installed-service schedule test activated a curl rule and observed the
  service switch back to monitoring at the next minute boundary with zero
  dropped packets. It restored the original empty rule set.

## Deployment boundary

This build targets Windows 11 x64 on Intel and AMD CPUs. The 1.0.0 installer
has not been installed and exercised on a separate clean computer. A machine
with Windows on ARM needs a native ARM64 driver and a separate build. The
installer, panel, service, and WinDivert DLL are unsigned; only the bundled
WinDivert driver currently has a valid signature. Code signing and clean
machine install/upgrade/uninstall checks remain before broad distribution.
The controlled UDP and IPv6 upload checks in `README.md` remain open.

## Version 1.1.0 startup option

- Settings now has one dialog with checkboxes for starting with Windows,
  starting minimized, and dark theme, plus the shortcut field. At 300×250
  logical pixels, the dialog keeps its buttons visible and scrolls its fields.
- The startup checkbox reads and writes the current user's Windows Run entry.
  The executable path is quoted, and the entry can be removed by unchecking
  the box. The service already has automatic startup; this entry launches the
  user panel at sign-in.
- A registry test created, read, and removed a separate acceptance value. A
  Settings integration test checked the option, saved it, reopened Settings,
  unchecked it, and verified removal. It used a workspace-only config and a
  test registry value; neither the installed rules nor the real startup value
  changed. The compact Settings layout check also passed.
- The uninstaller is set to remove the matching startup entry for the recorded
  installing account. This cleanup needs a full uninstall check on a separate
  test computer.
- The user installed the 1.1.0 package on the development computer. Both
  installed executable hashes match the release build, both report version
  1.1.0.0, the service is running, and the existing Firefox rule is active.
  The startup box is initially unchecked because the real per-user Run value
  is absent. The separate acceptance registry value is absent too.

## Version 1.2.0 installer and parental mode

- Setup now includes a directory page for a dedicated folder directly under
  Program Files and an options page with desktop shortcut and start-with-Windows
  boxes checked by default. Both selections are passed to the installer script.
- The install script creates or removes the all-users desktop shortcut and the
  recorded account's Run entry. It secures the installation directory for a
  system service and handles upgrades to a different permitted folder. The
  uninstaller uses the registered location and removes only named app files.
- Settings uses a native light control surface so checkbox labels remain
  readable even when the main panel uses the dark theme. Parental mode persists
  in config and hides the tray icon and its Exit menu. The keyboard shortcut
  remains available to reopen the panel.
- The 1.2.0 panel and service compile in release mode; both report 1.2.0.0.
  The installer reports 1.2.0 and has a SHA-256 file. PowerShell script syntax,
  compact Settings layout, parental-mode save/hidden-tray checks, and the
  Settings startup registry save/remove checks passed using workspace-only
  acceptance data and a dedicated temporary Run value. A real 1.2.0 upgrade and interactive
  installer choices still need checking on the installed Windows session.

## Version 1.3.0 visible launch and app block

- An interactive setup starts the panel after Finish. When setup elevates from
  a standard-user session, the original user process starts it; the elevated
  installer does not launch a duplicate. Silent setup does not open the UI.
  The `--show` launch flag overrides the normal start-minimized setting.
- Rules now store a separate `blocked` flag. Blocking is independent of the
  speed sliders, applies to attributed TCP/UDP packets in both directions,
  and remains active while speed limits are paused. The list and right-click
  menu show Blocked and provide an Unblock action. Existing rates are retained.
- Release binaries and installer build with version 1.3.0. The show override
  test passed with and without `--show`; the block button saved and cleared the
  rule without changing rates; packet tests dropped both inbound and outbound
  UDP packets; and compact layout checks passed. These used isolated acceptance
  configuration. A real 1.3.0 upgrade and setup Finish launch remain to be
  verified on an installed Windows session.

## Version 1.3.1 Settings size

- Settings now opens at 480 × 460 client pixels. On the development display
  at 168 DPI, all fields fit above the footer with a lower margin. The 300 ×
  250 compact layout still keeps the buttons reachable and the controls
  within the available width. Release binaries and installer report 1.3.1.

## Version 1.3.2 code review and cleanup

- Saved rules were first read by the status worker after packet workers had
  started. Startup now loads history and rules before opening packet workers,
  so a saved block selects the diverting mode from the first network open.
- The config writer could save duplicate executable paths or a bad shortcut
  that the reader would reject later. Both paths now use the same validation,
  and Windows path equality is shared by the reader, writer, service, and UI.
- Negative history counters could wrap to huge unsigned values and falsely
  exhaust a quota. They now load as zero; quota accumulation saturates rather
  than wrapping when a damaged history has extremely large counters, while
  remaining within the signed range used by the state JSON.
- Worker creation could fail partway through startup, leaving shutdown to
  dereference a missing thread. Shutdown now accepts a partially initialized
  worker set, and the packet sender starts before network capture can queue.
- Direct uninstallation now defaults to the registered custom install folder
  and validates it before writing an uninstall log. The unelevated setup
  parent removes its Windows startup entry only when it still points to this
  installation. Direct uninstall closes its transcript before removing the
  final log and empty folder.
- Range-checked regression tests passed for packet blocking, flow table
  rollover, weekly schedules, domain parsing, and the new persistence cases.
  The persistence test also simulates cleanup after partial worker startup.
  Isolated GUI smoke checks passed for limits, quota layout, responsive layout
  at 168 DPI, block actions, parental mode, setup show, and Settings. The
  quota smoke check needs a pinned app in its test config; the initial run
  without that fixture failed as expected, then passed after the block-action
  test created one. PowerShell installer scripts parsed without errors.
- The release build used FPC `-O2 -Xs` for the service and Lazarus `Release`
  with `-O3 -Xs` for the panel. Both binaries report 1.3.2.0, the installer
  reports 1.3.2, the bundled WinDivert driver signature is valid, and the
  generated SHA-256 file matches the installer. NSIS compiled without warnings.

The 1.3.2 build is a local review build. The runtime packet checks are
synthetic and do not replace a fresh install, upgrade, uninstall, and traffic
test on a separate Windows 11 x64 computer. Flow attribution can miss
connections that predate service startup, and unknown process traffic remains
unattributed. The clean-machine and controlled UDP/IPv6 checks listed above
remain open before broad distribution.

## Version 1.3.3 Excel export

- The Network activity window now saves its currently visible rows to `.xlsx`.
  The file contains the app path, date, domain or IP, remote IP, source, and
  separate download and upload byte columns. Its header stays frozen and
  Excel filters are enabled. Text is stored as text, including values that
  begin with `=`, and large byte counters keep their exact digits.
- A range-checked FPC export fixture generated a workbook containing escaped
  XML characters, a non-ASCII name, numeric byte totals, and a 19-digit
  counter. An independent `openpyxl` reader validated all values and cell
  types, the frozen header, the filter range, and the ZIP archive. Export also
  succeeded to a Windows filename containing a non-ASCII character.
- `build-installer.ps1` built the release panel, service, and 1.3.3 setup EXE.
  Both executables and setup report version 1.3.3; the signed WinDivert driver
  passed the signature check. The setup SHA-256 is
  `cacce4247ee30f3f3bff21fa1d931c8d50221d7c0152233a9ce7fb44f1298321`.
  The installer has not been run on a clean machine for this version.

## Version 1.3.4 parental PIN and single instance

- Enabling parental mode in Settings now opens a PIN and confirmation dialog
  after Save. The 6 to 12 digit PIN is stored as a random-salt PBKDF2-SHA256
  verifier, never as plain text. Disabling parental mode requires the PIN.
  Older parental-mode configurations with no verifier load with the mode off
  so the owner can set a PIN.
- The panel now keeps one instance per Windows session. Launching it again in
  parental mode signals the running panel to request its PIN before opening.
  The configured keyboard shortcut follows the same rule when the panel is
  hidden. With parental mode off, the second launch reports that App Limiter
  is already running. The Windows startup entry passes `--startup`, so
  parental mode starts hidden without a sign-in prompt.
- Range-checked tests passed for PIN generation, wrong-PIN rejection,
  randomized salts, config persistence, legacy config migration, and the
  two-process launch request. An isolated GUI smoke test enabled parental
  mode through Settings, entered and confirmed the PIN, closed the panel,
  and reopened it from a launch request with the correct PIN. The same smoke
  test verified that a fresh manual launch asks for the PIN and a Windows
  `--startup` launch stays hidden. Installer scripts passed PowerShell syntax
  parsing.
- The release panel and service report 1.3.4.0. The 1.3.4 installer SHA-256
  matches its checksum file:
  `0a5e53454977e4619542c6214f48e41f4144a4ebc77eafe402c1764dfb8b438e`.
  The bundled WinDivert driver signature is valid. This installer has not
  been run on a clean Windows machine yet.

## Version 1.3.5 PIN spacing and scheduled/quota blocking

- The parental PIN dialog positions its instruction, input fields, confirm
  label, and buttons after Windows applies display scaling. The isolated GUI
  smoke test checked that the controls do not overlap and captured the
  resulting dialog for visual inspection. PIN setup, hidden tray, unlock, and
  startup checks passed.
- The Schedule / quota window has independent options to block internet
  outside allowed hours and after the data quota. Rule validation and JSON
  persistence reject blocking without an enabled schedule or a nonzero
  quota, respectively. An isolated GUI test checked the compact scrolling
  300-pixel layout, including checkbox text fit, and saved both options
  without requiring a post-quota slow speed.
- Deterministic schedule/quota checks and synthetic TCP/UDP packet checks
  passed, including download and upload drops while ordinary speed limits
  are paused. The block rule test runs with the pinned WinDivert DLL in its
  test folder. Blocking still depends on process attribution; connections
  established before service startup can remain unattributed.
- The release panel and service report 1.3.5.0. The setup reports 1.3.5,
  its SHA-256 file matches the EXE, and the bundled driver signature is valid.
  Setup SHA-256:
  `d8cc9abf367da0832dce99a3e677df2ab800c882427c1bf15298ca4cc99218be`.
  This installer has not been run on a clean Windows machine yet.

## Version 1.3.6 program totals and computer-wide quota

- The main panel shows download plus upload since the selected program's
  current run began. The service keeps a process handle for each observed
  instance of an executable, aggregates concurrent instances, and resets the
  displayed total after all of them exit and a new instance connects.
- With no app selected, Schedule / quota edits a computer-wide rule. The
  service applies its schedule block or post-quota block/throttle to
  attributed and unattributed Internet packets in both directions. Local
  network packets are excluded from the computer-wide quota and its effects.
  Computer-wide quota usage persists in the daily usage history across
  service restarts.
- The quota dialog has separate amount and post-quota speed sliders. The
  leftmost amount position is ∞ (no quota); the leftmost speed position is
  unlimited. Numeric fields remain editable, and saving an untouched rule
  preserves its exact stored quota and speed values.
- Synthetic packet and config tests passed for computer-wide upload/download
  accounting, persisted usage, unattributed blocking, schedule blocking,
  throttling, local network exclusion, and program restart totals. Existing
  app blocking and schedule tests passed. An isolated GUI smoke test saved
  app and computer-wide quotas through the sliders and checked compact layout.
- Release panel and service both report 1.3.6.0. The bundled driver signature
  is valid, and the setup SHA-256 matches its checksum file:
  `be6fae963463988584be12206e17f96ed1ebab5712eba458e64fbb5ed459131b`.
  Live throughput with an active computer-wide quota and a clean-machine
  installation of this package remain to be verified.

## Version 1.3.7 backend continuity

- Windows System log recorded repeated App Limiter Service unexpected
  terminations (event 7031) during the reported session, including 11:20:04
  on 2026-09-27, just before the supplied screenshot. Earlier builds called
  `ExitProcess(1)` for status publication and flow receive failures without
  durable diagnostics. A temporary state-file sharing conflict is a plausible
  trigger: an isolated test holding the state file open reproduced a failed
  atomic replacement. The old release did not log which worker caused each
  termination, so the exact trigger of the observed events is unconfirmed.
- State, destination, and history publication now retry temporary Windows
  sharing conflicts. A failed state or destination publication is logged and
  retried on the next status cycle without terminating network enforcement.
  The flow worker reopens its capture handle after a receive error. Fatal
  worker paths write a bounded `backend.log` before Windows service recovery.
  Setup configures 1-second then 5-second fallback restarts. Old usage days
  are pruned at midnight, and inactive application and unreferenced
  destination slots can be reused after their bounded caches fill.
- The backend checkpoints per-program totals with process ID and creation
  time. At startup it restores totals only for processes with matching
  executable path and creation time, preventing PID reuse from reviving an
  old run. The panel keeps last-known rows when backend state is stale and
  marks enforcement status unknown instead of declaring limits inactive.
- Six backend acceptance checks passed: global quotas, app blocks, flow-table
  compaction, persistence, schedule transitions, and service recovery. The
  recovery check reproduced a locked state file, confirmed publication
  recovers afterward, rejected a stale process identity, and completed 5,000
  state publications. Cache reuse and 90-day history pruning passed. Responsive
  panel layout and a stale-state UI check passed at 168 DPI. A one-minute baseline check of the
  previously installed 1.3.6 service found no stale samples or restarts; that
  short observation is not evidence of long-run reliability for 1.3.7.
- Release panel and service both report 1.3.7.0; setup SHA-256 matches its
  checksum file and the bundled driver signature is valid. Setup SHA-256:
  `87da583cf39e62b271a99ce96e9d3fef45dce183273ec3168a7c463656b72a9f`.
  After installing 1.3.7, a controlled four-second read lock on the live
  state file produced `Cannot publish state (5)` in `backend.log`, followed by
  `State publication recovered` when the lock was released. The state resumed
  within two seconds and no service crash event occurred. The installed
  1.3.7 service then ran from 12:32:02 to 12:42:04 with 121 five-second
  samples, zero stale samples, zero detected counter resets, and zero service
  crash events. The oldest sampled state was 2.08 seconds old during the
  intentional file lock. Results are in `acceptance/backend-soak-1.3.7.csv`.
  This ten-minute run and fault injection verify recovery from the reproduced
  publication conflict; a multi-hour run is still needed to assess the
  previously sporadic terminations under normal use.

## Version 1.3.8 main window fit

- The main list now uses the space left after reserving the action buttons,
  details, and bottom navigation. At the normal 460-by-680 logical size it
  leaves the bottom controls within the window; compact displays still scroll
  when the minimum readable list height cannot fit.
- The responsive layout smoke test passed at 168 DPI for 460-by-680,
  460-by-900, and compact sizes. The rendered 460-by-900 panel shows all
  controls without an outer scrollbar.
- Release panel and service report 1.3.8.0. The installer SHA-256 is
  `a9c4314a64f18e74bb32ac9640bb26818a42d3fbaa6a933d8a1bf92f8d7da57c`.
  After installation, both installed executables report 1.3.8.0 and their
  hashes match the packaged payload. Backend state continues updating.

## Version 1.3.9 release sanity

- Offline backend checks passed for computer-wide quotas, app blocking,
  flow-table compaction, persistence, schedule transitions, and service
  recovery. UI checks passed for responsive layout, stale state, quota
  controls, Settings, parental PIN, block/unblock, and the install-show
  override. Destination parsing, PIN verification, single-instance requests,
  and `.xlsx` export also passed. The workbook XML contains a formula-like
  name as text with no formula element.
- A synthetic full-capacity workload used 1024 apps and 16,384 destinations.
  Destination serialization took about 250-282 ms on this PC. Before the
  change, that work held the shared packet lock; now a calibrated lock probe
  detected no measurable wait during serialization (0 ms versus 109-125 ms
  when deliberately held). Tables with 4096 or more destinations publish at
  most every five seconds. A 2000-packet, 1500-byte queued burst completed
  without test drops. These are local synthetic measurements, not throughput
  guarantees on every PC.
- The installed 1.3.8 service ran a three-minute monitoring soak with 37
  samples: zero stale states, counter resets, or crash events. The oldest
  sampled state was 1.09 seconds. Handles remained at 132, working set fell
  from about 22.8 MB to 19.5 MB, and dropped packets stayed at 235. A
  separate 30-sample Windows process counter averaged 0.82% CPU and peaked
  at 6.17%. This live sample was in monitoring mode, not under an active
  speed limit, and predates installation of the 1.3.9 service.
- Release panel and service report 1.3.9.0; PowerShell install/build scripts
  parse cleanly, and setup SHA-256 matches its checksum file:
  `5882144e4fbee39558866d1897cbe8c9b75b7987b56ae0392eb62ba4cade19d5`.
  The bundled WinDivert driver has a valid signature. The panel, service,
  WinDivert DLL, and installer are unsigned. A clean-machine install, upgrade,
  and uninstall and the open UDP/IPv6 upload checks are still required before
  broad distribution.
- The 1.3.9 installer completed on this PC. Installed panel and service
  hashes match the packaged files. The installed service ran from 13:13:07
  to 13:16:07 with 37 five-second samples, zero stale states, detected
  counter resets, or crash events. Maximum sampled state age was 1.09 s;
  dropped packets and flow-table-full events stayed at zero. A 30-sample
  process counter averaged 0.88% CPU, with a 6.17% peak, in monitoring mode.
  These observations do not replace a long-duration run under an active
  limiter or clean-machine acceptance tests.
