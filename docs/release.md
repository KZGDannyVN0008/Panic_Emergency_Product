# Release process

No release is published automatically from this rebuild.

1. Run `tests\run.ps1` on Windows 10 and Windows 11.
2. Complete the disposable-VM matrix in `docs\testing.md`.
3. Set the same semantic version in the module manifest, Core application
   information, installer definition, and update manifest.
4. Build `SoundFlowDesktop-Setup.exe` with `installer\build.ps1`.
5. Sign and timestamp the Setup EXE with the approved publisher certificate.
6. Verify Authenticode on a separate Windows machine.
7. Recalculate SHA-256 and prepare `update-manifest.json`.
8. Obtain release approval.
9. Create an official GitHub Release and upload only the signed Setup EXE,
   checksum, and update manifest.
10. Test update and rollback from the previous supported version.

Never publish OAuth client files, webhook values, user tokens, queues, reports,
or logs. Never update endpoints from a Git branch.
