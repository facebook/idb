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
public final class FBAccessibilityProfilingCollector {

  // Timing fields are set only on the serialization thread, so they are not lock-guarded.
  public var translationDuration: CFAbsoluteTime = 0
  public var elementConversionDuration: CFAbsoluteTime = 0

  /// When the read began; the collector is created at request start.
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
  func markWalkStart() {
    lock.lock()
    _xpcDurationBeforeWalk = _totalXPCDuration
    lock.unlock()
  }

  func incrementElementCount() {
    lock.lock()
    _elementCount += 1
    lock.unlock()
  }

  func incrementAttributeFetchCount(forKey key: String?) {
    lock.lock()
    _attributeFetchCount += 1
    if let key {
      _fetchedKeys.insert(key)
    }
    lock.unlock()
  }

  func addXPCCallDuration(_ duration: CFAbsoluteTime) {
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

  /// XPC wait accrued during the walk — this backend's `read` phase.
  private var walkXPCDuration: CFAbsoluteTime {
    lock.lock()
    defer { lock.unlock() }
    return _totalXPCDuration - _xpcDurationBeforeWalk
  }

  /// `walkDuration` is the wall time of the serialization walk, which on this backend fetches and formats
  /// in one pass; `serializeDuration` is that wall time minus the walk's XPC wait.
  public func finalize(withWalkDuration walkDuration: CFAbsoluteTime) -> FBAccessibilityProfilingData {
    let readDuration = walkXPCDuration
    return FBAccessibilityProfilingData(
      elementCount: elementCount,
      totalDuration: CFAbsoluteTimeGetCurrent() - readStart,
      acquireDuration: translationDuration + elementConversionDuration,
      readDuration: readDuration,
      // Clamped on the invariant that the walk's XPC waits happen during the walk.
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
