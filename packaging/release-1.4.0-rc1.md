This is a 64-bit compatibility preview for testing App Limiter on older Windows PCs. The stable release is still 1.3.9.

The installer now accepts Windows 7 SP1, Windows 8/8.1, Windows 10, and Windows 11 on x64 Intel/AMD PCs. It checks whether the bundled WinDivert driver can open before changing an existing installation. If the check fails, setup stops and reports the Windows error.

**Windows 7 and 8 are not confirmed supported yet.** The bundled WinDivert 2.2.2 package documents Windows 10/11. Start with `AppLimiter-Driver-Check-1.4.0.zip`: extract it on the older PC, right-click `run_driver_check.cmd`, and choose **Run as administrator**. Share the result and your exact Windows version. If the driver passes, install this preview and test limits, blocking, restart, and a few hours of uptime. Windows 7 SP1 needs SHA-2 code-signing updates.

The app remains x64 only. The normal installer and SHA-256 checksum are attached below.
