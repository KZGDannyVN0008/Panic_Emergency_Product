# Architecture and migration

SoundFlow Desktop uses one canonical implementation for each feature. The
assigned rebuild workspace was empty; reusable behavior was audited from the
clean `EmergencySecurityDesktop_v4.9_final` checkout at tag `v4.11.0`. The
older checkout with uncommitted changes was not modified.

## Runtime flow

```text
Launcher
  ├─ Update -> signed release updater
  └─ Run
      ├─ DRY RUN -> discovery -> report -> delivery/queue
      └─ PRODUCTION -> UAC -> confirmation -> lock -> started event
                       -> before scan -> bounded cleanup -> after scan
                       -> report/events/queues -> delivery -> logout/shutdown
```

`app/` owns process entry points. `src/SoundFlowDesktop/` owns reusable
behavior. `config/targets.windows.v1.json` is the only target definition.
Runtime state never lives beside program files.

## Migration summary

| Prior implementation | Canonical destination |
|---|---|
| Monolithic `EmergencyClean.ps1` | `Incident`, `Discovery`, `Safety`, `Cleanup`, `Reporting`, and integration modules |
| `GoogleSheets.ps1` | Private `GoogleSheets.ps1` component under the canonical module |
| `Update-ESD.ps1` | Private `Updater.ps1` component and `SoundFlowDesktop.Updater.ps1` entry point |
| Batch installer/uninstaller | `installer/SoundFlowDesktop.iss` |
| Hardcoded target arrays | `config/targets.windows.v1.json` |
| Separate summary/detail queues | One destination-tagged JSONL queue |
| Version-named ZIP files | Ignored build artifacts |
| macOS scripts | Deferred until Windows acceptance passes |
| Real deployment/OAuth JSON | Excluded; injected during approved packaging/install |

The Fast Wipe sibling was treated as historical reference only. Its deceptive
lock screen, silent destructive task, device rename, Chrome policy change, and
no-confirm behavior were rejected.
