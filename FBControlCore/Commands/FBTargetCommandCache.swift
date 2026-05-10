/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// One-slot-per-protocol cache for command class instances bound to a single
/// target. Each `resolve` call for a distinct `T` creates an independent slot
/// keyed by the protocol metatype, so callers can cache as many command kinds
/// as they ask for without registering anything up front.
///
/// The lock is held across `build` so concurrent first-access from two RPCs
/// can't double-construct the same command class -- important for stateful
/// command classes that own queues / connections per target.
@objc public final class FBTargetCommandCache: NSObject {

  private let lock = NSLock()
  private var slots: [ObjectIdentifier: Any] = [:]

  public func resolve<T>(_ type: T.Type = T.self, build: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    let key = ObjectIdentifier(type as Any.Type)
    if let hit = slots[key] as? T { return hit }
    let value = try build()
    slots[key] = value
    return value
  }
}
