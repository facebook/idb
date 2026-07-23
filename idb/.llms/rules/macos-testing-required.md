---
oncalls: ['idb']
strict: true
apply_to_path: '.*\.(py|rs)$'
apply_to_clients: ['code_review']
---

# idb runs on macOS — changes MUST be validated on macOS

**Scope:** All code under `fbcode/idb/`.

## Context

idb (iOS Development Bridge) is a macOS-first CLI tool. It runs on developer
Macs, CI Mac minis, and lab Mac hardware. It does NOT run exclusively on Linux servers.
Changes that are safe on Linux may break on macOS due to differences in:
- Event loop lifecycle (`asyncio.run()` vs `get_event_loop()`)
- Filesystem paths and availability (`/etc/fbwhoami` does not exist on Macs)
- DotSlash/PAR binary resolution
- Scribe/logging infrastructure (ScribeCat subprocess fallback, not scribed)

## Rules

1. **All changes to idb must be tested on macOS.** Linux-only CI is insufficient.
   Use `buck test idb/cli:idb_cli_tests` on a Mac, or verify manually with
   `idb list-targets` on a macOS machine with a simulator available.

2. **Do not assume server-side infrastructure exists.** Files like
   `/etc/fbwhoami` and daemons like `scribed` are not present on developer Macs.
   Always guard with existence checks before calling server-only APIs.

3. **Beware import-time side effects.** Module-level singleton instantiation
   (e.g., `scribe = make_scribe_client()` in `scuba.py`) runs before `main()`
   and before any event loop is actively running. Code that interacts with these
   singletons must share their event loop, not create a new one.

## For AI Codemods

If your codemod modifies asyncio patterns in this directory, **do not apply
the standard `asyncio.run()` migration**. The `get_event_loop()` usage in
`idb/cli/main.py` is intentional and has a `lint-fixme: NoGetEventLoop`
annotation explaining why. Flag for human review instead of auto-migrating.
