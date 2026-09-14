/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import FBControlCore
import FBSimulatorControl
import Foundation

/// Bare-minimum `SimDevice` stand-in: `FBSimulator.init` reads only `UDID.uuidString` (to name the
/// logger); everything else on the unit-test path is intercepted by a registered wrapping command class.
/// Reached by Objective-C message send, hence `@objc` `NSObject`.
@objc final class StubSimDevice: NSObject {
  @objc let UDID: NSUUID = NSUUID()
}

/// Reinterprets a test double as `SimDevice`.
///
/// The doubles are not `SimDevice`s — they merely respond to the selectors the simulator sends
/// them — so any *checked* conversion (`as!`, `unsafeDowncast`) traps. Round-tripping the
/// reference through its opaque pointer performs no check.
private func asSimDevice(_ object: AnyObject) -> SimDevice {
  Unmanaged<SimDevice>.fromOpaque(Unmanaged.passUnretained(object).toOpaque()).takeUnretainedValue()
}

/// Reinterprets a test double as `SimDeviceSet`, for the same reason as `asSimDevice`.
private func asSimDeviceSet(_ object: AnyObject) -> SimDeviceSet {
  Unmanaged<SimDeviceSet>.fromOpaque(Unmanaged.passUnretained(object).toOpaque()).takeUnretainedValue()
}

/// Builds an `FBSimulatorSet` around a device set double.
func createSimulatorSet(
  configuration: FBSimulatorControlConfiguration,
  fakeDeviceSet: AnyObject,
  logger: (any FBControlCoreLogger)? = nil
) -> FBSimulatorSet {
  do {
    return try FBSimulatorSet.set(
      withConfiguration: configuration,
      deviceSet: asSimDeviceSet(fakeDeviceSet),
      delegate: nil,
      logger: logger)
  } catch {
    preconditionFailure("Failed to create the simulator set: \(error)")
  }
}

/// Builds `FBSimulator`s for unit tests. Tests pre-register a wrapping command class on the
/// returned simulator's `commandCache` (`TargetCommandCache.register(_:as:)`); `device`-derived
/// properties are stub-backed and must not be exercised.
enum SimulatorTestSupport {

  static func testableSimulator() -> FBSimulator {
    testableSimulator(withDevice: StubSimDevice())
  }

  /// Reinterprets a device double as `SimDevice`, for code under test that takes the CoreSimulator
  /// type directly rather than an `FBSimulator`.
  static func asDevice(_ object: AnyObject) -> SimDevice {
    asSimDevice(object)
  }

  /// Variant that lets the caller substitute a custom device double. Useful when production
  /// code under test reads `simulator.state` (which delegates to `device.state`) or calls
  /// `device.responds(to:)`. The supplied object must respond to `UDID` (returning `NSUUID`)
  /// and any other selectors the code path exercises.
  static func testableSimulator(withDevice device: AnyObject) -> FBSimulator {
    let logger = FBControlCoreLoggerFactory.logger(to: FBNullDataConsumer())
    let configuration = FBSimulatorConfiguration(
      device: .generic(withName: "Test Device"), os: .generic(withName: "TestOS 99.0"))
    return FBSimulator(
      device: asSimDevice(device),
      configuration: configuration,
      set: nil,
      auxillaryDirectory: NSTemporaryDirectory(),
      logger: logger)
  }
}
