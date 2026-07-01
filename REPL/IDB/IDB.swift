/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// The API that injected REPL code calls to drive the connected target while its
// own code runs (e.g. `try IDB.tap(x:y:)`, where `IDB` is this module).
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
// These are top-level functions rather than statics on a type so the module can
// be named `IDB` without a type shadowing it; `import IDB` then makes them
// callable as `IDB.tap(...)` (module-qualified) or unqualified.

public struct HostCommandError: Error, CustomStringConvertible {
  public let description: String
}

/// Sends a host command (`name` plus JSON `args`) to the companion and returns the
/// parsed `result` on success, or throws `HostCommandError` on failure.
@discardableResult
public func invoke(_ name: String, _ args: [String: Any] = [:]) throws -> Any? {
  typealias InvokeFunction = @convention(c) (UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
  guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "FBReplInvokeHostCommand") else {
    throw HostCommandError(description: "idb: host command channel unavailable")
  }
  let invokeHostCommand = unsafeBitCast(symbol, to: InvokeFunction.self)
  let argsJSON = String(decoding: (try? JSONSerialization.data(withJSONObject: args)) ?? Data("{}".utf8), as: UTF8.self)
  guard let responsePtr = name.withCString({ namePtr in argsJSON.withCString { argsPtr in invokeHostCommand(namePtr, argsPtr) } }) else {
    throw HostCommandError(description: "idb: no response for host command '\(name)' (not running inside an idb REPL execution?)")
  }
  defer { free(responsePtr) }
  let response = ((try? JSONSerialization.jsonObject(with: Data(String(cString: responsePtr).utf8))) as? [String: Any]) ?? [:]
  if response["success"] as? Bool == true { return response["result"] }
  throw HostCommandError(description: response["error"] as? String ?? "idb: host command '\(name)' failed")
}

/// Taps the connected target at the given point.
public func tap(x: Double, y: Double) throws {
  try invoke("tap", ["x": x, "y": y])
}

/// Returns the connected target's full accessibility hierarchy as JSON.
public func describeAll() throws -> String {
  (try invoke("describe_all") as? String) ?? ""
}
