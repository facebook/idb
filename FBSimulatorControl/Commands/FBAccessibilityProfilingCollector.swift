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
  public var serializationDuration: CFAbsoluteTime = 0

  private let lock = NSLock()
  private var _elementCount: Int64 = 0
  private var _attributeFetchCount: Int64 = 0
  private var _xpcCallCount: Int64 = 0
  private var _totalXPCDuration: CFAbsoluteTime = 0
  private var _fetchedKeys = Set<String>()

  public init() {}

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

  public func finalize(withSerializationDuration serializationDuration: CFAbsoluteTime) -> FBAccessibilityProfilingData {
    FBAccessibilityProfilingData(
      elementCount: elementCount,
      attributeFetchCount: attributeFetchCount,
      xpcCallCount: xpcCallCount,
      translationDuration: translationDuration,
      elementConversionDuration: elementConversionDuration,
      serializationDuration: serializationDuration,
      totalXPCDuration: totalXPCDuration,
      fetchedKeys: fetchedKeys
    )
  }
}
