/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

public final class SimulatorSet: FBiOSTargetSet {

  public let configuration: SimulatorControlConfiguration
  public let deviceSet: SimDeviceSet
  public weak var delegate: (any FBiOSTargetSetDelegate)?
  public let logger: any ControlCoreLogger
  public let workQueue: DispatchQueue
  public let asyncQueue: DispatchQueue

  private var _allSimulators: [Simulator]
  // Guards _allSimulators: the allSimulators getter re-inflates and swaps the
  // backing array, and is called from arbitrary threads (lookups at companion
  // startup, delegate notification, description). Unsynchronized, the swap
  // races iteration in concurrent callers.
  private let simulatorsLock = NSLock()
  private lazy var inflationStrategy = SimulatorInflationStrategy.strategy(for: self)

  // Held only so that the strategy's notifier stays registered for the lifetime of the set; it is never read.
  private var notificationUpdateStrategy: SimulatorNotificationUpdateStrategy?

  /// - Parameter logger: nil means `ControlCoreGlobalConfiguration.defaultLogger`, which is
  ///   os_log-only unless the `FBCONTROLCORE_LOGGING`/`FBCONTROLCORE_DEBUG_LOGGING` environment
  ///   variables are set — see its documentation. The resolved logger is stored non-optionally.
  public class func set(withConfiguration configuration: SimulatorControlConfiguration, deviceSet: SimDeviceSet, delegate: (any FBiOSTargetSetDelegate)?, logger: (any ControlCoreLogger)?) throws -> SimulatorSet {
    let resolvedLogger = logger ?? ControlCoreGlobalConfiguration.defaultLogger
    try SimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(resolvedLogger)
    return SimulatorSet(configuration: configuration, deviceSet: deviceSet, delegate: delegate, logger: resolvedLogger)
  }

  private init(configuration: SimulatorControlConfiguration, deviceSet: SimDeviceSet, delegate: (any FBiOSTargetSetDelegate)?, logger: any ControlCoreLogger) {
    self.configuration = configuration
    self.deviceSet = deviceSet
    self.delegate = delegate
    self.logger = logger
    self.workQueue = DispatchQueue.main
    self.asyncQueue = DispatchQueue.global(qos: .default)
    self._allSimulators = []
    self.notificationUpdateStrategy = SimulatorNotificationUpdateStrategy.strategy(with: self)
  }

  // MARK: - Querying

  public func target(withUDID udid: String) -> (any FBiOSTargetInfo)? {
    return simulator(withUDID: udid)
  }

  public func simulator(withUDID udid: String) -> Simulator? {
    return allSimulators.filter { FBiOSTargetPredicateForUDID(udid).evaluate(with: $0) }.first
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
      try await SimulatorShutdownStrategy.shutdown(simulator)
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
    try await SimulatorShutdownStrategy.shutdown(simulator)
  }

  public func delete(_ simulator: Simulator) async throws {
    try await SimulatorDeletionStrategy.delete(simulator)
  }

  func shutdownAll(_ simulators: [Simulator]) async throws {
    try await SimulatorShutdownStrategy.shutdownAll(simulators)
  }

  public func deleteAll(_ simulators: [Simulator]) async throws {
    try await SimulatorDeletionStrategy.deleteAll(simulators)
  }

  func shutdownAll() async throws {
    try await SimulatorShutdownStrategy.shutdownAll(allSimulators)
  }

  public func deleteAll() async throws {
    try await deleteAll(allSimulators)
  }

  public var description: String {
    CollectionInformation.oneLineDescription(from: allSimulators)
  }

  public var allTargetInfos: [any FBiOSTargetInfo] {
    allSimulators
  }

  public var allSimulators: [Simulator] {
    simulatorsLock.lock()
    defer { simulatorsLock.unlock() }
    _allSimulators = inflationStrategy.inflate(
      fromDevices: deviceSet.availableDevices,
      exitingSimulators: _allSimulators
    )
    .sorted { ($0 as Simulator).compare($1 as any FBiOSTarget) == .orderedAscending }
    return _allSimulators
  }

  private class func keySimulatorsByUDID(_ simulators: [Simulator]) -> [String: Simulator] {
    var dictionary: [String: Simulator] = [:]
    for simulator in simulators {
      dictionary[simulator.udid] = simulator
    }
    return dictionary
  }

  private func fetchNewlyMadeSimulatorOrThrow(_ device: SimDevice) throws -> Simulator {
    guard let simulator = SimulatorSet.keySimulatorsByUDID(allSimulators)[device.udid.uuidString] else {
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
}
