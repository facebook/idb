/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

public final class FBSimulatorSet: FBiOSTargetSet {

  // MARK: - Properties

  public let configuration: FBSimulatorControlConfiguration
  public let deviceSet: SimDeviceSet
  public weak var delegate: (any FBiOSTargetSetDelegate)?
  public let logger: any FBControlCoreLogger
  public let workQueue: DispatchQueue
  public let asyncQueue: DispatchQueue

  private var _allSimulators: [FBSimulator]
  // Guards _allSimulators: the allSimulators getter re-inflates and swaps the
  // backing array, and is called from arbitrary threads (lookups at companion
  // startup, delegate notification, description). Unsynchronized, the swap
  // races iteration in concurrent callers.
  private let simulatorsLock = NSLock()
  private lazy var inflationStrategy = FBSimulatorInflationStrategy.strategy(for: self)

  // Held only so that the strategy's notifier stays registered for the lifetime of the set; it is never read.
  private var notificationUpdateStrategy: FBSimulatorNotificationUpdateStrategy?

  // MARK: - Initializers

  /// - Parameter logger: nil means `FBControlCoreGlobalConfiguration.defaultLogger`, which is
  ///   os_log-only unless the `FBCONTROLCORE_LOGGING`/`FBCONTROLCORE_DEBUG_LOGGING` environment
  ///   variables are set — see its documentation. The resolved logger is stored non-optionally.
  public class func set(withConfiguration configuration: FBSimulatorControlConfiguration, deviceSet: SimDeviceSet, delegate: (any FBiOSTargetSetDelegate)?, logger: (any FBControlCoreLogger)?) throws -> FBSimulatorSet {
    let resolvedLogger = logger ?? FBControlCoreGlobalConfiguration.defaultLogger
    try FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(resolvedLogger)
    return FBSimulatorSet(configuration: configuration, deviceSet: deviceSet, delegate: delegate, logger: resolvedLogger)
  }

  private init(configuration: FBSimulatorControlConfiguration, deviceSet: SimDeviceSet, delegate: (any FBiOSTargetSetDelegate)?, logger: any FBControlCoreLogger) {
    self.configuration = configuration
    self.deviceSet = deviceSet
    self.delegate = delegate
    self.logger = logger
    self.workQueue = DispatchQueue.main
    self.asyncQueue = DispatchQueue.global(qos: .default)
    self._allSimulators = []
    self.notificationUpdateStrategy = FBSimulatorNotificationUpdateStrategy.strategy(with: self)
  }

  // MARK: - Querying

  public func target(withUDID udid: String) -> (any FBiOSTargetInfo)? {
    return simulator(withUDID: udid)
  }

  public func simulator(withUDID udid: String) -> FBSimulator? {
    return allSimulators.filter { FBiOSTargetPredicateForUDID(udid).evaluate(with: $0) }.first
  }

  // MARK: - Creation

  public func createSimulator(with configuration: FBSimulatorConfiguration) async throws -> FBSimulator {
    let model: String = configuration.device.model.rawValue

    let deviceType: SimDeviceType
    let runtime: SimRuntime
    do {
      deviceType = try configuration.obtainDeviceType()
      runtime = try configuration.obtainRuntime()
    } catch {
      throw FBSimulatorSetError.deviceTypeOrRuntimeUnavailable(configuration: "\(configuration)", reason: error.localizedDescription)
    }

    logger.debug().log("Creating device with Type \(deviceType) Runtime \(runtime)")
    let device = try await Self.createDevice(on: deviceSet, type: deviceType, runtime: runtime, name: model, queue: asyncQueue)
    let simulator = try fetchNewlyMadeSimulatorOrThrow(device)
    simulator.configuration = configuration
    logger.debug().log("Created Simulator \(simulator.udid) for configuration \(configuration)")
    do {
      try await FBSimulatorShutdownStrategy.shutdown(simulator)
    } catch {
      throw FBSimulatorSetError.shutdownAfterCreateFailed(reason: error.localizedDescription)
    }
    return simulator
  }

  public func cloneSimulator(_ simulator: FBSimulator, toDeviceSet destinationSet: FBSimulatorSet) async throws -> FBSimulator {
    let device = try await Self.cloneDevice(on: deviceSet, device: simulator.device, toDeviceSet: destinationSet.deviceSet, queue: asyncQueue)
    return try destinationSet.fetchNewlyMadeSimulatorOrThrow(device)
  }

  func configurationsForAbsentDefaultSimulators() throws -> [FBSimulatorConfiguration] {
    let existingConfigurations = Set(allSimulators.compactMap { $0.configuration })
    var absentConfigurations = Set(try FBSimulatorConfiguration.allAvailableDefaultConfigrations(withLogger: logger))
    absentConfigurations.subtract(existingConfigurations)
    return Array(absentConfigurations)
  }

  // MARK: - Destructive Methods

  public func shutdown(_ simulator: FBSimulator) async throws {
    try await FBSimulatorShutdownStrategy.shutdown(simulator)
  }

  public func delete(_ simulator: FBSimulator) async throws {
    try await FBSimulatorDeletionStrategy.delete(simulator)
  }

  func shutdownAll(_ simulators: [FBSimulator]) async throws {
    try await FBSimulatorShutdownStrategy.shutdownAll(simulators)
  }

  public func deleteAll(_ simulators: [FBSimulator]) async throws {
    try await FBSimulatorDeletionStrategy.deleteAll(simulators)
  }

  func shutdownAll() async throws {
    try await FBSimulatorShutdownStrategy.shutdownAll(allSimulators)
  }

  public func deleteAll() async throws {
    try await deleteAll(allSimulators)
  }

  // MARK: - Description

  public var description: String {
    FBCollectionInformation.oneLineDescription(from: allSimulators)
  }

  // MARK: - FBiOSTargetSet

  public var allTargetInfos: [any FBiOSTargetInfo] {
    allSimulators
  }

  // MARK: - Public Properties

  public var allSimulators: [FBSimulator] {
    simulatorsLock.lock()
    defer { simulatorsLock.unlock() }
    _allSimulators = inflationStrategy.inflate(
      fromDevices: deviceSet.availableDevices,
      exitingSimulators: _allSimulators
    )
    .sorted { ($0 as FBSimulator).compare($1 as any FBiOSTarget) == .orderedAscending }
    return _allSimulators
  }

  // MARK: - Private Methods

  private class func keySimulatorsByUDID(_ simulators: [FBSimulator]) -> [String: FBSimulator] {
    var dictionary: [String: FBSimulator] = [:]
    for simulator in simulators {
      dictionary[simulator.udid] = simulator
    }
    return dictionary
  }

  private func fetchNewlyMadeSimulatorOrThrow(_ device: SimDevice) throws -> FBSimulator {
    guard let simulator = FBSimulatorSet.keySimulatorsByUDID(allSimulators)[device.udid.uuidString] else {
      throw FBSimulatorSetError.simulatorNotInflated(udid: device.udid.uuidString)
    }
    return simulator
  }

  private static func createDevice(on deviceSet: SimDeviceSet, type deviceType: SimDeviceType, runtime: SimRuntime, name: String, queue: DispatchQueue) async throws -> SimDevice {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SimDevice, Error>) in
      deviceSet.createDeviceAsync(withType: deviceType, runtime: runtime, name: name, completionQueue: queue) { error, device in
        if let device {
          continuation.resume(returning: device)
        } else {
          continuation.resume(throwing: error ?? FBSimulatorSetError.deviceCreationFailed)
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
          continuation.resume(throwing: error ?? FBSimulatorSetError.deviceCloneFailed)
        }
      }
    }
  }
}
