---
name: idb-proto
metadata:
  oncalls: idb
  strict: true
  apply_to_path: 'xplat/idb/.*'
  deps:
    - fbobjc/Tools/idb/.llms/rules/idb.md
---

# idb protocol

`idb.proto` is the contract between the idb client and companion, which ship and
update independently; the project-wide rules load alongside this one. Every
change must be additive.
