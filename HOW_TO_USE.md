# SoundFlow Desktop — Installation and User Guide

This guide is for testers and users running SoundFlow Desktop on a personal or
company-provided Windows 10 or Windows 11 computer.

## What you receive

The developer or test coordinator should provide one file:

- `SoundFlowDesktop-Setup.exe`

Only install the copy received through the developer's shared Google Drive or
chat link. Do not download files with a similar name from another source.

## Install SoundFlow Desktop

1. Download `SoundFlowDesktop-Setup.exe` to the computer.
2. Double-click the installer.
3. Select **Install**.
4. Finish Setup. It does not ask for identity, Lark, Google, or administrator
   configuration.
5. Confirm that the **SoundFlow Desktop** shortcut appears on the Desktop.

SoundFlow Desktop is installed only for the current Windows user. Installation
does not request UAC. Production cleanup still requests UAC because Windows
requires elevation for privileged cleanup.

## Open the application

Double-click the **SoundFlow Desktop** Desktop shortcut. The main window has
two choices:

- **UPDATE** checks for an approved newer version.
- **RUN** opens the scan and cleanup choices.

## Safe scan: DRY RUN

Use **DRY RUN — Scan Only** unless the developer or test coordinator has
specifically instructed you to test Production cleanup.

1. Open **SoundFlow Desktop**.
2. Select **RUN**.
3. Select **DRY RUN — Scan Only**.
4. Wait for the scan and report to finish.
5. Send the resulting report to the developer or test coordinator if
   requested.

DRY RUN discovers matching applications and data and creates a report. It does
not stop applications, delete data, remove credentials, uninstall software,
disconnect cloud synchronization, log out, or shut down the computer.

## Emergency cleanup: PRODUCTION

**PRODUCTION — Emergency Clean can remove local application data and
credentials. Use it only with explicit authorization from the developer or
test coordinator.**

Before starting:

1. Save your work and close open applications.
2. Confirm that important personal or work files are safely backed up.
3. Follow the test coordinator's instructions about OneDrive and other
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

Depending on the configuration selected during Setup, Windows may log out or
shut down after the report and event records have been saved.

## Find the local report

Reports are stored in:

```text
%LOCALAPPDATA%\SoundFlowDesktop\reports
```

If you cannot open that folder, ask the Windows device owner or IT support to
retrieve the latest TXT report. Do not edit the report before sending it to the
developer or test coordinator.

## Update the application

1. Open **SoundFlow Desktop**.
2. Select **UPDATE**.
3. Approve the Windows User Account Control prompt.
4. Allow the update verification and installation to finish.

The updater rejects packages with an invalid version, checksum, signature, or
publisher identity. Contact the developer if an update is rejected.

## Common problems

### Windows blocks installation

The test installer may show **Unknown publisher** because it is unsigned.
Confirm that it came from the developer's exact Drive or chat link. A managed
work laptop may block external software; do not bypass device policy or security
controls.

### Lark or Google Sheets is unavailable

SoundFlow Desktop saves the report locally and queues supported delivery
failures for a later retry. Give the local TXT report to the developer or test
coordinator if delivery remains unavailable.

### Production reports a protected target

The application intentionally refuses broad, unsafe, redirected, or actively
synchronized locations. Do not try to bypass the protection. Contact your
test coordinator and provide the report.

### Production was started accidentally

Select **No** on the confirmation window. The cancellation is recorded and no
cleanup is performed.

## Remove SoundFlow Desktop

Run the same Setup file, select **Uninstall**, and approve the Windows prompt.
When asked, choose whether to retain or remove SoundFlow Desktop reports and
configuration data.

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
