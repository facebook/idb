/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

/// Backed by a `MobileDevice`, a `RestorableDevice`, or both, caching the target
/// information of whichever it holds.
public final class Device: Target, DeviceCommands, CustomStringConvertible {

  // MARK: - Properties

  public private(set) weak var set: DeviceSet?
  public let commandCache: TargetCommandCache
  public private(set) var logger: any ControlCoreLogger
  public private(set) var calls: AMDCalls

  private var amDeviceStorage: MobileDevice?
  private var restorableDeviceStorage: RestorableDevice?

  public var amDevice: MobileDevice? {
    get {
      amDeviceStorage
    }
    set {
      amDeviceStorage = newValue
      if let newValue {
        cacheValues(from: newValue, overwrite: true)
      }
    }
  }

  var restorableDevice: RestorableDevice? {
    get {
      restorableDeviceStorage
    }
    set {
      restorableDeviceStorage = newValue
      if let newValue {
        cacheValues(from: newValue, overwrite: false)
      }
    }
  }

  // MARK: - Cached target information

  // Optional storage: the nil state is what `cacheValues(from:overwrite:)` tests to decide
  // whether a gap can be filled. The public accessors are non-optional because the initializer
  // always populates the cache from one of the two backing devices.

  private var cachedUniqueIdentifier: String?
  private var cachedUDID: String?
  private var cachedName: String?
  private var cachedDeviceType: DeviceType?
  private var cachedArchitectures: [Architecture]?
  private var cachedOSVersion: OSVersion?
  private var cachedExtendedInformation: [String: Any]?
  private var cachedTargetType: TargetType?
  private var cachedBuildVersion: String?
  private var cachedProductVersion: String?
  private var cachedActivationState: String?
  private var cachedAllValues: [String: Any]?

  public private(set) var state: TargetState = .unknown

  public var uniqueIdentifier: String { cachedUniqueIdentifier ?? "" }
  public var udid: String { cachedUDID ?? "" }
  public var name: String { cachedName ?? "" }
  public var deviceType: DeviceType { cachedDeviceType ?? DeviceType.generic(withName: "unknown") }
  public var architectures: [Architecture] { cachedArchitectures ?? [] }
  public var osVersion: OSVersion { cachedOSVersion ?? OSVersion.generic(withName: "unknown") }
  public var extendedInformation: [String: Any] { cachedExtendedInformation ?? [:] }
  public var targetType: TargetType { cachedTargetType ?? .none }
  public var buildVersion: String? { cachedBuildVersion }
  public var productVersion: String? { cachedProductVersion }
  public var activationState: String { cachedActivationState ?? "" }
  public var allValues: [String: Any] { cachedAllValues ?? [:] }

  public init(
    set: DeviceSet?,
    amDevice: MobileDevice?,
    restorableDevice: RestorableDevice?,
    logger: any ControlCoreLogger
  ) {
    self.set = set
    self.amDeviceStorage = amDevice
    self.restorableDeviceStorage = restorableDevice
    self.commandCache = TargetCommandCache()
    // Without a backing device there is no call table; fail here rather than through a null
    // function pointer later.
    if let amDevice {
      self.calls = amDevice.calls
    } else if let restorableDevice {
      self.calls = restorableDevice.calls
    } else {
      preconditionFailure("A MobileDevice or RestorableDevice must be provided")
    }
    self.logger = logger
    if let info: any TargetInfo & DeviceProtocol = amDevice ?? restorableDevice {
      cacheValues(from: info, overwrite: true)
    }
    self.logger = logger.withName(udid)
  }

  public static func commands(with target: any Target) -> Self {
    guard let device = target as? Self else {
      preconditionFailure("\(type(of: target)) is not a Device, so it cannot provide device commands")
    }
    return device
  }

  // MARK: - Target

  public var workQueue: DispatchQueue {
    // One of the two backing devices is always present, per the initializer's contract.
    (amDevice?.workQueue ?? restorableDevice?.workQueue) ?? DispatchQueue.main
  }

  public var asyncQueue: DispatchQueue {
    (amDevice?.asyncQueue ?? restorableDevice?.asyncQueue) ?? DispatchQueue.global()
  }

  private var temporaryDirectoryStorage: TemporaryDirectory?

  public var temporaryDirectory: TemporaryDirectory {
    if let temporaryDirectoryStorage {
      return temporaryDirectoryStorage
    }
    let created = TemporaryDirectory(logger: logger)
    temporaryDirectoryStorage = created
    return created
  }

  public var auxillaryDirectory: String {
    let cwd = FileManager.default.currentDirectoryPath
    return FileManager.default.isWritableFile(atPath: cwd) ? cwd : "/tmp"
  }

  public var platformRootDirectory: String {
    get async {
      (XcodeConfiguration.developerDirectory as NSString).appendingPathComponent("Platforms/iPhoneOS.platform")
    }
  }

  public var runtimeRootDirectory: String {
    get async { await platformRootDirectory }
  }

  public var screenInfo: TargetScreenInfo? {
    nil
  }

  public var customDeviceSetPath: String? {
    nil
  }

  public func requiresBundlesToBeSigned() -> Bool {
    true
  }

  public func replacementMapping() -> [String: String] {
    [:]
  }

  public func environmentAdditions() -> [String: String] {
    [:]
  }

  public var description: String {
    self.targetDescription
  }

  // MARK: - DeviceProtocol

  public var amDeviceRef: AMDevice? {
    amDevice?.amDeviceRef
  }

  public var recoveryModeDeviceRef: AMRecoveryModeDevice? {
    restorableDevice?.recoveryModeDeviceRef
  }

  // MARK: - DeviceCommands

  public func withConnectedDevice<T>(
    purpose: String,
    _ body: (any DeviceCommands) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: purpose)
    }
    return try await amDevice.withConnectedDevice(purpose: purpose, body)
  }

  public func withHouseArrestAFCConnection<T>(
    forBundleID bundleID: String,
    afcCalls: AFCCalls,
    _ body: (FileConduit) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: "withHouseArrestAFCConnection(forBundleID:afcCalls:)")
    }
    return try await amDevice.withHouseArrestAFCConnection(forBundleID: bundleID, afcCalls: afcCalls, body)
  }

  // MARK: - Private

  /// The AMDevice's richer information always overwrites; the restorable device's only fills what
  /// is not yet known. `calls` and `state` are refreshed from either.
  private func cacheValues(from targetInfo: any TargetInfo & DeviceProtocol, overwrite: Bool) {
    calls = targetInfo.calls
    state = targetInfo.state

    if cachedAllValues == nil || overwrite {
      cachedAllValues = targetInfo.allValues
    }
    if cachedArchitectures == nil || overwrite {
      cachedArchitectures = targetInfo.architectures
    }
    if cachedBuildVersion == nil || overwrite {
      cachedBuildVersion = targetInfo.buildVersion
    }
    if cachedDeviceType == nil || overwrite {
      cachedDeviceType = targetInfo.deviceType
    }
    if cachedExtendedInformation == nil || overwrite {
      cachedExtendedInformation = targetInfo.extendedInformation
    }
    if cachedName == nil || overwrite {
      cachedName = targetInfo.name
    }
    if cachedOSVersion == nil || overwrite {
      cachedOSVersion = targetInfo.osVersion
    }
    if cachedProductVersion == nil || overwrite {
      cachedProductVersion = targetInfo.productVersion
    }
    if cachedTargetType == nil || overwrite {
      cachedTargetType = targetInfo.targetType
    }
    if cachedUDID == nil || overwrite {
      cachedUDID = targetInfo.udid
    }
    if cachedUniqueIdentifier == nil || overwrite {
      cachedUniqueIdentifier = targetInfo.uniqueIdentifier
    }
    if cachedActivationState == nil || overwrite {
      cachedActivationState = targetInfo.activationState
    }
  }
}

// Commands that own something outliving a single call — a notifier, an in-flight video, a set of
// AFC calls — are memoized through `commandCache` (`TargetCommandCache`), whose lock also stops
// two callers racing the first construction, and hold their device weakly so the cache slot does
// not close a cycle. Commands that only wrap the device are built per call and hold it strongly:
// nothing outlives the call that builds them.
extension Device {

  // MARK: - Shared accessors

  public var application: DeviceApplicationCommands {
    commandCache.resolve { DeviceApplicationCommands.commands(with: self) }
  }

  public var crashLog: DeviceCrashLogCommands {
    commandCache.resolve { DeviceCrashLogCommands.commands(with: self) }
  }

  public var screenshot: DeviceScreenshotCommands {
    DeviceScreenshotCommands.commands(with: self)
  }

  public var location: DeviceLocationCommands {
    DeviceLocationCommands.commands(with: self)
  }

  public var debugger: DeviceDebuggerCommands {
    DeviceDebuggerCommands.commands(with: self)
  }

  public var file: DeviceFileCommands {
    commandCache.resolve { DeviceFileCommands.commands(with: self) }
  }

  public var lifecycle: DeviceLifecycleCommands {
    DeviceLifecycleCommands.commands(with: self)
  }

  public var log: DeviceLogCommands {
    DeviceLogCommands.commands(with: self)
  }

  public var videoRecording: DeviceVideoRecordingCommands {
    commandCache.resolve { DeviceVideoRecordingCommands.commands(with: self) }
  }

  public var videoStream: DeviceVideoStreamCommands {
    DeviceVideoStreamCommands.commands(with: self)
  }

  public var xctest: DeviceXCTestCommands {
    commandCache.resolve { DeviceXCTestCommands.commands(with: self) }
  }

  public var xctraceRecord: TargetXCTraceRecordCommands {
    TargetXCTraceRecordCommands.commands(with: self)
  }

  public var instruments: DeviceInstrumentsCommands {
    DeviceInstrumentsCommands.commands(with: self)
  }

  // MARK: - Device-only accessors

  public var diagnosticInformation: DeviceDiagnosticInformationCommands {
    DeviceDiagnosticInformationCommands.commands(with: self)
  }

  public var erase: DeviceEraseCommands {
    DeviceEraseCommands.commands(with: self)
  }

  public var power: DevicePowerCommands {
    DevicePowerCommands.commands(with: self)
  }

  public var provisioningProfile: DeviceProvisioningProfileCommands {
    DeviceProvisioningProfileCommands.commands(with: self)
  }

  public var activation: DeviceActivationCommands {
    DeviceActivationCommands.commands(with: self)
  }

  public var recovery: DeviceRecoveryCommands {
    DeviceRecoveryCommands.commands(with: self)
  }

  public var debugSymbols: DeviceDebugSymbolsCommands {
    DeviceDebugSymbolsCommands(device: self)
  }

  public var developerDiskImage: DeviceDeveloperDiskImageCommands {
    commandCache.resolve { DeviceDeveloperDiskImageCommands.commands(with: self) }
  }

  public var socketForwarding: DeviceSocketForwardingCommands {
    DeviceSocketForwardingCommands.commands(with: self)
  }

  public var springboard: DeviceSpringboardCommands {
    DeviceSpringboardCommands.commands(with: self)
  }
}

extension Device {

  /// Starts a service on the device, invalidating the connection once `body` returns or throws.
  ///
  /// The async counterpart of `startService`, which this mirrors including its restriction to
  /// AMDevice-backed devices.
  func withServiceConnection<T>(
    _ service: String,
    _ body: (LockdownServiceConnection) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.withServiceConnection(service, body)
  }

  /// Starts a service whose connection outlives this call, handing ownership to the caller, who
  /// hands it back to `MobileDevice.invalidateServiceConnection`.
  func openServiceConnection(_ service: String) async throws -> LockdownServiceConnection {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.openServiceConnection(service)
  }

  /// Starts a device link service, invalidating the connection once `body` returns or throws.
  func withDeviceLinkClient<T>(
    _ service: String,
    _ body: (DeviceLinkClient) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.withDeviceLinkClient(service, body)
  }

  /// Starts a service and wraps it in an AFC client, tearing both down once `body` returns or
  /// throws.
  func withAFCConnection<T>(
    _ service: String,
    calls afcCalls: AFCCalls = FileConduit.defaultCalls,
    _ body: (FileConduit) async throws -> T
  ) async throws -> T {
    guard let amDevice else {
      throw AMDeviceServiceError.notAMDeviceBacked(service: service)
    }
    return try await amDevice.withAFCConnection(service, calls: afcCalls, body)
  }
}
