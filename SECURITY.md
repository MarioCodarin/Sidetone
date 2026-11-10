# Security

## Model

Sidetone is a local-first macOS app. It has:

- **no network code** — no HTTP client, no analytics, no crash reporting, no update check;
- **no accounts, API keys or tokens** — there is nothing to configure beyond macOS privacy grants;
- **no sandbox escape or private API** — it uses the public Core Audio process-tap API and standard
  TCC prompts.

Audio is written only to the recordings folder the user chooses (`~/Documents/Recordings` by
default). The final take is one AAC `.m4a`; while recording, two raw `.caf` files and a
`session.json` alignment file sit in a working folder inside it.

## What is in the repository

Source, docs, screenshots with fixture data, the icon, and build scripts. It contains no recordings,
keys, tokens, email addresses or personal paths. If you think you have found a secret, please open a
private advisory rather than a public issue.

## Reporting a vulnerability

Use GitHub's **Report a vulnerability** (Security → Advisories) on
[github.com/MarioCodarin/Sidetone](https://github.com/MarioCodarin/Sidetone). Please include the macOS
version, what you observed, and the smallest reproduction you can.

## Signing

Release builds are ad-hoc signed (`codesign -s -`). There is no notarized binary, so macOS treats each
build as a new identity: rebuilding can re-prompt for Microphone / System Audio / Calendar access, and
those grants can be reviewed or revoked at any time in System Settings → Privacy & Security.
