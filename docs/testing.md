# Testing

## Automated safe tests

On Windows PowerShell 5.1:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

The suite parses every PowerShell file, validates the 56-target manifest,
checks path rejection, queue deduplication/retry, report generation, `WhatIf`
cleanup behavior, secret absence, update verification controls, and prohibited
filenames. It never invokes a real Production cleanup.

## Required Windows VM matrix

Run the following only in disposable Windows 10 and Windows 11 snapshots:

- personal and company-style local profiles;
- standard Desktop and OneDrive Known Folder Move;
- administrator accepted and denied;
- multiple browser profiles, locked files, and running targets;
- supported and unknown applications;
- online/offline Lark and Sheets delivery;
- empty `Detail_Log`, existing reordered headers, and missing columns;
- duplicate Event ID retry;
- cleanup success, partial failure, and verification failure;
- OneDrive disconnected and still-connected cases, with no cloud deletion;
- Lark summary and app-bot TXT upload success/failure;
- valid, invalid-checksum, unsigned, wrong-publisher, and downgrade updates;
- update failure and config/queue preservation;
- Production confirmation cancellation;
- protected/broad/reparse/active-sync path rejection;
- logout and shutdown only after report/event/queue persistence;
- uninstall retain/remove choices and all-users shortcut removal.

Record the VM snapshot, OS build, tester, incident ID, expected result, actual
result, and evidence for each case.
