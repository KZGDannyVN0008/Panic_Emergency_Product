# User guide

Open the single SoundFlow Desktop shortcut.

- `Update` checks the approved GitHub Release metadata, then verifies version,
  SHA-256, and Authenticode publisher identity before starting Setup.
- `Run` offers `DRY RUN — Scan Only` and `PRODUCTION — Emergency Clean`.

DRY RUN is the default safe choice. It discovers targets, writes a local TXT
report, attempts Lark and Google Sheets delivery, and queues failures. It does
not stop applications, delete data, remove credentials, uninstall software,
disconnect synchronization, log out, or shut down.

Production requests standard UAC and displays the device, employee, mode,
destructive actions, and final system action. Select No to cancel.

Reports are stored under `%LOCALAPPDATA%\SoundFlowDesktop\reports`.
