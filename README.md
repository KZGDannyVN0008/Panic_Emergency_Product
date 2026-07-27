# SoundFlow Desktop

SoundFlow Desktop is a Windows 10/11 emergency scan and authorized cleanup
application. It defaults to a non-destructive DRY RUN. Production requires
normal UAC elevation and an explicit confirmation that identifies the user,
device, mode, and requested final system action.

The application installs machine-wide to:

```text
C:\Program Files\SoundFlowDesktop
```

Writable configuration, encrypted credentials, logs, reports, queues, and
state are stored under:

```text
C:\ProgramData\SoundFlowDesktop
```

## Repository layout

- `app/` contains the three runtime entry points.
- `src/SoundFlowDesktop/` contains the canonical PowerShell modules.
- `config/` contains versioned manifests and secret-free examples.
- `installer/` contains the Windows Setup EXE definition and build script.
- `tests/` contains non-destructive unit, integration, and fixture tests.
- `docs/` contains operating, security, privacy, testing, and release guidance.

## Safety

Do not run Production on a development computer. Destructive tests belong in a
disposable Windows VM snapshot. The repository never contains the Lark webhook,
Google user tokens, or a real OAuth client configuration.

See `docs/installation.md` and `docs/testing.md`.

## Windows tester distribution

Testers receive one file:

```text
SoundFlowDesktop-Setup.exe
```

The developer can send that installer through Google Drive or chat. Testers do
not need the source repository, checksum file, configuration templates, or
build scripts. The current hosted test build is unsigned, so Windows may show
**Unknown publisher**, and managed devices may block installation according to
their security policy.

Give testers the standalone instructions in `HOW_TO_USE.md`.
