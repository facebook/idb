/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

private let DefaultDeviceSet = "~/Library/Developer/CoreSimulator/Devices"

/// An implementation of `FBiOSTarget` for iOS Simulators.
///
/// The async commands serialize their work onto `FBFuture`'s internal queues, so instances are
/// safe to pass across Swift concurrency domains.
public final class FBSimulator: FBiOSTarget, Hashable, CustomStringConvertible, @unchecked Sendable {

  // MARK: - Properties

  /// The underlying `SimDevice`.
  public let device: SimDevice

  /// The Simulator Set that the Simulator belongs to. Nil for simulators created outside a set.
  ///
  /// Referencing `FBSimulatorSet` here forms a strong-strong reference cycle between the set and
  /// the simulator. The set breaks it explicitly when a simulator is removed from the device set
  /// it wraps.
  public private(set) var set: FBSimulatorSet?

  /// The `FBSimulatorConfiguration` representing this Simulator.
  public var configuration: FBSimulatorConfiguration

  public let commandCache: FBTargetCommandCache

  public let logger: any FBControlCoreLogger
  public let auxillaryDirectory: String

  private var _temporaryDirectory: FBTemporaryDirectory?

  // MARK: - Initializers

  public class func fromSimDevice(_ device: SimDevice, configuration: FBSimulatorConfiguration?, set: FBSimulatorSet) -> FBSimulator {
    FBSimulator(
      device: device,
      configuration: configuration ?? FBSimulatorConfiguration.inferSimulatorConfigurationFromDeviceSynthesizingMissing(device),
      set: set,
      auxillaryDirectory: auxillaryDirectory(fromSimDevice: device),
      logger: set.logger)
  }

  public init(
    device: SimDevice,
    configuration: FBSimulatorConfiguration,
    set: FBSimulatorSet?,
    auxillaryDirectory: String,
    logger: (any FBControlCoreLogger)?
  ) {
    self.device = device
    self.configuration = configuration
    self.set = set
    self.auxillaryDirectory = auxillaryDirectory
    self.logger = (logger ?? FBControlCoreGlobalConfiguration.defaultLogger).withName(device.udid.uuidString)
    self.commandCache = FBTargetCommandCache()
  }

  // MARK: - FBiOSTargetInfo

  public var uniqueIdentifier: String { udid }

  public var udid: String { device.udid.uuidString }

  public var name: String { device.name }

  public var state: FBiOSTargetState { FBiOSTargetState(rawValue: UInt(device.state)) ?? .unknown }

  public var targetType: FBiOSTargetType { .simulator }

  public var architectures: [FBArchitecture] { Array(FBArchitectureProcessAdapter.hostMachineSupportedArchitectures()) }

  public var deviceType: FBDeviceType { configuration.device }

  public var osVersion: FBOSVersion { configuration.os }

  public var extendedInformation: [String: Any] { [:] }

  // MARK: - FBiOSTarget

  public var runtimeRootDirectory: String { get async { device.runtime.root } }

  public var platformRootDirectory: String {
    get async {
      (FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneSimulator.platform")
    }
  }

  public var screenInfo: FBiOSTargetScreenInfo? {
    guard let deviceType = device.deviceType else {
      return nil
    }
    return FBiOSTargetScreenInfo(
      widthPixels: UInt(deviceType.mainScreenSize.width),
      heightPixels: UInt(deviceType.mainScreenSize.height),
      scale: deviceType.mainScreenScale)
  }

  public var temporaryDirectory: FBTemporaryDirectory {
    if let _temporaryDirectory {
      return _temporaryDirectory
    }
    let directory = FBTemporaryDirectory.temporaryDirectory(logger: logger)
    _temporaryDirectory = directory
    return directory
  }

  public var workQueue: DispatchQueue { .main }

  public var asyncQueue: DispatchQueue { .global(qos: .userInitiated) }

  public func compare(_ target: any FBiOSTarget) -> ComparisonResult {
    FBiOSTargetComparison(self, target)
  }

  public func replacementMapping() -> [String: String] {
    ["%%SIM_ROOT%%": dataDirectory ?? ""]
  }

  public func environmentAdditions() -> [String: String] { [:] }

  public func requiresBundlesToBeSigned() -> Bool { true }

  /// A simulator is its own command source. The protocol requires a non-throwing `Self`, so a mismatch can
  /// only trap (not catchable by `FBObjCExceptionGuard`).
  public static func commands(with target: any FBiOSTarget) -> Self {
    guard let simulator = target as? Self else {
      preconditionFailure("\(type(of: target)) is not an FBSimulator, so it cannot provide simulator commands")
    }
    return simulator
  }

  // MARK: - Simulator Properties

  /// The Product Family of the Simulator.
  var productFamily: FBControlCoreProductFamily {
    switch device.deviceType?.productFamilyID {
    case .some(1):
      return .familyiPhone
    case .some(2):
      return .familyiPad
    case .some(3):
      return .familyAppleTV
    case .some(4):
      return .familyAppleWatch
    default:
      return .familyUnknown
    }
  }

  /// A string representation of the Simulator State.
  public var stateString: FBiOSTargetStateString {
    FBiOSTargetStateStringFromState(state)
  }

  /// The Directory that Contains the Simulator's Data.
  var dataDirectory: String? { device.dataPath() }

  public var customDeviceSetPath: String? {
    let setPath = device.deviceSet?.setPath
    return setPath == (DefaultDeviceSet as NSString).expandingTildeInPath ? nil : setPath
  }

  /// A command executor for simctl.
  ///
  /// Only used for video recording (`simctl io recordVideo`), which has no CoreSimulator API; all
  /// other operations spawn inside the simulator via CoreSimulator.
  public var simctlExecutor: FBAppleSimctlCommandExecutor {
    FBAppleSimctlCommandExecutor.executor(for: self)
  }

  /// The directory path of the expected location of the CoreSimulator logs directory.
  var coreSimulatorLogsDirectory: String {
    ((NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/CoreSimulator") as NSString)
      .appendingPathComponent(udid)
  }

  // MARK: - Hashable

  public func hash(into hasher: inout Hasher) {
    hasher.combine(device.hash)
  }

  public static func == (lhs: FBSimulator, rhs: FBSimulator) -> Bool {
    lhs.device.isEqual(rhs.device)
  }

  public var description: String {
    FBiOSTargetDescribe(self)
  }

  private class func auxillaryDirectory(fromSimDevice device: SimDevice) -> String {
    ((device.dataPath() ?? "") as NSString).appendingPathComponent("fbsimulatorcontrol")
  }
}

// MARK: - Healthcheck Helpers

extension FBSimulator {

  /// Bootstrap-namespace lookup for a Mach port name in the simulator. A live XPC round-trip to
  /// the CoreSimulator daemon (`SimDevice.lookup` is not cached).
  ///
  /// - Returns: the looked-up Mach port.
  /// - Throws: the device's own error if the lookup failed, or `FBSimulatorPortLookupError` when
  ///   the daemon reported no port without reporting an error.
  public func lookupBootstrapPortNamed(_ name: String) throws -> NSNumber {
    var error: NSError?
    let port = device.lookup(name, error: &error)
    // The port is checked before the error: CoreSimulator is unannotated private API, and a
    // populated error alongside a valid port is a success.
    guard port != mach_port_t(MACH_PORT_NULL) else {
      throw error ?? FBSimulatorPortLookupError.portNotFound(name: name)
    }
    return NSNumber(value: port)
  }
}

/// The way a bootstrap-port lookup fails without the daemon reporting an error of its own.
public enum FBSimulatorPortLookupError: Error, LocalizedError {
  case portNotFound(name: String)

  public var errorDescription: String? {
    switch self {
    case let .portNotFound(name):
      return "No mach port named \(name) is registered in the simulator's bootstrap namespace"
    }
  }
}
