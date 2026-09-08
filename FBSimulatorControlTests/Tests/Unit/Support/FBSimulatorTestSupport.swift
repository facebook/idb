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
@objc final class FBStubSimDevice: NSObject {
  @objc let UDID: NSUUID = NSUUID()
}

/// Named stand-in for `SimDevice.runtime` / `SimDevice.deviceType`. Only `name` is read, by
/// the configuration synthesis below.
@objc final class FBStubSimNamed: NSObject {
  @objc let name: String

  init(name: String) {
    self.name = name
    super.init()
  }
}

/// A device whose runtime and device-type names are always present, used solely to synthesize
/// a configuration for the tests.
@objc final class FBStubConfigurationSimDevice: NSObject {
  @objc let runtime = FBStubSimNamed(name: "iOS 17.0")
  @objc let deviceType = FBStubSimNamed(name: "iPhone 15")
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
/// returned simulator's `commandCache` (`FBTargetCommandCache.register(_:as:)`); `device`-derived
/// properties are stub-backed and must not be exercised.
enum FBSimulatorTestSupport {

  static func testableSimulator() -> FBSimulator {
    testableSimulator(withDevice: FBStubSimDevice())
  }

  /// Variant that lets the caller substitute a custom device double. Useful when production
  /// code under test reads `simulator.state` (which delegates to `device.state`) or calls
  /// `device.responds(to:)`. The supplied object must respond to `UDID` (returning `NSUUID`)
  /// and any other selectors the code path exercises.
  static func testableSimulator(withDevice device: AnyObject) -> FBSimulator {
    let logger = FBControlCoreLoggerFactory.logger(to: FBNullDataConsumer())
    // Synthesize the configuration from a stub rather than asking for the default one.
    // `defaultConfiguration` pins a hardcoded device model and then resolves the newest
    // *installed* runtime that supports it, so it returns nil on a host whose runtimes have
    // dropped that model — a host dependency these tests should not have. They never read the
    // configuration back; the initializer only stores it.
    let configuration = FBSimulatorConfiguration.inferSimulatorConfigurationFromDeviceSynthesizingMissing(
      asSimDevice(FBStubConfigurationSimDevice()))
    return FBSimulator(
      device: asSimDevice(device),
      configuration: configuration,
      set: nil,
      auxillaryDirectory: NSTemporaryDirectory(),
      logger: logger)
  }
}
