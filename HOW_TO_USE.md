# SoundFlow Desktop — Installation and User Guide

This guide is for employees using SoundFlow Desktop on Windows 10 or Windows
11.

## What you receive

Your administrator should provide:

- `SoundFlowDesktop-Setup.exe`
- `SoundFlowDesktop-Setup.exe.sha256` (optional integrity checksum)

Only install a copy received through your organization's approved download
location. If Windows reports that the publisher or signature is invalid, stop
and contact your administrator.

## Install SoundFlow Desktop

1. Download `SoundFlowDesktop-Setup.exe` to the computer.
2. Double-click the installer.
3. Select **Install**.
4. Approve the normal Windows User Account Control prompt.
5. Enter your full name, work email, and department.
6. Follow the organization's instructions for the final action and optional
   Lark or Google Sheets connection.
7. Finish Setup.
8. Confirm that the **SoundFlow Desktop** shortcut appears on the Desktop.

SoundFlow Desktop is installed for all users of the computer. Do not move or
edit its files manually.

## Open the application

Double-click the **SoundFlow Desktop** Desktop shortcut. The main window has
two choices:

- **UPDATE** checks for an approved newer version.
- **RUN** opens the scan and cleanup choices.

## Safe scan: DRY RUN

Use **DRY RUN — Scan Only** unless an authorized incident responder has
specifically instructed you to perform Production cleanup.

1. Open **SoundFlow Desktop**.
2. Select **RUN**.
3. Select **DRY RUN — Scan Only**.
4. Wait for the scan and report to finish.
5. Send the resulting report to your administrator if requested.

DRY RUN discovers matching applications and data and creates a report. It does
not stop applications, delete data, remove credentials, uninstall software,
disconnect cloud synchronization, log out, or shut down the computer.

## Emergency cleanup: PRODUCTION

**PRODUCTION — Emergency Clean can remove local application data and
credentials. Use it only with explicit authorization from your organization.**

Before starting:

1. Save your work and close open applications.
2. Confirm that important files are backed up according to company policy.
3. Follow your incident responder's instructions about OneDrive and other
   synchronization applications.

To proceed:

1. Open **SoundFlow Desktop**.
2. Select **RUN**.
3. Select **PRODUCTION — Emergency Clean**.
4. Approve the Windows User Account Control prompt.
5. Carefully read the confirmation showing the user, device, mode, cleanup
   operation, and final system action.
6. Select **No** to cancel if anything is unexpected.
7. Select **Yes** only when the information is correct and you are authorized.
8. Leave the computer powered on until processing completes.

Depending on the configuration selected by your administrator, Windows may log
out or shut down after the report and event records have been saved.

## Find the local report

Reports are stored in:

```text
C:\ProgramData\SoundFlowDesktop\reports
```

If you cannot open that folder, ask an administrator to retrieve the latest
TXT report. Do not edit the report before sending it to the authorized support
team.

## Update the application

1. Open **SoundFlow Desktop**.
2. Select **UPDATE**.
3. Approve the Windows User Account Control prompt.
4. Allow the update verification and installation to finish.

The updater rejects packages with an invalid version, checksum, signature, or
publisher identity. Contact your administrator if an update is rejected.

## Common problems

### Windows blocks installation

Do not bypass an invalid or unknown publisher warning. Confirm that the
installer came from the approved company location and contact your
administrator.

### Lark or Google Sheets is unavailable

SoundFlow Desktop saves the report locally and queues supported delivery
failures for a later retry. Give the local TXT report to your administrator if
delivery remains unavailable.

### Production reports a protected target

The application intentionally refuses broad, unsafe, redirected, or actively
synchronized locations. Do not try to bypass the protection. Contact your
administrator and provide the report.

### Production was started accidentally

Select **No** on the confirmation window. The cancellation is recorded and no
cleanup is performed.

## Remove SoundFlow Desktop

Run the same approved Setup file, select **Uninstall**, and approve the Windows
prompt. When asked, choose whether authorized administrators should retain or
remove SoundFlow Desktop reports and configuration data.

## Support information

When requesting help, provide:

- your name and work email;
- the Windows computer name;
- whether you used DRY RUN or PRODUCTION;
- the approximate time of the attempt;
- the latest TXT report, if available;
- a screenshot of any error message that does not show credentials or secret
  configuration values.

Never send OAuth credentials, Lark webhook URLs, application secrets, or files
from the credentials folder.
