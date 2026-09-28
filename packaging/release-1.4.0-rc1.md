This is a 64-bit compatibility preview for testing App Limiter on older Windows PCs. The stable release is still 1.3.9.

The installer probes x64 Intel/AMD Windows versions from Windows 7 onward. It checks whether the bundled WinDivert driver can open before changing an existing installation. If the check fails, setup stops and reports the Windows error.

**Windows 7 SP1 failed the driver check with error 577 even after KB4490628, KB4474419, and a restart. This build does not support that Windows 7 PC. Windows 8/8.1 has not been tested.** The bundled WinDivert 2.2.2 package documents Windows 10/11. For another older PC, start with `AppLimiter-Driver-Check-1.4.0.zip`: extract it, right-click `run_driver_check.cmd`, and choose **Run as administrator**. Share the result and your exact Windows version. If the driver passes, install this preview and test limits, blocking, restart, and a few hours of uptime.

The app remains x64 only. The normal installer and SHA-256 checksum are attached below.
