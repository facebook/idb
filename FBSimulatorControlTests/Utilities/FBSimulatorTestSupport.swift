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

/// Bare-minimum stand-in for `SimDevice`. The `FBSimulator` designated initializer only reads
/// `UDID.uuidString` (to name the logger); nothing on the unit-test path reaches the device
/// through its other properties, because tests register a wrapping command class that
/// intercepts before any device access.
///
/// The stubs are `@objc` `NSObject` subclasses because the simulator reaches them by
/// Objective-C message send, having been handed one in place of a real `SimDevice`.
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

/// Helpers that construct an `FBSimulator` instance suitable for unit tests.
///
/// The unit-test path is intended never to reach production code that touches the real
/// `SimDevice`; the only thing the returned simulator needs to do is expose its `commandCache`
/// so tests can pre-register a wrapping command class (see `FBTargetCommandCache.register(_:as:)`).
/// The returned simulator's `device`-derived properties are NOT guaranteed to be correct and
/// must not be exercised on the test path.
enum FBSimulatorTestSupport {

  /// Builds an `FBSimulator` whose `commandCache` is empty and ready for `register(_:as:)`
  /// calls. Do NOT exercise `device`-derived properties on the returned simulator — they are
  /// stub-backed and unsafe.
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
    // The initializer only stores fields and reads `device.UDID.uuidString`; everything else on
    // the test path is intercepted before it reaches the device.
    return FBSimulator(
      device: asSimDevice(device),
      configuration: configuration,
      set: nil,
      auxillaryDirectory: NSTemporaryDirectory(),
      logger: logger)
  }
}
