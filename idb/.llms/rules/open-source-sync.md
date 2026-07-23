---
name: open-source-sync
metadata:
  oncalls: idb
  strict: true
---

# Open-Source Sync — Keep Internal Details Out of Code and Commit Messages

**`fbcode/idb/` is mirrored to public GitHub** at [`facebook/idb`](https://github.com/facebook/idb) by ShipIt (config: `configerator/source/opensource/shipit_config/facebook/idb.cconf`). The synced paths are `fbcode/idb/`, `fbobjc/Tools/idb/Source/`, and `xplat/idb/` — both their **source code** and their **commit messages** become public.

## Code

- Anything under the synced paths is published. Open-source files here carry the MIT license header.
- Keep Meta-internal code out of the synced files. idb's internal-only client code lives under `fbcode/idb/fb/` (marked "Confidential and proprietary", stripped on export) and is reached from the open-source client through the plugin seam in `idb/common/plugin.py` — never `import` an internal module directly from a synced file; add a plugin hook and implement it in `idb/fb/plugin.py` instead.

## Commit messages

On export, ShipIt keeps only the **title** (minus its `[area][type]` tag prefix) plus the `Summary:`, `Reviewed By:`, `Differential Revision:`, and `Pulled By:` sections. It strips any `Internal:` section and drops every other section (`Test Plan:`, `Reviewers:`, `Tasks:`, etc.). So for idb commit messages:

- Write the **title** and **`Summary:`** for an external reader — no internal URLs (Phabricator, notes, Workplace, wikis), task/diff numbers, codenames, internal system/dataset names, or team/oncall/host/infra references.
- Put all internal context — `# This Stack`, plan links, task links, Meta-specific motivation, and internal system names — under an **`Internal:`** section, which is stripped on export.
- This **overrides** the default convention of leading `Summary:` with a `Plan:` link or `# This Stack` heading: for idb, move those under `Internal:` so they aren't published.

Assume anything in the **title** or **`Summary:`** — and any code under the synced paths — will be read publicly on GitHub.
