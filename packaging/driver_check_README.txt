App Limiter 1.4.0 legacy driver check

Extract the whole ZIP on the older 64-bit Windows PC. Right-click
run_driver_check.cmd and choose Run as administrator. The check briefly opens
WinDivert's flow and network layers in passive sniff mode, then closes them.
It does not install App Limiter or change your limits.

Send the text shown in the window, or the report path it prints, along with
your Windows version (7 SP1, 8, or 8.1). A passing check confirms that the
driver can start; we still need an install and a longer traffic test before
calling that Windows version supported.

Windows 7 SP1 needs Microsoft's SHA-2 code-signing updates for modern signed
drivers. If the check fails, do not run the preview installer yet.
