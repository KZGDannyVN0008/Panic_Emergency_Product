# Troubleshooting

## Google Sheets: Not Connected

Confirm the Google Sheets API is enabled, the OAuth client is an installed
desktop client, the selected user can edit the spreadsheet, and loopback
traffic to `127.0.0.1` is allowed. Rerun Setup to reconnect.

## Lark summary is queued

Confirm HTTPS access to Lark and rotate/re-enter the webhook through Setup if
needed. Do not print the protected webhook file. The next application launch
retries queued records.

## TXT report says pending credentials

A custom webhook cannot upload files. Configure an official Lark app ID,
DPAPI-protected app secret, and destination chat/user ID. Until then, summary
delivery can succeed while TXT delivery correctly remains pending/queued.

## Production reports protected

This is expected when a path is broad, unresolved, a reparse point, inside an
active synchronized root, or when sync disconnection cannot be verified. Do
not bypass the protection; correct the manifest or disconnect state and retest
in a disposable VM.

## Update rejected

Check the semantic version, SHA-256, Authenticode status, and signer subject.
Unsigned, mismatched, wrong-publisher, and unauthorized downgrade packages are
intentionally rejected.
