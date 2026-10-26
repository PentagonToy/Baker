# Changelog

## 0.0.8 — 2026-10-26

- Add one optional OCR plugin from a ZIP, with explicit code approval, a provider switch and optional API key stored in Keychain.
- Track plugin completions separately from Baker · Local usage, with confirmed reset and an updated tracking date.
- Fall back to an installed local formula or PDF model when a plugin fails; preserve cancellation and show the completing provider.
- Document the provider-neutral JSON protocol, adapter example and agent controls without bundling an external OCR connector.

## 0.0.7 — 2026-10-26

- Process image, formula and PDF recognition locally, with no OCR account login or cloud conversion.
- Offer Pix2Text, Texo and PP-FormulaNet plus-S as separate verified model downloads; retain the optional offline PDF engine.
- Keep capture editing, recording, formula history, direct copy, confirmed metadata deletion and the agent CLI.
- Preserve local usage counts and saved results when upgrading from an earlier installation.

This repository starts from the local-processing edition. Earlier release history is not mirrored here.
