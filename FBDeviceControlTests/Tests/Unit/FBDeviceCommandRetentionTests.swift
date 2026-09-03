/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBDeviceControl
import Foundation
import Testing

/// Every command accessor on `FBDevice`, so the retention rule is checked against all of them
/// rather than a hand-picked few.
enum FBDeviceCommandAccessor: CaseIterable, Sendable {
  case application
  case crashLog
  case screenshot
  case location
  case debugger
  case file
  case lifecycle
  case log
  case videoRecording
  case xctest
  case xctraceRecord
  case diagnosticInformation
  case erase
  case power
  case provisioningProfile
  case activation
  case recovery
  case debugSymbols
  case developerDiskImage
  case socketForwarding

  func resolve(on device: FBDevice) {
    switch self {
    case .application:
      _ = device.application
    case .crashLog:
      _ = device.crashLog
    case .screenshot:
      _ = device.screenshot
    case .location:
      _ = device.location
    case .debugger:
      _ = device.debugger
    case .file:
      _ = device.file
    case .lifecycle:
      _ = device.lifecycle
    case .log:
      _ = device.log
    case .videoRecording:
      _ = device.videoRecording
    case .xctest:
      _ = device.xctest
    case .xctraceRecord:
      _ = device.xctraceRecord
    case .diagnosticInformation:
      _ = device.diagnosticInformation
    case .erase:
      _ = device.erase
    case .power:
      _ = device.power
    case .provisioningProfile:
      _ = device.provisioningProfile
    case .activation:
      _ = device.activation
    case .recovery:
      _ = device.recovery
    case .debugSymbols:
      _ = device.debugSymbols
    case .developerDiskImage:
      _ = device.developerDiskImage
    case .socketForwarding:
      _ = device.socketForwarding
    }
  }

  /// BUG: `xctraceRecord` is memoized yet holds the device strongly, so resolving it closes the
  /// cycle described on the suite below and the device is never released. The expectation is
  /// flipped to `false` in the commit that fixes it.
  var retainsTheDevice: Bool {
    switch self {
    case .xctraceRecord:
      return true
    default:
      return false
    }
  }
}

/// Whether resolving a command class keeps the device alive.
///
/// A device owns its `commandCache`; the cache owns whatever is resolved into it. Every command on
/// `FBDevice` is memoized, so a command holding its device strongly closes a cycle — device to
/// cache to command to device — and the device can never be released. This is why the device
/// command classes hold `weak var device`.
@MainActor
// Serialized for the same reason as the other device-driving suites in this target: the devices
// these tests build run their work and async queues on the main queue.
@Suite("Device command retention", .serialized)
struct FBDeviceCommandRetentionTests {

  /// Resolves a command, then reports whether the device survived the only strong reference to it
  /// going away.
  private func deviceSurvives(_ resolve: (FBDevice) -> Void) -> Bool {
    weak var weakDevice: FBDevice?
    autoreleasepool {
      let device = FakeAMDevice().makeDevice()
      weakDevice = device
      resolve(device)
    }
    return weakDevice != nil
  }

  /// Without this, a harness that leaks the device for its own reasons would report every accessor
  /// as retaining and the rule below would be vacuous.
  @Test("A device nothing was resolved on is released")
  func aDeviceWithNoCommandsResolvedIsReleased() {
    #expect(deviceSurvives { _ in } == false)
  }

  @Test("Resolving a command does not retain the device", arguments: FBDeviceCommandAccessor.allCases)
  func resolvingACommandDoesNotRetainTheDevice(_ accessor: FBDeviceCommandAccessor) {
    #expect(deviceSurvives { accessor.resolve(on: $0) } == accessor.retainsTheDevice)
  }
}
