# Administrator guide

## Configuration

`C:\ProgramData\SoundFlowDesktop\config\deployment.json` stores non-secret
settings. Lark and Google token material is separately DPAPI-protected for the
authorizing Windows user under `credentials`.

To rotate the Lark webhook, rerun Setup and enter the replacement value. Do not
paste secrets into logs, tickets, screenshots, or command history.

## Target governance

Targets are defined only in `config\targets.windows.v1.json`. A path must be
explicit, resolve without missing variables, remain inside its approved target
base, avoid protected roots and reparse points, and not be inside an active
sync root.

All uninstall flags ship disabled. Enabling fallback uninstall requires a
reviewed entry in `uninstall-allowlist.json`, a registered/official uninstall
method, verification-failure gating, and product-owner approval.

## Queue operations

Failed deliveries are stored in `queue\delivery.jsonl` using Event ID plus
destination as the deduplication key. The next launch retries a bounded batch.
Do not edit a live queue without preserving valid JSONL and Event IDs.
