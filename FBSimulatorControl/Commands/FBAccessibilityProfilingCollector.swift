/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Mutable collector for profiling data during an accessibility request. A
/// per-request object accumulating timing and count data. The counters and the
/// fetched-keys set are guarded by a lock because `addXPCCallDuration` may be
/// called from the accessibility XPC callback thread while the serialization
/// walk increments element/attribute counts.
///
/// Created and driven entirely from Swift in this module (the serializer and the
/// dispatcher), so it is a plain Swift class.
public final class FBAccessibilityProfilingCollector {

  // Timing fields are set on the serialization thread (non-atomic, as in the
  // original ObjC `assign` properties).
  public var translationDuration: CFAbsoluteTime = 0
  public var elementConversionDuration: CFAbsoluteTime = 0

  /// When the read began. The collector is created with the request, so its own lifetime is the read's
  /// — there is no earlier moment worth stamping and nothing to thread down from the caller.
  private let readStart = CFAbsoluteTimeGetCurrent()

  private let lock = NSLock()
  private var _elementCount: Int64 = 0
  private var _attributeFetchCount: Int64 = 0
  private var _xpcCallCount: Int64 = 0
  private var _totalXPCDuration: CFAbsoluteTime = 0
  private var _xpcDurationBeforeWalk: CFAbsoluteTime = 0
  private var _fetchedKeys = Set<String>()

  public init() {}

  /// Marks the boundary between acquisition and the walk.
  ///
  /// Both phases drive XPC through the same delegate callback, so one running total cannot be
  /// attributed to either without a mark. Acquisition's share is already inside `translationDuration`
  /// and `elementConversionDuration` — wall times over calls that make XPC of their own — so counting
  /// it again as read time would report it twice.
  public func markWalkStart() {
    lock.lock()
    _xpcDurationBeforeWalk = _totalXPCDuration
    lock.unlock()
  }

  public func incrementElementCount() {
    lock.lock()
    _elementCount += 1
    lock.unlock()
  }

  public func incrementAttributeFetchCount(forKey key: String?) {
    lock.lock()
    _attributeFetchCount += 1
    if let key {
      _fetchedKeys.insert(key)
    }
    lock.unlock()
  }

  public func addXPCCallDuration(_ duration: CFAbsoluteTime) {
    lock.lock()
    _xpcCallCount += 1
    _totalXPCDuration += duration
    lock.unlock()
  }

  public var fetchedKeys: Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return _fetchedKeys
  }

  public var elementCount: Int64 {
    lock.lock()
    defer { lock.unlock() }
    return _elementCount
  }

  public var attributeFetchCount: Int64 {
    lock.lock()
    defer { lock.unlock() }
    return _attributeFetchCount
  }

  public var xpcCallCount: Int64 {
    lock.lock()
    defer { lock.unlock() }
    return _xpcCallCount
  }

  public var totalXPCDuration: CFAbsoluteTime {
    lock.lock()
    defer { lock.unlock() }
    return _totalXPCDuration
  }

  /// The walk's own XPC wait, which is what this lane's `read` phase is: the tree is pulled out of the
  /// application one attribute at a time, and the wait for those is the pulling.
  private var walkXPCDuration: CFAbsoluteTime {
    lock.lock()
    defer { lock.unlock() }
    return _totalXPCDuration - _xpcDurationBeforeWalk
  }

  /// `walkDuration` is the wall time of the serialization walk, which on this lane fetches and formats
  /// in one pass. The two are told apart by subtraction: what the walk did not spend waiting on the
  /// application, it spent building the output.
  public func finalize(withWalkDuration walkDuration: CFAbsoluteTime) -> FBAccessibilityProfilingData {
    let readDuration = walkXPCDuration
    return FBAccessibilityProfilingData(
      elementCount: elementCount,
      totalDuration: CFAbsoluteTimeGetCurrent() - readStart,
      acquireDuration: translationDuration + elementConversionDuration,
      readDuration: readDuration,
      // Clamped on the invariant that the walk's XPC waits happen during the walk. A future path that
      // broke it would produce a negative duration, which is worse to publish than a zero.
      serializeDuration: max(0, walkDuration - readDuration),
      attributeFetchCount: attributeFetchCount,
      xpcCallCount: xpcCallCount,
      translationDuration: translationDuration,
      elementConversionDuration: elementConversionDuration,
      totalXPCDuration: totalXPCDuration,
      fetchedKeys: fetchedKeys
    )
  }
}
