# Release process

No release is published automatically from this rebuild.

1. Run `tests\run.ps1` on Windows 10 and Windows 11.
2. Complete the disposable-VM matrix in `docs\testing.md`.
3. Set the same semantic version in the module manifest, Core application
   information, installer definition, and update manifest.
4. Build `SoundFlowDesktop-Setup.exe` with `installer\build.ps1`.
5. Inject the dedicated, revocable Lark webhook through the protected
   `SOUNDFLOW_LARK_WEBHOOK` build secret. Never commit it or request it from a
   tester.
6. Sign and timestamp the Setup EXE with the approved publisher certificate.
7. Verify Authenticode on a separate Windows machine.
8. Recalculate SHA-256 and prepare `update-manifest.json`.
9. Obtain release approval.
10. Create an official GitHub Release and upload only the signed Setup EXE,
   checksum, and update manifest.
11. Test update and rollback from the previous supported version.

Never publish OAuth client files, webhook values, user tokens, queues, reports,
or logs. Never update endpoints from a Git branch.
