/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// One cached instance per type, for a single target.
///
/// The lock is held across `build`, so concurrent first access cannot construct the same command twice.
/// Value types are returned by copy, so a command that mutates as it is used must be a reference type.
/// A resolved command must hold its target weakly: the target owns this cache, so a strong reference is a cycle.
public final class FBTargetCommandCache {

  private let lock = NSLock()
  private var slots: [ObjectIdentifier: Any] = [:]

  public init() {}

  public func resolve<T>(_ type: T.Type = T.self, build: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    let key = ObjectIdentifier(type as Any.Type)
    if let hit = slots[key] as? T { return hit }
    let value = try build()
    slots[key] = value
    return value
  }

  /// Pre-populates a slot (for tests substituting a wrapper). Keyed by the static `T`, so pass `as:` explicitly
  /// when `value`'s runtime type is a subclass.
  public func register<T>(_ value: T, as type: T.Type = T.self) {
    lock.lock()
    defer { lock.unlock() }
    slots[ObjectIdentifier(type as Any.Type)] = value
  }
}
