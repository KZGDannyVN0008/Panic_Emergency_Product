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
2. Complete Setup without identity, integration, or UAC prompts.
3. Confirm the current user's SoundFlow Desktop shortcut exists.

The Lark webhook is injected only from the protected
`SOUNDFLOW_LARK_WEBHOOK` GitHub Actions secret during packaging. It is never
committed to source or entered by the tester.

Program files are fixed at
`%LOCALAPPDATA%\Programs\SoundFlowDesktop`. Writable state is fixed at
`%LOCALAPPDATA%\SoundFlowDesktop`. Only Production cleanup requests UAC.
