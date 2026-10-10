/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

public final class SimulatorSet: TargetSet {

  public let configuration: SimulatorControlConfiguration
  public let deviceSet: SimDeviceSet
  public weak var delegate: (any TargetSetDelegate)?
  public let logger: any ControlCoreLogger
  public let workQueue: DispatchQueue
  public let asyncQueue: DispatchQueue

  // Keeps every `Simulator` the set has vended alive for the set's lifetime. Guarded by
  // `vendedLock`, as lookups arrive from arbitrary threads.
  private var vended: [String: Simulator] = [:]
  private let vendedLock = NSLock()

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
    guard let uuid = NSUUID(uuidString: udid) else {
      return nil
    }
    // `vended` is keyed by the canonical form, which the caller's spelling need not match.
    let key = uuid.uuidString
    guard let item = deviceSet.devicesByUDID?[uuid] else {
      forget { $0 == key }
      return nil
    }
    let device = Self.simDevice(item)
    guard device.available else {
      forget { $0 == key }
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

  public var allTargetInfos: [any TargetInfo] {
    allSimulators
  }

  public var allSimulators: [Simulator] {
    let devices = (deviceSet.availableDevices ?? []).map(Self.simDevice)
    let available = Set(devices.map { $0.udid.uuidString })
    forget { !available.contains($0) }
    return devices.map(vend).sorted { ($0 as Simulator).compare($1 as any Target) == .orderedAscending }
  }

  // Unchecked because unit tests stand in doubles that respond to `SimDevice`'s selectors without
  // being instances of it, which a checked cast rejects. A real `SimDeviceSet` vends only `SimDevice`s.
  private static func simDevice(_ item: Any) -> SimDevice {
    unsafeBitCast(item as AnyObject, to: SimDevice.self)
  }

  private func vend(_ device: SimDevice) -> Simulator {
    let simulator = Simulator.fromSimDevice(device, set: self)
    vendedLock.lock()
    defer { vendedLock.unlock() }
    vended[simulator.udid] = simulator
    return simulator
  }

  private func forget(where departed: (String) -> Bool) {
    vendedLock.lock()
    defer { vendedLock.unlock() }
    vended = vended.filter { !departed($0.key) }
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
}
