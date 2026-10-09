# SimScope agent protocol (experimental)

SimScope lets an agent join a person's simulator session. Both see the same
screen and action timeline. Use `simscope-remote`, bundled in
`SimScope.app/Contents/MacOS`, to communicate with the app.

```sh
simscope-remote status
simscope-remote describe
simscope-remote tap --label "General" -i "open General to check the settings"
simscope-remote say "I will check Display & Brightness"
simscope-remote wait-for-next-message --wait 30
```

Confirm the device with `status` before acting. The person may interact while
you work; read their events before assuming the screen is unchanged. Mutating
commands require `-i/--intent`, which appears in the shared action log before
the action is sent. Prefer labels over coordinates when available.

`watch` follows the complete timeline. `wait-for-next-message` returns human
actions followed by a message, retaining its cursor between calls. Exit code 8
means the wait expired without a message; retry without treating it as failure.

The default socket is `/tmp/simscope/control.sock`, with mode `0600` inside a
`0700` directory. Override it with `SIMSCOPE_CONTROL_SOCKET` or `--socket` on
the CLI. Each additional simulator window listens on
`/tmp/simscope/control-<UDID>.sock`. The base socket addresses the launch window.

The wire format is newline-delimited JSON over a local Unix socket. The app and
CLI share the Codable types in [SimScopeProtocol](SimScopeProtocol). This is
SimScope's own experimental protocol, not idb's gRPC protocol.

Use `simscope-remote --help` and each subcommand's `--help` for current options.
Swift injection uses the bundled `idb-repl`; supply `--bundle-id` or the default
configured when SimScope launched. Injected UIKit code runs on the main thread
by default. Recording and injection are visible in the shared timeline.
