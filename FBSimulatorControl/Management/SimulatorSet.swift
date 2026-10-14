/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

/// Queries, creates and deletes the simulators in a `SimDeviceSet`, and reports their changes to its `delegate`.
///
/// A set does not own the `Simulator`s it returns: they come from the same process-wide registry as
/// `Simulator.fromSimDevice(_:logger:hidEventLogging:)`, so a device has one live `Simulator`
/// however it is reached, and the set keeps none alive.
public final class SimulatorSet: TargetSet {

  public let configuration: SimulatorControlConfiguration
  public let deviceSet: SimDeviceSet
  public weak var delegate: (any TargetSetDelegate)?
  public let logger: any ControlCoreLogger
  public let workQueue: DispatchQueue
  public let asyncQueue: DispatchQueue

  // Held only so that the strategy's notifier stays registered for the lifetime of the set; it is never read.
  private var notificationUpdateStrategy: SimulatorNotificationUpdateStrategy?

  /// - Parameter logger: nil means `ControlCoreGlobalConfiguration.defaultLogger`, which is
  ///   os_log-only unless the `FBCONTROLCORE_LOGGING`/`FBCONTROLCORE_DEBUG_LOGGING` environment
  ///   variables are set — see its documentation. The resolved logger is stored non-optionally.
  public static func set(withConfiguration configuration: SimulatorControlConfiguration, deviceSet: SimDeviceSet, delegate: (any TargetSetDelegate)?, logger: (any ControlCoreLogger)?) throws -> SimulatorSet {
    let resolvedLogger = logger ?? ControlCoreGlobalConfiguration.defaultLogger
    try SimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(resolvedLogger)
    return SimulatorSet(configuration: configuration, deviceSet: deviceSet, delegate: delegate, logger: resolvedLogger)
  }

  private init(configuration: SimulatorControlConfiguration, deviceSet: SimDeviceSet, delegate: (any TargetSetDelegate)?, logger: any ControlCoreLogger) {
    self.configuration = configuration
    self.deviceSet = deviceSet
    self.delegate = delegate
    self.logger = logger
    self.workQueue = DispatchQueue.main
    self.asyncQueue = DispatchQueue.global(qos: .default)
    self.notificationUpdateStrategy = SimulatorNotificationUpdateStrategy.strategy(with: self)
  }

  // MARK: - Querying

  public func target(withUDID udid: String) -> (any TargetInfo)? {
    return simulator(withUDID: udid)
  }

  public func simulator(withUDID udid: String) -> Simulator? {
    guard let uuid = NSUUID(uuidString: udid), let item = deviceSet.devicesByUDID?[uuid] else {
      return nil
    }
    let device = Self.simDevice(item)
    guard device.available else {
      return nil
    }
    return vend(device)
  }

  // MARK: - Creation

  public func createSimulator(with request: SimulatorCreationRequest) async throws -> Simulator {
    let deviceType: SimDeviceType
    let runtime: SimRuntime
    do {
      let snapshot = try CoreSimulatorRuntimeIndex.load()
      (deviceType, runtime) = try snapshot.resolve(request)
    } catch {
      throw SimulatorSetError.deviceTypeOrRuntimeUnavailable(configuration: "\(request)", reason: error.localizedDescription)
    }

    logger.debug().log("Creating device with Type \(deviceType) Runtime \(runtime)")
    let device = try await Self.createDevice(on: deviceSet, type: deviceType, runtime: runtime, name: deviceType.name ?? deviceType.identifier, queue: asyncQueue)
    let simulator = try fetchNewlyMadeSimulatorOrThrow(device)
    logger.debug().log("Created Simulator \(simulator.udid) for request \(request)")
    do {
      try await simulator.power.shutdown()
    } catch {
      throw SimulatorSetError.shutdownAfterCreateFailed(reason: error.localizedDescription)
    }
    return simulator
  }

  public func cloneSimulator(_ simulator: Simulator, toDeviceSet destinationSet: SimulatorSet) async throws -> Simulator {
    let device = try await Self.cloneDevice(on: deviceSet, device: simulator.device, toDeviceSet: destinationSet.deviceSet, queue: asyncQueue)
    return try destinationSet.fetchNewlyMadeSimulatorOrThrow(device)
  }

  // MARK: - Destructive Methods

  public func shutdown(_ simulator: Simulator) async throws {
    try await simulator.power.shutdown()
  }

  public func delete(_ simulator: Simulator) async throws {
    // Capture the Log Directory ahead of time as the Simulator will disappear on deletion.
    let coreSimulatorLogsDirectory = simulator.coreSimulatorLogsDirectory
    let udid = simulator.udid
    guard let deviceSet = simulator.device.deviceSet else {
      throw SimulatorSetError.simulatorHasNoSet(udid: simulator.udid)
    }
    let logger = simulator.logger

    logger.log("Killing Simulator, in preparation for deletion \(simulator)")
    try await simulator.power.shutdown()

    logger.log("Deleting Simulator \(simulator)")
    try await Self.deleteDevice(simulator.device, on: deviceSet, queue: simulator.asyncQueue)

    logger.log("Simulator \(udid) Deleted")

    if FileManager.default.fileExists(atPath: coreSimulatorLogsDirectory) {
      logger.log("Deleting Simulator Log Directory at \(coreSimulatorLogsDirectory)")
      do {
        try FileManager.default.removeItem(atPath: coreSimulatorLogsDirectory)
        logger.log("Deleted Simulator Log Directory at \(coreSimulatorLogsDirectory)")
      } catch {
        logger.error().log("Failed to delete Simulator Log Directory \(coreSimulatorLogsDirectory): \(error)")
      }
    }

    logger.log("Confirming \(udid) has been removed from set")
    try await Self.confirmSimulatorUDID(udid, isRemovedFromSet: deviceSet)
    logger.log("\(udid) has been removed from set")
  }

  func shutdownAll(_ simulators: [Simulator]) async throws {
    for simulator in simulators {
      try await simulator.power.shutdown()
    }
  }

  public func deleteAll(_ simulators: [Simulator]) async throws {
    for simulator in simulators {
      try await delete(simulator)
    }
  }

  func shutdownAll() async throws {
    try await shutdownAll(allSimulators)
  }

  public func deleteAll() async throws {
    try await deleteAll(allSimulators)
  }

  public var description: String {
    CollectionInformation.oneLineDescription(from: allSimulators)
  }

  public var allTargetInfos: [any TargetInfo] {
    allSimulators
  }

  public var allSimulators: [Simulator] {
    let devices = (deviceSet.availableDevices ?? []).map(Self.simDevice)
    return devices.map(vend).sorted { ($0 as Simulator).compare($1 as any Target) == .orderedAscending }
  }

  // Unchecked because unit tests stand in doubles that respond to `SimDevice`'s selectors without
  // being instances of it, which a checked cast rejects. A real `SimDeviceSet` vends only `SimDevice`s.
  private static func simDevice(_ item: Any) -> SimDevice {
    unsafeBitCast(item as AnyObject, to: SimDevice.self)
  }

  private func vend(_ device: SimDevice) -> Simulator {
    Simulator.fromSimDevice(device, logger: logger, hidEventLogging: configuration.hidEventLogging)
  }

  private func fetchNewlyMadeSimulatorOrThrow(_ device: SimDevice) throws -> Simulator {
    guard let simulator = simulator(withUDID: device.udid.uuidString) else {
      throw SimulatorSetError.simulatorNotInflated(udid: device.udid.uuidString)
    }
    return simulator
  }

  private static func createDevice(on deviceSet: SimDeviceSet, type deviceType: SimDeviceType, runtime: SimRuntime, name: String, queue: DispatchQueue) async throws -> SimDevice {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SimDevice, Error>) in
      deviceSet.createDeviceAsync(withType: deviceType, runtime: runtime, name: name, completionQueue: queue) { error, device in
        if let device {
          continuation.resume(returning: device)
        } else {
          continuation.resume(throwing: error ?? SimulatorSetError.deviceCreationFailed)
        }
      }
    }
  }

  private static func cloneDevice(on deviceSet: SimDeviceSet, device: SimDevice, toDeviceSet destinationSet: SimDeviceSet, queue: DispatchQueue) async throws -> SimDevice {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SimDevice, Error>) in
      deviceSet.cloneDeviceAsync(device, name: device.name, to: destinationSet, completionQueue: queue) { error, created in
        if let created {
          continuation.resume(returning: created)
        } else {
          continuation.resume(throwing: error ?? SimulatorSetError.deviceCloneFailed)
        }
      }
    }
  }

  private static func deleteDevice(_ device: SimDevice, on deviceSet: SimDeviceSet, queue: DispatchQueue) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      deviceSet.deleteDeviceAsync(device, completionQueue: queue) { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume(returning: ())
        }
      }
    }
  }

  private static func confirmSimulatorUDID(_ udid: String, isRemovedFromSet deviceSet: SimDeviceSet) async throws {
    // Deleting the device from the set can still leave it around for a few seconds.
    let timeout = ControlCoreGlobalConfiguration.regularTimeout
    let deadline = Date().addingTimeInterval(timeout)
    let pollIntervalNs = UInt64(0.1 * Double(NSEC_PER_SEC))
    while true {
      try Task.checkCancellation()
      let udidsInSet = (deviceSet.availableDevices ?? []).compactMap { ($0 as? SimDevice)?.udid.uuidString }
      if !udidsInSet.contains(udid) {
        return
      }
      if Date() >= deadline {
        throw SimulatorDeletionError.removalTimedOut
      }
      try await Task.sleep(nanoseconds: pollIntervalNs)
    }
  }
}

public enum SimulatorDeletionError: Error, LocalizedError {
  case removalTimedOut

  public var errorDescription: String? {
    switch self {
    case .removalTimedOut:
      return "Timed out waiting for Simulator to be removed from set"
    }
  }
}
