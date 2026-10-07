# FBSimulatorBridgeProtocol

The contract between the host and `SimulatorFrameworkBridge`, the helper idb runs inside a booted Simulator to read accessibility and change state no `simctl` verb reaches. Both sides depend on this library and nothing else of each other, so a request the host sends and the guest reads are defined once.

It is Foundation-only Swift with no other dependencies, and builds for macOS, iphonesimulator and appletvsimulator, because the guest is a Simulator binary for both iOS and tvOS.

## What it provides

- **Commands.** `BridgeCommand` names every service the guest offers (accessibility, contacts, photos, notifications, privacy, DNS and the rest), with its arguments. The same command travels as a command-line argument for a one-shot guest or as a frame on a long-lived guest's socket.
- **Envelopes.** `BridgeRequest` carries a versioned command; `BridgeResponse` and `BridgeResult` carry an exit status, ordered JSON values and an optional binary property list, including partial output when a command fails. `BridgeJSONValue` is the JSON both sides exchange.
- **The accessibility vocabulary.** `BridgeAXWire` spells every key of an accessibility request and response: the element attributes the guest reads, the verbs and actions a request can ask for, the response envelope, error kinds, quiescence signals and timing phases. Its raw values are the bytes on the wire, so they are stable.
- **Accessibility requests.** `BridgeAXRequest` is every accessibility request the host sends, typed: a read of an application or of whatever is frontmost (with `BridgeAXReadOptions` for depth, node budget, attributes, traversal and automation mode), a hit test, a write with its optional `BridgeAXWriteAssertion`, device-setting reads and writes, a quiescence stream and the display inventory. Each encodes to the `BridgeAXWire` keys above, and `BridgeAXRequest(payload:)` decodes them back, so the guest answers the same type the host builds. A payload that does not decode throws a `BridgeAXRequestError` naming what is wrong; the guest words the error the caller sees. The companion and the guest it launches are built together, so the decoder reads what this revision encodes rather than older shapes.

## Who depends on it

On the host, `FBSimulatorControl`'s bridge client spawns guests, connects to their sockets and encodes requests with this library; `FBSimulatorAX` reads accessibility through that client. In the guest, `SimulatorFrameworkBridgeSupport` decodes the same requests and answers them. The guest itself lives in [`SimulatorFrameworkBridge`](../SimulatorFrameworkBridge), and how it binds the Simulator's privacy database is described in [its privacy notes](../SimulatorFrameworkBridge/Privacy.md).
