/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FBObjCExceptionGuard {

  /// Run a closure under an Objective-C `@try`/`@catch (NSException *)`
  /// wrapper. The closure may itself throw a Swift `Error`; that error is
  /// rethrown unchanged. If the closure raises an `NSException` from
  /// underlying Objective-C code, the exception is converted to an
  /// `NSError` in `FBObjCExceptionGuardErrorDomain` and thrown.
  ///
  /// Use this anywhere Swift code messages a private Objective-C API that
  /// may raise — particularly `NSProxy`-style remote-call proxies whose
  /// `respondsToSelector:` lies, and forwarder targets that may have lost
  /// a method between Xcode releases.
  ///
  /// The closure is `rethrows`-compatible from the caller's perspective:
  /// callers wrap with `try` exactly like any other throwing call.
  ///
  ///     let bytes = try FBObjCExceptionGuard.guarded {
  ///       try someProxy.dataForKey(key)
  ///     }
  public static func guarded<T>(_ closure: () throws -> T) throws -> T {
    // Swift auto-bridges +tryBlock:error: into a throwing form, so any
    // NSException caught by the ObjC implementation arrives here as a
    // thrown NSError in FBObjCExceptionGuardErrorDomain. A Swift Error
    // raised from inside the closure is captured separately and rethrown
    // unchanged, so callers can still distinguish Swift-level failures
    // from underlying Objective-C exceptions.
    // swiftlint:disable:next implicitly_unwrapped_optional
    var capturedResult: T!
    var capturedSwiftError: Error?
    try self.run {
      do {
        capturedResult = try closure()
      } catch {
        capturedSwiftError = error
      }
    }
    if let capturedSwiftError {
      throw capturedSwiftError
    }
    return capturedResult
  }
}
