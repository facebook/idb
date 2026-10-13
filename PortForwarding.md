# Device port forwarding

`idb forward 8099 --local-port 0 --json` starts a TCP listener on the client's
loopback interface. Each accepted connection opens an independent `forward_port`
RPC to the companion's selected physical iOS device. The companion connects to
the device port through USBMux. The client may run on Linux or macOS; the
companion must run on the Mac attached to the device.

Use the normal `--companion` option or `IDB_COMPANION` to select the companion.
There is no separate device-port endpoint or local USBMux requirement on the
client. Simulators and Mac targets currently return `UNIMPLEMENTED`.

The JSON readiness line contains `event`, `host_port`, and `device_port`.
Readiness means the local listener is bound, not that a device service is
listening. Each RPC acknowledges its device connection separately. Interrupting
the command closes the listener and cancels its accepted connections. It accepts
at most 64 simultaneous connections.

## Streaming contract

The first request is `Open` with a port in `1...65535`. The first response is
`Opened`, sent only after the device connection succeeds. Subsequent data chunks
are opaque bytes of at most 64 KiB; empty data is not EOF. TCP and protobuf chunk
boundaries need not match.

Request-stream completion finishes accepted writes and drains responses for up
to four seconds before closing the device connection. If the response drain
times out, the RPC returns `DEADLINE_EXCEEDED`; bytes received before the timeout
may be an incomplete response. The Python client reports the timeout as an
`IdbException` containing the companion's error message. Device EOF ends the RPC
and closes the local connection. Response-stream completion terminates pending
client input. USBMux write shutdown is not used; TCP half-close is not exposed
by this API.
Non-OK status, disconnect, and cancellation terminate the connection; interrupted
connections are never automatically reopened or replayed.

The native `SocketStream` owns its descriptor and uses nonblocking I/O. Readiness
sources monitor separate duplicated descriptors and close them only from their
cancellation handlers. The scoped device API retains the connected device
through socket cleanup.

## Restricting ports

Forwarding is disabled by default. Start the companion with
`--allowed-forward-ports 8099,8100` to permit those device ports. Omitting the
option or supplying an empty string disables forwarding. Malformed policy values
fail server construction. Requests for disallowed ports fail before connecting
to the device.
