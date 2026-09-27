# App Limiter

App Limiter lets you control how much internet a Windows program can use. Set separate upload and download speeds, give an app a data quota, schedule when it can connect, or block its internet access completely. You can also set a quota or schedule for the whole computer.

## Install

1. Download **AppLimiter-Setup-1.3.9.exe** from [Releases](../../releases/latest).
2. Run it and approve the Windows administrator prompt. Setup lets you choose the install folder, desktop shortcut, and whether the app opens when you sign in.
3. Open **App Limiter**. The background service starts automatically, including after a restart.

The current stable release supports **Windows 11, 64-bit, on Intel or AMD PCs**. Setup is for one Windows user account per computer. The installer is not code signed, so Windows may show a download warning.

### Older Windows test build

The 1.4.0 preview accepts Windows 7 SP1, Windows 8/8.1, Windows 10, and Windows 11 on x64 Intel or AMD PCs. **Windows 7 and 8 are not yet verified.** The bundled WinDivert 2.2.2 driver documents Windows 10/11; the preview installer now checks that its flow and network layers open before changing the installed app or service. A successful check is the first step, not proof that long-running traffic limits work on that OS.

To help test an older PC, download `AppLimiter-Driver-Check-1.4.0.zip` from the [1.4.0 preview release](https://github.com/GulagExplorer2023/app-limiter/releases/tag/v1.4.0-rc1), extract it, then right-click `run_driver_check.cmd` and choose **Run as administrator**. Send the displayed result and the exact Windows version. If it passes, try the preview installer and test browsing, upload/download limits, blocking, restart, and several hours of service uptime. Windows 7 SP1 needs SHA-2 code-signing updates for modern signed drivers. The driver check ZIP is also created locally by `build-installer.ps1`.

## Use it

- **Pick a program** from the list, or use **Pin / Browse** to choose its `.exe` file. Recently active programs stay listed for a minute; pinned programs stay listed.
- **Edit limits** sets upload and download speeds. Drag either slider all the way left for **∞ (unlimited)**, or enter an exact value in **KiB/s**. For reference, 1 MiB/s is 1,024 KiB/s.
- **Block internet** stops that program's uploads and downloads. Click it again to restore access. **Pause all limits** pauses speed limits but does not cancel blocks.
- **Schedule / quota** sets allowed hours and a daily or monthly data amount. When the quota runs out, choose a slower speed or block access. Leave the program list unselected to set a rule for the whole computer.
- **Network activity** shows the destinations a program contacted. It shows domains when available and IP addresses otherwise. You can export the list to an Excel `.xlsx` file.
- **Settings** has start-with-Windows, appearance, and parental mode. Parental mode hides the tray icon when you close the window and asks for a PIN before reopening it. It is a convenience control; Windows administrators can still stop the service.

Right-click a program for the same actions. Closing the window normally leaves App Limiter in the notification area.

## Build from source

Install Lazarus 4.8 with FPC 3.2.2 x64 on Windows 11 x64, then run `./build-installer.ps1` in PowerShell. The pinned WinDivert and NSIS archives are included in `third_party` and `tools`; the build scripts check their SHA-256 hashes. The installer and checksum are written to `dist/`. Run `./build.ps1` if you only need the app and service binaries.

WinDivert handles packet capture and enforcement. Its license is included inside the pinned archive and in the installed package. Technical test notes are in [acceptance/release_review.md](acceptance/release_review.md).
