/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation
@_implementationOnly import ReplProtocol

// The API that injected REPL code calls to drive the connected target while its
// own code runs (e.g. `IDB.tap(point)`, where `IDB` is this module).
//
// This module is linked into `libRepl`, which serves the REPL in both contexts
// (DYLD-injected into the xctest process for `test`; dlopen'd by
// SimulatorFrameworkBridge for `simulator`). Injected code imports the matching
// `IDB.swiftinterface`; at run time its `IDB.*` references resolve to this
// module's symbols, exported by the loaded `libRepl`. Each call encodes a
// `ReplCommand` (the shared wire type) and hands it to the host's
// `FBReplInvokeHostCommand` C entry point, resolved here with `dlsym` (it lives
// in the same loaded image, so there is no link dependency on libRepl). The only
// link dependency is `ReplProtocol`, the pure wire types shared with the
// companion -- so the request contract is one type-checked model on both sides.
//
// The calls do not throw. Losing the connection to the companion means the REPL
// session is over, so instead of surfacing a catchable error on every call it
// stops the submission outright (see `haltReplExecution`). A command that merely
// did not apply is ignored (best-effort). If a future command's failure is a
// meaningful result of the call, make that one `throws`.
//
// Injected code must not write to stdout/stderr: in the REPL host those file
// descriptors can alias the control socket, so a stray write corrupts the
// protocol. That is why failures are silent rather than logged.
//
// These are top-level functions rather than statics on a type so the module can
// be named `IDB` without a type shadowing it; `import IDB` then makes them
// callable as `IDB.tap(...)` (module-qualified) or unqualified.

/// Encodes `command`, sends it to the companion, and returns the parsed `result`
/// value on success, or `nil` if the command reported a failure. Does not return
/// if the REPL host can no longer reach the companion -- it stops the submission
/// (see `haltReplExecution`) rather than surfacing a catchable error.
@discardableResult
private func perform(_ command: ReplCommand) -> Any? {
  typealias InvokeFunction = @convention(c) (UnsafeRawPointer?, Int32, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?
  guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "FBReplInvokeHostCommand") else {
    haltReplExecution() // not running inside an idb REPL host
  }
  let invokeHostCommand = unsafeBitCast(symbol, to: InvokeFunction.self)
  // Encode the command as a binary property list so values (e.g. coordinates)
  // round-trip bit-for-bit rather than through a decimal string. It travels as
  // the raw payload of a length-prefixed frame -- there is no text envelope.
  let encoder = PropertyListEncoder()
  encoder.outputFormat = .binary
  guard let commandData = try? encoder.encode(command) else {
    return nil // a command that cannot be encoded cannot be sent; skip it
  }
  var responseLength: Int32 = 0
  let responsePtr = commandData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    invokeHostCommand(raw.baseAddress, Int32(raw.count), &responseLength)
  }
  guard let responsePtr else {
    haltReplExecution() // the REPL host disconnected mid-command
  }
  defer { free(responsePtr) }
  let responseData = Data(bytes: responsePtr, count: Int(responseLength))
  let response = ((try? PropertyListSerialization.propertyList(from: responseData, options: [], format: nil)) as? [String: Any]) ?? [:]
  if response["success"] as? Bool == true {
    return response["result"]
  }
  return nil
}

/// Stops the current REPL submission because the companion is no longer reachable
/// (the session is over). Exits the host process outright rather than throwing a
/// catchable error -- injected code can do nothing useful once the host is gone,
/// and the driver observes the halt as the session disconnecting.
private func haltReplExecution() -> Never {
  exit(EXIT_FAILURE)
}

/// Taps the connected target at the given point.
public func tap(_ point: CGPoint) {
  perform(.tap(point))
}

/// Taps the frontmost-app accessibility element whose label contains `marker`.
public func tap(marker: String) {
  perform(.tapMarker(marker))
}

/// Swipes from one point to another. `duration` is the gesture's length in
/// seconds; `delta` is the spacing in points between intermediate touches (0
/// uses a default). 0 values let the companion pick sensible behavior.
public func swipe(from: CGPoint, to: CGPoint, duration: Double = 0, delta: Double = 0) {
  perform(.swipe(from: from, to: to, duration: duration, delta: delta))
}

/// Pinches centered at the given point. `scale` < 1 pinches in, > 1 pinches out.
public func pinch(at center: CGPoint, scale: Double, duration: Double = 0.5, radius: Double = 100) {
  perform(.pinch(at: center, scale: scale, duration: duration, radius: radius))
}

/// Presses a hardware button: "home", "lock", "side_button", "siri", or "apple_pay".
public func button(_ name: String) {
  perform(.button(name))
}

/// Types `string` on the hardware keyboard.
public func text(_ string: String) {
  perform(.text(string))
}

/// Begins a touch at the given point. Hold it with `touchMove`, end with `touchUp`.
public func touchDown(_ point: CGPoint) {
  perform(.touchDown(point))
}

/// Moves an in-progress touch to the given point.
public func touchMove(_ point: CGPoint) {
  perform(.touchMove(point))
}

/// Ends an in-progress touch at the given point.
public func touchUp(_ point: CGPoint) {
  perform(.touchUp(point))
}

/// Returns the connected target's accessibility hierarchy as a tree of
/// `AXElement`, or nil if it could not be retrieved.
public func describeAll() -> AXElement? {
  guard let data = perform(.describeAll) as? Data else {
    return nil
  }
  if let root = try? PropertyListDecoder().decode(AXElement.self, from: data) {
    return root
  }
  return try? PropertyListDecoder().decode([AXElement].self, from: data).first
}
