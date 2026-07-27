# Installation

## Build prerequisites

Use an isolated Windows build machine with:

- Windows PowerShell 5.1;
- Inno Setup 6;
- Windows SDK `signtool.exe`;
- an approved code-signing certificate;
- an installed-desktop Google OAuth client JSON, if Sheets connection is
  required during installation.

Build and sign:

```powershell
.\installer\build.ps1 `
  -InnoSetupCompiler 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe' `
  -OAuthClientPath 'C:\SecureBuildInput\google-oauth-client.json' `
  -SignTool 'C:\Program Files (x86)\Windows Kits\10\bin\x64\signtool.exe' `
  -CertificateThumbprint 'APPROVED_CERTIFICATE_THUMBPRINT'
```

The output is `installer\output\SoundFlowDesktop-Setup.exe` plus its SHA-256
file. Do not place a real OAuth client or webhook in the repository.

## Endpoint installation

1. Double-click `SoundFlowDesktop-Setup.exe`.
2. Accept standard UAC.
3. Enter full name, work email, and department.
4. Choose the Production final action.
5. Supply the Lark webhook only through the protected installer field, or leave
   it blank for a disconnected installation.
6. Choose whether to connect Google Sheets. Cancellation or connection failure
   does not roll back the install.
7. Confirm the all-users SoundFlow Desktop shortcut exists.

Program files are fixed at `C:\Program Files\SoundFlowDesktop`. Writable state
is fixed at `C:\ProgramData\SoundFlowDesktop`.
