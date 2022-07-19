/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@propertyWrapper
public final class Atomic<Value>: @unchecked Sendable {

  private var value: Value
  private let mutex: FBMutex

  public init(wrappedValue: Value) {
    self.mutex = FBMutex()
    self.value = wrappedValue
  }

  public var wrappedValue: Value {
    get { mutex.sync(execute: { value }) }
    set { mutex.sync(execute: { value = newValue }) }
  }

  /// Convenience plain setter.
  /// This produces exact same results:
  /// ```
  /// @Atomic var counter = 0
  ///
  /// $counter.set(1)
  /// $counter.sync { $0 = 1 }
  /// ```
  public func `set`(_ newValue: Value) {
    mutex.sync(execute: { value = newValue })
  }

  public func sync<R>(execute work: (inout Value) throws -> R) rethrows -> R {
    try mutex.sync(execute: { try work(&value) })
  }
}
