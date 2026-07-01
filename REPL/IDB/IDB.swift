/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

// The API that injected REPL code calls to drive the connected target while its
// own code runs (e.g. `IDB.tap(point)`, where `IDB` is this module).
//
// This module is linked into `libRepl`, which serves the REPL in both contexts
// (DYLD-injected into the xctest process for `test`; dlopen'd by
// SimulatorFrameworkBridge for `simulator`). Injected code imports the matching
// `IDB.swiftinterface`; at run time its `IDB.*` references resolve to this
// module's symbols, exported by the loaded `libRepl`. The transport is the
// host's `FBReplInvokeHostCommand` C entry point, resolved here with `dlsym`
// (it lives in the same loaded image) so this module needs no link dependency --
// keeping it self-contained and unable to expose any of libRepl's own symbols.
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

/// Sends a host command (`name` plus JSON `args`) to the companion and returns its
/// parsed `result`, or `nil` if the command reported a failure. Does not return if
/// the REPL host can no longer reach the companion -- it stops the submission (see
/// `haltReplExecution`) rather than surfacing a catchable error.
@discardableResult
public func invoke(_ name: String, _ args: [String: Any] = [:]) -> Any? {
  typealias InvokeFunction = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
  guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "FBReplInvokeHostCommand") else {
    haltReplExecution() // not running inside an idb REPL host
  }
  let invokeHostCommand = unsafeBitCast(symbol, to: InvokeFunction.self)
  let argsJSON = String(decoding: (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8), as: UTF8.self)
  guard let responsePtr = name.withCString({ namePtr in argsJSON.withCString { argsPtr in invokeHostCommand(namePtr, argsPtr) } }) else {
    haltReplExecution() // the REPL host disconnected mid-command
  }
  defer { free(responsePtr) }
  let response = ((try? JSONSerialization.jsonObject(with: Data(String(cString: responsePtr).utf8))) as? [String: Any]) ?? [:]
  if response["success"] as? Bool == true {
    return response["result"]
  }
  // A command-level failure (e.g. bad input, or the action did not apply). The
  // current commands carry no meaningful error result, so ignore it and continue
  // rather than throwing; a command that must surface an error should be `throws`.
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
  invoke("tap", ["x": Double(point.x), "y": Double(point.y)])
}

/// Taps the frontmost-app accessibility element whose label contains `marker`.
public func tap(marker: String) {
  invoke("tap", ["marker": marker])
}

/// Swipes from one point to another. `duration` is the gesture's length in
/// seconds; `delta` is the spacing in points between intermediate touches (0
/// uses a default). 0 values let the companion pick sensible behavior.
public func swipe(from: CGPoint, to: CGPoint, duration: Double = 0, delta: Double = 0) {
  invoke("swipe", ["start_x": Double(from.x), "start_y": Double(from.y), "end_x": Double(to.x), "end_y": Double(to.y), "duration": duration, "delta": delta])
}

/// Pinches centered at the given point. `scale` < 1 pinches in, > 1 pinches out.
public func pinch(at center: CGPoint, scale: Double, duration: Double = 0.5, radius: Double = 100) {
  invoke("pinch", ["x": Double(center.x), "y": Double(center.y), "scale": scale, "duration": duration, "radius": radius])
}

/// Presses a hardware button: "home", "lock", "side_button", "siri", or "apple_pay".
public func button(_ name: String) {
  invoke("button", ["button": name])
}

/// Types `string` on the hardware keyboard.
public func text(_ string: String) {
  invoke("text", ["text": string])
}

/// Begins a touch at the given point. Hold it with `touchMove`, end with `touchUp`.
public func touchDown(_ point: CGPoint) {
  invoke("touch_down", ["x": Double(point.x), "y": Double(point.y)])
}

/// Moves an in-progress touch to the given point.
public func touchMove(_ point: CGPoint) {
  invoke("touch_move", ["x": Double(point.x), "y": Double(point.y)])
}

/// Ends an in-progress touch at the given point.
public func touchUp(_ point: CGPoint) {
  invoke("touch_up", ["x": Double(point.x), "y": Double(point.y)])
}

/// Returns the connected target's full accessibility hierarchy as JSON.
public func describeAll() -> String {
  (invoke("describe_all") as? String) ?? ""
}
