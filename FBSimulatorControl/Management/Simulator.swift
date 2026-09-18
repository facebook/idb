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

  public var state: TargetState { TargetState(rawValue: UInt(device.state)) ?? .unknown }

  public var targetType: TargetType { .simulator }

  public var architectures: [Architecture] { Array(ArchitectureProcessAdapter.hostMachineSupportedArchitectures()) }

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
  var productFamily: ProductFamily {
    switch device.deviceType?.productFamilyID {
    case .some(1):
      return .iPhone
    case .some(2):
      return .iPad
    case .some(3):
      return .appleTV
    case .some(4):
      return .appleWatch
    default:
      return .unknown
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

// Commands that own something outliving a single call — a notifier, an in-flight video, a task —
// are memoized through `commandCache` (`TargetCommandCache`), whose lock also stops two callers
// racing the first construction. Commands that only wrap the simulator are built per call: a slot
// for one would hold a box around a pointer back to the object owning the cache, closing a retain
// cycle.
extension Simulator {

  // MARK: - Shared accessors

  public var application: SimulatorApplicationCommands {
    SimulatorApplicationCommands.commands(with: self)
  }

  public var crashLog: SimulatorCrashLogCommands {
    commandCache.resolve { SimulatorCrashLogCommands.commands(with: self) }
  }

  public var screenshot: SimulatorScreenshotCommands {
    commandCache.resolve { SimulatorScreenshotCommands.commands(with: self) }
  }

  public var location: SimulatorLocationCommands {
    SimulatorLocationCommands.commands(with: self)
  }

  public var debugger: SimulatorDebuggerCommands {
    commandCache.resolve { SimulatorDebuggerCommands.commands(with: self) }
  }

  public var file: SimulatorFileCommands {
    SimulatorFileCommands.commands(with: self)
  }

  public var log: SimulatorLogCommands {
    SimulatorLogCommands.commands(with: self)
  }

  public var processSpawn: SimulatorProcessSpawnCommands {
    SimulatorProcessSpawnCommands.commands(with: self)
  }

  public var videoRecording: SimulatorVideoRecordingCommands {
    commandCache.resolve { SimulatorVideoRecordingCommands.commands(with: self) }
  }

  public var videoStream: SimulatorVideoStreamCommands {
    SimulatorVideoStreamCommands.commands(with: self)
  }

  public var launchCtl: SimulatorLaunchCtlCommands {
    SimulatorLaunchCtlCommands.commands(with: self)
  }

  public var xctraceRecord: TargetXCTraceRecordCommands {
    TargetXCTraceRecordCommands.commands(with: self)
  }

  public var instruments: SimulatorInstrumentsCommands {
    SimulatorInstrumentsCommands.commands(with: self)
  }

  // MARK: - Sim-only accessors

  public var lifecycle: SimulatorLifecycleCommands {
    commandCache.resolve { SimulatorLifecycleCommands.commands(with: self) }
  }

  public var power: SimulatorPowerCommands {
    SimulatorPowerCommands.commands(with: self)
  }

  public var media: SimulatorMediaCommands {
    SimulatorMediaCommands.commands(with: self)
  }

  public var keychain: SimulatorKeychainCommands {
    SimulatorKeychainCommands.commands(with: self)
  }

  public var privacy: SimulatorPrivacyCommands {
    SimulatorPrivacyCommands.commands(with: self)
  }

  public var preferences: SimulatorPreferencesCommands {
    SimulatorPreferencesCommands.commands(with: self)
  }

  public var statusBar: SimulatorStatusBarCommands {
    SimulatorStatusBarCommands.commands(with: self)
  }

  public var network: SimulatorNetworkCommands {
    SimulatorNetworkCommands.commands(with: self)
  }

  public var health: SimulatorHealthCommands {
    SimulatorHealthCommands.commands(with: self)
  }

  public var contacts: SimulatorContactsCommands {
    SimulatorContactsCommands.commands(with: self)
  }

  public var photos: SimulatorPhotosCommands {
    SimulatorPhotosCommands.commands(with: self)
  }

  /// The converged UI-automation surface for `backend` — element reads and element-targeted actions
  /// over a single query-shaped API. Every call returns a fresh reader; the readers are cheap, and
  /// where a backend owns an expensive warm resource, who owns it differs by backend:
  ///
  /// - `.axBridge(persistence: .shared, …)` reads over a guest `serve` process on the simulator's
  ///   well-known socket, shared with every other process reading the same simulator. The connection is
  ///   released after each round trip so the next reader can have it, and no host ever ends the guest —
  ///   only its own idle timeout does.
  /// - `.axBridge(persistence: .exclusive, …)` reads over a guest of the caller's own, on a socket
  ///   nobody else can discover. Memoized per simulator and per persistence, and holds its connection
  ///   between reads. The guest was spawned with `--exit-on-disconnect`, so closing that connection is
  ///   what ends it — for a process that owns the simulator for its lifetime.
  /// - `.accessibility` and `.axBridge(persistence: .oneShot, …)` are stateless — they hold no warm
  ///   resource, so reconstructing them per call is free.
  public func uiAutomation(backend: UIAutomationBackend) throws -> any UIAutomation {
    switch backend {
    case .accessibility:
      return AccessibilityUIAutomation(simulator: self)
    case let .axBridge(persistence, frontmostMethod, automationMode):
      let transport: any AXBridgeTransport =
        switch persistence {
        case .oneShot: AXBridgeOneshotTransport(simulator: self)
        case .shared: axBridgeTransport(scope: .shared)
        case .exclusive: axBridgeTransport(scope: .exclusive)
        }
      return AXBridgeUIAutomation(
        simulator: self, transport: transport, persistence: persistence, frontmostMethod: frontmostMethod,
        automationMode: automationMode
      )
    }
  }

  var accessibility: SimulatorAccessibilityCommands {
    commandCache.resolve { SimulatorAccessibilityCommands.commands(with: self) }
  }

  public var dapServer: SimulatorDapServerCommand {
    SimulatorDapServerCommand.commands(with: self)
  }

  public var notification: SimulatorNotificationCommands {
    SimulatorNotificationCommands.commands(with: self)
  }

  public var memory: SimulatorMemoryCommands {
    SimulatorMemoryCommands.commands(with: self)
  }

  public var audio: SimulatorAudioCommands {
    SimulatorAudioCommands.commands(with: self)
  }

  public var runtimeTools: SimulatorRuntimeToolCommands {
    SimulatorRuntimeToolCommands.commands(with: self)
  }

  public var bootstrapPorts: SimulatorBootstrapPortCommands {
    SimulatorBootstrapPortCommands.commands(with: self)
  }

  // MARK: - Command verbs

  public func erase() async throws {
    try await SimulatorEraseStrategy.erase(self)
  }
}

/// The failures of running a service inside the guest with `SimulatorFrameworkBridge`.
public enum SimulatorFrameworkBridgeError: Error, LocalizedError {

  /// The bridge binary is not present in the companion's Resources directory.
  case binaryMissing

  /// The bridge ran and reported a failure.
  case serviceFailed(service: String, action: String, exitCode: Int32, stderr: String)

  static func failureDetails(stderr: Data, stdout: Data) -> String {
    let details = [stderr, stdout]
      .compactMap { String(data: $0, encoding: .utf8) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n")
    return details.isEmpty ? "no output" : details
  }

  public var errorDescription: String? {
    switch self {
    case .binaryMissing:
      return "SimulatorFrameworkBridge binary not found in the companion Resources directory"
    case let .serviceFailed(service, action, exitCode, stderr):
      return "SimulatorFrameworkBridge \(service) \(action) failed with exit code \(exitCode): \(stderr)"
    }
  }
}

// MARK: - SimulatorFrameworkBridge

extension Simulator {

  /// Runs one of `SimulatorFrameworkBridge`'s services inside the guest, returning its stdout.
  ///
  /// The bridge is a guest binary spawned into the booted simulator, so it reaches frameworks and
  /// daemons that exist only there. `ServiceDispatch.m` holds the set of services and their actions.
  @discardableResult
  func runSimulatorFrameworkBridge(
    withService service: String,
    action: String,
    arguments: [String] = []
  ) async throws -> String {
    guard let helperPath = frameworkBridgePath else {
      throw SimulatorFrameworkBridgeError.binaryMissing
    }

    let output = try await runtimeTools.launchConsumingOutput(
      launchPath: helperPath,
      arguments: [service, action] + arguments)
    guard output.exitCode == 0 else {
      let details = SimulatorFrameworkBridgeError.failureDetails(
        stderr: output.stderr,
        stdout: output.stdout)
      throw SimulatorFrameworkBridgeError.serviceFailed(
        service: service,
        action: action,
        exitCode: output.exitCode,
        stderr: details)
    }
    logger.log("SimulatorFrameworkBridge \(service) \(action) completed successfully")
    return String(data: output.stdout, encoding: .utf8) ?? ""
  }
}
