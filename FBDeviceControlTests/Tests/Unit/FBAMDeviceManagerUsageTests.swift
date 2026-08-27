/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import XCTest

/// Records the `AMDCalls` a device usage cycle makes, in order.
private final class UsageCallRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [String] = []

  func record(_ event: String) {
    lock.lock()
    defer { lock.unlock() }
    events.append(event)
  }

  var recorded: [String] {
    lock.lock()
    defer { lock.unlock() }
    return events
  }
}

private nonisolated(unsafe) var sUsageRecorder = UsageCallRecorder()

/// Pins the order in which `+startUsing:` and `+stopUsing:` drive the device.
///
/// These are the entry points `FBAMDevice` uses around every operation, and the sequence is the
/// contract: connect before pairing, pair before a session, and unwind in reverse. Nothing here
/// needs a device — every step is an `AMDCalls` function pointer.
final class FBAMDeviceManagerUsageTests: XCTestCase {

  override func setUp() {
    super.setUp()
    sUsageRecorder = UsageCallRecorder()
  }

  private func stubbedCalls() -> AMDCalls {
    var calls = FBCreateZeroedAMDCalls()
    calls.Connect = { _ in
      sUsageRecorder.record("connect")
      return 0
    }
    calls.Disconnect = { _ in
      sUsageRecorder.record("disconnect")
      return 0
    }
    calls.IsPaired = { _ in
      sUsageRecorder.record("is_paired")
      return 1
    }
    calls.ValidatePairing = { _ in
      sUsageRecorder.record("validate_pairing")
      return 0
    }
    calls.StartSession = { _ in
      sUsageRecorder.record("start_session")
      return 0
    }
    calls.StopSession = { _ in
      sUsageRecorder.record("stop_session")
      return 0
    }
    calls.Retain = { $0 }
    calls.Release = { $0 }
    return calls
  }

  private var logger: any FBControlCoreLogger {
    FBControlCoreGlobalConfiguration.defaultLogger
  }

  /// The stubs ignore the device entirely, so any object stands in for the opaque reference.
  private let device = NSObject()

  func testStartUsingConnectsThenPairsThenStartsASession() throws {
    try FBAMDeviceManager.start(using: device, calls: stubbedCalls(), logger: logger)
    XCTAssertEqual(sUsageRecorder.recorded, ["connect", "is_paired", "validate_pairing", "start_session"])
  }

  func testStopUsingEndsTheSessionBeforeTheConnection() throws {
    try FBAMDeviceManager.stop(using: device, calls: stubbedCalls(), logger: logger)
    XCTAssertEqual(sUsageRecorder.recorded, ["stop_session", "disconnect"])
  }
}
