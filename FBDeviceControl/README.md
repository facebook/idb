# `FBDeviceControl`

A sister-framework to [`FBSimulatorControl`](https://github.com/facebook/idb/tree/main/FBSimulatorControl) for iOS Devices.

Like `FBSimulatorControl`, `FBDeviceControl` is primarily an implementation detail of `idb`, and `idb` is the easiest way to use what it implements. It is also built to be linked directly, mainly by native macOS applications that embed Device automation in-process, or by consumers that need finer-grained control than the `idb` cli exposes. The same trade-off applies. The `idb` cli and its gRPC interface are the project's compatibility boundary; the framework's own APIs change more freely with the implementation.
