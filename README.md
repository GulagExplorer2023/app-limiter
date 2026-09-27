# App Limiter

App Limiter lets you control how much internet a Windows program can use. Set separate upload and download speeds, give an app a data quota, schedule when it can connect, or block its internet access completely. You can also set a quota or schedule for the whole computer.

## Install

1. Download **AppLimiter-Setup-1.3.9.exe** from [Releases](../../releases/latest).
2. Run it and approve the Windows administrator prompt. Setup lets you choose the install folder, desktop shortcut, and whether the app opens when you sign in.
3. Open **App Limiter**. The background service starts automatically, including after a restart.

This build supports **Windows 11, 64-bit, on Intel or AMD PCs**. Setup is for one Windows user account per computer. The installer is not code signed, so Windows may show a download warning.

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
