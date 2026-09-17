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
public protocol LightweightGeneric: AnyObject {}

extension FBFuture: LightweightGeneric {}
extension FBProcessInput: LightweightGeneric {}
extension FBProcessOutput: LightweightGeneric {}
extension FBSubprocess: LightweightGeneric {}

public extension LightweightGeneric {

  /// Re-expresses the erased parameter of a value returned by an Objective-C API. Chaining methods that
  /// cannot name their result type (`failFuture`, `mapReplace:` and neighbours) are declared as bare
  /// `FBFuture *` and import as the `AnyObject` specialisation.
  /// The parameter is erased at runtime, so restoring it cannot fail.
  func retyped<U: LightweightGeneric>(_ type: U.Type = U.self) -> U {
    unsafeDowncast(self, to: U.self)
  }
}
