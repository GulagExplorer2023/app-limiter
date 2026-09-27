# App Limiter release

Run `./build-installer.ps1` from PowerShell on Windows 11 x64. It produces
`dist/AppLimiter-Setup-1.3.9.exe` and a matching SHA-256 file. The setup EXE
contains the panel, service, signed WinDivert driver, DLL, license, and
installation scripts. Recipients need only the setup EXE.

Version 1.3.9 uses optimized release builds with debug symbols stripped.
Both app executables and the installer carry version 1.3.9 metadata. The
installer checks for Windows 11 x64 on an Intel or AMD processor. Windows on
ARM, Windows 10, and 32-bit Windows are outside this build's support. An x64
user program can run under ARM emulation, but the bundled x64 packet driver
cannot load as an ARM64 kernel driver.

Version 0.2.0 adds the selected application's **Network activity** window.
Version 0.2.1 renders the panel at native system DPI for sharper text.
Version 0.3.0 adds live activity search and sorting, copy and CSV export,
daily app/domain usage history, weekly schedules, configurable data quotas,
and DNS answer correlation for more domain labels.
Version 0.3.1 adapts all windows to compact screens and per-monitor DPI changes.
Version 0.3.2 adds main-list sorting and app right-click actions, expands the
quota dialog, keeps inactive apps visible for one minute, and uses the globe
speedometer icon.
Version 0.3.3 adds upload and download speed sliders from unlimited (∞) to
10,000 KiB/s, with precise value entry.
Version 0.3.4 adds 25% headroom to ordinary speed limits and shows approximate
speed-test rates alongside the sliders. Post-quota slow speeds are not boosted.
Version 0.3.5 assigns the supplied globe icon to the main window and installs
the icon file for the Start Menu shortcut and Installed apps entry.
Version 0.3.6 sends idle packets immediately and uses a high resolution timer
for packets that need pacing, reducing limiter induced latency and jitter.
Version 1.0.0 fixes long-running flow tracking and scheduled mode changes,
adds release build metadata, and checks Windows 11 x64 compatibility.
Version 1.1.0 adds a single Settings dialog with a per-user **Start with
Windows** checkbox. Uninstall removes the matching startup entry.
Version 1.2.0 adds an installer folder picker and checked options for a
desktop shortcut and launching the panel at sign-in. Settings adds parental
mode, which hides the tray icon and its Exit menu, and uses a readable native
dialog surface in both themes. The configured keyboard shortcut still opens
the panel. Parental mode is a convenience barrier, not a Windows security
boundary; a user with Task Manager or administrator access can stop it.
Version 1.3.0 opens the panel visibly after a successful interactive setup,
including when normal launches start minimized. It adds a per-app Block internet
button and right-click action. Blocking drops attributed TCP/UDP traffic in
both directions; it does not rely on a zero speed limit and stays active when
speed limits are paused. Unblocking preserves the app's speed limits.
Version 1.3.1 enlarges Settings so every option fits at the tested display
scaling, while smaller screens can still scroll.
Version 1.3.2 loads saved rules before packet workers start, rejects duplicate
executable paths and invalid shortcuts on save, and prevents damaged usage
history from wrapping quota counters. Direct uninstall uses the registered
custom folder and keeps an unrelated Windows startup entry intact. Partial
service startup now shuts down safely if a worker thread cannot start.
Version 1.3.3 exports the visible activity rows as an Excel `.xlsx` workbook.
The workbook opens without Excel being installed on the exporting computer;
byte totals are numeric except counters too large for Excel's exact number range.
Version 1.3.4 asks for a PIN when parental mode is enabled, then requires it
to reopen a hidden panel from the shortcut, EXE, or keyboard shortcut. The
PIN is saved as a salted verifier. Windows sign-in launches parental mode
hidden. When parental mode is off, a second launch reports that the app is
already running. Older parental-mode settings without a PIN load as off so
the owner can set a PIN in Settings.
Version 1.3.5 spaces the parental PIN fields after display scaling and adds
optional internet blocking outside scheduled hours or after an app's data
quota. Those blocks apply to both upload and download even while ordinary
speed limits are paused.
Version 1.3.6 shows each selected program's total internet use during its
current run. Its total resets after all instances of that executable exit and
a new instance connects; saved daily and monthly quotas keep their history.
With no app selected, Schedule / quota edits a computer-wide Internet rule
that also covers traffic without process attribution. Both the data amount
and post-quota speed have sliders and precise fields. Computer-wide
throttling shares one rate per direction across programs.
Version 1.3.7 retries temporary backend state-file sharing conflicts without
stopping traffic enforcement. If Windows must restart the service, a
checkpoint restores totals for programs still running. Flow monitoring
reopens after a receive error, and backend errors are recorded in
`C:\ProgramData\AppLimiter\backend.log`. The panel keeps last-known usage
visible when backend state is stale and labels enforcement status unknown.
Old in-memory usage days are pruned during uninterrupted service runs, and
inactive app and destination cache entries can be reused when full.
Version 1.3.8 sizes the main app list from the space remaining above the
action buttons, keeping the whole panel visible without scrolling at its
normal width and height, including the tested 168 DPI display.
Version 1.3.9 builds destination JSON from a snapshot so a full activity
table cannot hold the packet worker lock throughout serialization. When the
table has 4096 or more destinations, it publishes at most once every five
seconds to bound disk and CPU work.

The installer requests administrator approval, installs into
`C:\Program Files\AppLimiter` by default, starts the service, and creates an
all-users Start Menu shortcut and a Windows Installed apps entry. The folder
and desktop/startup options can be changed during setup. The folder must be
directly under Program Files to protect the system service. It records the account
that launched setup for rules and service permissions, including when a
standard user supplies different administrator credentials. Only that one
account is supported per machine. Running setup again upgrades in place and
keeps its rules. Uninstall keeps rules but removes the service and program.

Before a public release:

1. Sign `AppLimiter.exe`, `app_limiter_service.exe`, and `WinDivert.dll` in
   `dist/AppLimiter` with a trusted code-signing identity and timestamp. The
   bundled `WinDivert64.sys` already has a valid signature; do not replace it
   with an unsigned driver.
2. Run `./build-installer.ps1 -SkipBuild` to package the signed files. Sign the
   setup EXE and regenerate its `.sha256` file after signing. Verify every
   signature and the checksum on a clean Windows 11 machine.
3. Test fresh install, upgrade while the panel is running, and uninstall on a
   clean Windows 11 x64 PC. Test a standard user who enters a separate admin
   account at UAC. Confirm that rules survive upgrade and uninstall, and that
   normal networking works after uninstall.
4. Complete the open controlled UDP and IPv6 upload acceptance checks noted
   in `README.md` before calling the app fully verified.

The setup build is currently unsigned. Microsoft documents that unsigned
downloads may show SmartScreen warnings and that Smart App Control can block
unsigned executables. Code signing needs an identity controlled by the
publisher: <https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation>.

The release review and local tests are recorded in
`acceptance/release_review.md`. A clean-machine install of this exact 1.3.9
package remains to be performed before broad distribution.
