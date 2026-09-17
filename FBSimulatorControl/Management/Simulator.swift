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

/// An implementation of `Target` for iOS Simulators.
///
/// The async commands serialize their work onto `FBFuture`'s internal queues, so instances are
/// safe to pass across Swift concurrency domains.
public final class Simulator: Target, Hashable, CustomStringConvertible, @unchecked Sendable {

  // MARK: - Properties

  /// The underlying `SimDevice`.
  public let device: SimDevice

  /// The Simulator Set that the Simulator belongs to. Nil for simulators created outside a set.
  ///
  /// Referencing `SimulatorSet` here forms a strong-strong reference cycle between the set and
  /// the simulator. The set breaks it explicitly when a simulator is removed from the device set
  /// it wraps.
  public private(set) var set: SimulatorSet?

  /// The `SimulatorConfiguration` representing this Simulator.
  public let configuration: SimulatorConfiguration

  public let commandCache: TargetCommandCache

  public let logger: any ControlCoreLogger
  public let auxillaryDirectory: String

  private var _temporaryDirectory: TemporaryDirectory?

  // MARK: - Initializers

  public class func fromSimDevice(_ device: SimDevice, configuration: SimulatorConfiguration?, set: SimulatorSet) -> Simulator {
    Simulator(
      device: device,
      configuration: configuration ?? SimulatorConfiguration.inferSimulatorConfiguration(fromDevice: device),
      set: set,
      auxillaryDirectory: auxillaryDirectory(fromSimDevice: device),
      logger: set.logger)
  }

  public init(
    device: SimDevice,
    configuration: SimulatorConfiguration,
    set: SimulatorSet?,
    auxillaryDirectory: String,
    logger: (any ControlCoreLogger)?
  ) {
    self.device = device
    self.configuration = configuration
    self.set = set
    self.auxillaryDirectory = auxillaryDirectory
    self.logger = (logger ?? ControlCoreGlobalConfiguration.defaultLogger).withName(device.udid.uuidString)
    self.commandCache = TargetCommandCache()
  }

  // MARK: - TargetInfo

  public var uniqueIdentifier: String { udid }

  public var udid: String { device.udid.uuidString }

  public var name: String { device.name }

  public var state: FBiOSTargetState { FBiOSTargetState(rawValue: UInt(device.state)) ?? .unknown }

  public var targetType: FBiOSTargetType { .simulator }

  public var architectures: [FBArchitecture] { Array(ArchitectureProcessAdapter.hostMachineSupportedArchitectures()) }

  public var deviceType: DeviceType { configuration.device }

  public var osVersion: OSVersion { configuration.os }

  public var extendedInformation: [String: Any] { [:] }

  // MARK: - Target

  public var runtimeRootDirectory: String { get async { device.runtime.root } }

  public var platformRootDirectory: String {
    get async {
      (XcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneSimulator.platform")
    }
  }

  public var screenInfo: TargetScreenInfo? {
    guard let deviceType = device.deviceType else {
      return nil
    }
    return TargetScreenInfo(
      widthPixels: UInt(deviceType.mainScreenSize.width),
      heightPixels: UInt(deviceType.mainScreenSize.height),
      scale: deviceType.mainScreenScale)
  }

  public var temporaryDirectory: TemporaryDirectory {
    if let _temporaryDirectory {
      return _temporaryDirectory
    }
    let directory = TemporaryDirectory.temporaryDirectory(logger: logger)
    _temporaryDirectory = directory
    return directory
  }

  public var workQueue: DispatchQueue { .main }

  public var asyncQueue: DispatchQueue { .global(qos: .userInitiated) }

  public func replacementMapping() -> [String: String] {
    ["%%SIM_ROOT%%": dataDirectory ?? ""]
  }

  public func environmentAdditions() -> [String: String] { [:] }

  public func requiresBundlesToBeSigned() -> Bool { true }

  /// A simulator is its own command source. The protocol requires a non-throwing `Self`, so a mismatch can
  /// only trap (not catchable by `FBObjCExceptionGuard`).
  public static func commands(with target: any Target) -> Self {
    guard let simulator = target as? Self else {
      preconditionFailure("\(type(of: target)) is not a Simulator, so it cannot provide simulator commands")
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
  public var stateString: TargetStateString {
    state.stateString
  }

  /// The Directory that Contains the Simulator's Data.
  var dataDirectory: String? { device.dataPath() }

  public var customDeviceSetPath: String? {
    let setPath = device.deviceSet?.setPath
    return setPath == (DefaultDeviceSet as NSString).expandingTildeInPath ? nil : setPath
  }

  /// A command executor for simctl.
  ///
  /// Used by an out-of-tree consumer for clipboard support (`simctl pbcopy` /
  /// `simctl pbpaste`), which has no CoreSimulator API.
  public var simctlExecutor: AppleSimctlCommandExecutor {
    AppleSimctlCommandExecutor.executor(for: self)
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

  public static func == (lhs: Simulator, rhs: Simulator) -> Bool {
    lhs.device.isEqual(rhs.device)
  }

  public var description: String {
    self.targetDescription
  }

  private class func auxillaryDirectory(fromSimDevice device: SimDevice) -> String {
    ((device.dataPath() ?? "") as NSString).appendingPathComponent("fbsimulatorcontrol")
  }
}
