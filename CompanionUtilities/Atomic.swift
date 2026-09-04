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

  /// Read-only on purpose: a setter would make `counter += 1` look atomic when it is a separate read
  /// and write. Use `sync` for any read-modify-write.
  public var wrappedValue: Value {
    mutex.sync(execute: { value })
  }

  /// Convenience plain setter.
  public func `set`(_ newValue: Value) {
    mutex.sync(execute: { value = newValue })
  }

  public func sync<R>(execute work: (inout Value) throws -> R) rethrows -> R {
    try mutex.sync(execute: { try work(&value) })
  }
}
