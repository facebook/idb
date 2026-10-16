---
name: idb-client
metadata:
  oncalls: idb
  strict: true
  apply_to_path: 'fbcode/idb/.*'
  deps:
    - fbobjc/Tools/idb/.llms/rules/idb.md
---

# idb Python client

This is the client half of idb; the project-wide rules load alongside this one.
The client runs on developer Macs as well as Linux, so validate changes on
macOS.
