/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A class declared in Objective-C as a lightweight generic (`@interface FBFuture <T : id>`).
///
/// The parameter of such a class exists only in the type checker — it is erased before it reaches
/// the runtime, so every instance is the same class whatever it is declared to carry.
public protocol FBLightweightGeneric: AnyObject {}

extension FBFuture: FBLightweightGeneric {}
extension FBFutureContext: FBLightweightGeneric {}
extension FBProcessInput: FBLightweightGeneric {}
extension FBProcessOutput: FBLightweightGeneric {}

public extension FBLightweightGeneric {

  /// Re-expresses the erased parameter of a value returned by an Objective-C API.
  ///
  /// The chaining methods that cannot name their result type — `onQueue:pend:`, `failFuture`,
  /// `mapReplace:` and their neighbours — are declared as a bare `FBFuture *` / `FBFutureContext *`
  /// and so import into Swift as the `AnyObject` specialisation. This restores the parameter the
  /// caller already knows, and cannot fail: it changes how the type checker reads a reference that
  /// already points at the right object, and leaves the object itself alone.
  func retyped<U: FBLightweightGeneric>(_ type: U.Type = U.self) -> U {
    unsafeDowncast(self, to: U.self)
  }
}
