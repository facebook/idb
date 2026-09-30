/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Columns a handler attaches to the event its own call reports.
///
/// `CompanionTelemetry` binds a fresh instance to `current` for each call and reads it once the call
/// finishes, whether it succeeded or failed. Handlers need no extra plumbing: anything running in the
/// call's task tree can reach it, and outside a call `current` is nil.
///
/// Setting a key again replaces its earlier value, so a handler can record progress as it goes and the
/// event carries the last value set.
// SAFETY: every stored property is only read or written inside `lock`.
// patternlint-disable-next-line unchecked-sendable
final class CallTelemetry: @unchecked Sendable {

  @TaskLocal static var current: CallTelemetry?

  private let lock = NSLock()
  private var sizeValue: Int64?
  private var intValues: [String: Int] = [:]
  private var normalValues: [String: String] = [:]

  /// The bytes the call transferred.
  func setSize(_ bytes: Int64) {
    lock.withLock { sizeValue = bytes }
  }

  func setInt(_ value: Int, forKey key: String) {
    lock.withLock { intValues[key] = value }
  }

  func setNormal(_ value: String, forKey key: String) {
    lock.withLock { normalValues[key] = value }
  }

  var size: NSNumber? {
    lock.withLock { sizeValue.map { NSNumber(value: $0) } }
  }

  var ints: [String: Int] {
    lock.withLock { intValues }
  }

  var normals: [String: String] {
    lock.withLock { normalValues }
  }

  /// Every column as `key=value`, `size` first and the rest by key, so a log line reads the same
  /// for the same values.
  var columnDescriptions: [String] {
    lock.withLock {
      let size = sizeValue.map { ["size=\($0)"] } ?? []
      let columns = intValues.map { ($0.key, String($0.value)) } + normalValues.map { ($0.key, $0.value) }
      return size + columns.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map { "\($0.0)=\($0.1)" }
    }
  }
}
