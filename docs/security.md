# Security

- Authorized device-owner or tester use only.
- DRY RUN is non-destructive and the default.
- Production requires UAC, explicit confirmation, and a single-run lock.
- Cleanup is manifest-bounded and verification-driven.
- Empty, unresolved, broad, protected, wildcard, reparse-point, and active-sync
  paths are rejected.
- Cloud APIs are never used to delete files.
- OneDrive local deletion is skipped unless disconnection is independently
  verified. Other sync products currently report protected rather than guess.
- Unknown applications are detected but unsupported.
- Secrets and file contents are excluded from reports and events.
- Webhook and OAuth tokens use Windows DPAPI Current User.
- Update packages require SHA-256 and a trusted Authenticode publisher.
- No remote command execution, covert surveillance, security bypass, deceptive
  UI, hidden publisher, or stealth persistence is present.

Production verification must be performed only in disposable Windows VMs.
