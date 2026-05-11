/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorSet)
public final class FBSimulatorSet: NSObject, FBiOSTargetSet {

  // MARK: - Properties

  @objc public let configuration: FBSimulatorControlConfiguration
  @objc public let deviceSet: SimDeviceSet
  @objc public weak var delegate: (any FBiOSTargetSetDelegate)?
  @objc public let logger: (any FBControlCoreLogger)?
  @objc public let reporter: (any FBEventReporter)?
  @objc public let workQueue: DispatchQueue
  @objc public let asyncQueue: DispatchQueue

  private var _allSimulators: [FBSimulator]
  private var inflationStrategy: FBSimulatorInflationStrategy!
  private var notificationUpdateStrategy: FBSimulatorNotificationUpdateStrategy!

  // MARK: - Initializers

  @objc(setWithConfiguration:deviceSet:delegate:logger:reporter:)
  public class func set(withConfiguration configuration: FBSimulatorControlConfiguration, deviceSet: SimDeviceSet, delegate: (any FBiOSTargetSetDelegate)?, logger: (any FBControlCoreLogger)?, reporter: (any FBEventReporter)?) -> FBSimulatorSet {
    FBSimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworksOrAbort()
    return FBSimulatorSet(configuration: configuration, deviceSet: deviceSet, delegate: delegate, logger: logger, reporter: reporter)
  }

  private init(configuration: FBSimulatorControlConfiguration, deviceSet: SimDeviceSet, delegate: (any FBiOSTargetSetDelegate)?, logger: (any FBControlCoreLogger)?, reporter: (any FBEventReporter)?) {
    self.configuration = configuration
    self.deviceSet = deviceSet
    self.delegate = delegate
    self.logger = logger
    self.reporter = reporter
    self.workQueue = DispatchQueue.main
    self.asyncQueue = DispatchQueue.global(qos: .default)
    self._allSimulators = []
    super.init()
    self.inflationStrategy = FBSimulatorInflationStrategy.strategy(for: self)
    self.notificationUpdateStrategy = FBSimulatorNotificationUpdateStrategy.strategy(with: self)
  }

  // MARK: - Querying

  @objc
  public func target(withUDID udid: String) -> (any FBiOSTargetInfo)? {
    return simulator(withUDID: udid)
  }

  @objc(simulatorWithUDID:)
  public func simulator(withUDID udid: String) -> FBSimulator? {
    return allSimulators.filter { FBiOSTargetPredicateForUDID(udid).evaluate(with: $0) }.first
  }

  // MARK: - Creation

  @objc(createSimulatorWithConfiguration:)
  public func createSimulator(with configuration: FBSimulatorConfiguration) -> FBFuture<FBSimulator> {
    fbFutureFromAsync { [self] in
      try await createSimulatorAsync(with: configuration)
    }
  }

  @objc(cloneSimulator:toDeviceSet:)
  public func cloneSimulator(_ simulator: FBSimulator, toDeviceSet destinationSet: FBSimulatorSet) -> FBFuture<FBSimulator> {
    fbFutureFromAsync { [self] in
      try await cloneSimulatorAsync(simulator, toDeviceSet: destinationSet)
    }
  }

  // MARK: - Async

  func createSimulatorAsync(with configuration: FBSimulatorConfiguration) async throws -> FBSimulator {
    let model: String = configuration.device.model.rawValue

    // See if we meet the runtime requirements to create a Simulator with the given configuration.
    let deviceType: SimDeviceType
    let runtime: SimRuntime
    do {
      deviceType = try configuration.obtainDeviceType()
      runtime = try configuration.obtainRuntime()
    } catch {
      throw FBSimulatorError.describe("Could not obtain DeviceType or SimRuntime for Configuration \(configuration)").caused(by: error as NSError).build()
    }

    // First, create the device.
    logger?.debug().log("Creating device with Type \(deviceType) Runtime \(runtime)")
    let device = try await Self.createDeviceAsync(on: deviceSet, type: deviceType, runtime: runtime, name: model, queue: asyncQueue)
    let simulator = try fetchNewlyMadeSimulatorOrThrow(device)
    simulator.configuration = configuration
    logger?.debug().log("Created Simulator \(simulator.udid) for configuration \(configuration)")
    do {
      try await FBSimulatorShutdownStrategy.shutdownAsync(simulator)
    } catch {
      throw FBSimulatorError.describe("Could not get newly-created simulator into a shutdown state").caused(by: error as NSError).build()
    }
    return simulator
  }

  func cloneSimulatorAsync(_ simulator: FBSimulator, toDeviceSet destinationSet: FBSimulatorSet) async throws -> FBSimulator {
    let device = try await Self.cloneDeviceAsync(on: deviceSet, device: simulator.device, toDeviceSet: destinationSet.deviceSet, queue: asyncQueue)
    return try destinationSet.fetchNewlyMadeSimulatorOrThrow(device)
  }

  @objc
  public func configurationsForAbsentDefaultSimulators() -> [FBSimulatorConfiguration] {
    let existingConfigurations = Set(allSimulators.compactMap { $0.configuration })
    var absentConfigurations = Set(FBSimulatorConfiguration.allAvailableDefaultConfigrations(withLogger: logger))
    absentConfigurations.subtract(existingConfigurations)
    return Array(absentConfigurations)
  }

  // MARK: - Destructive Methods

  @objc(shutdown:)
  public func shutdown(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    return FBSimulatorShutdownStrategy.shutdown(simulator)
  }

  @objc(erase:)
  public func erase(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    return FBSimulatorEraseStrategy.erase(simulator)
  }

  @objc(delete:)
  public func delete(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    return FBSimulatorDeletionStrategy.delete(simulator)
  }

  @objc(shutdownAll:)
  public func shutdownAll(_ simulators: [FBSimulator]) -> FBFuture<NSNull> {
    return FBSimulatorShutdownStrategy.shutdownAll(simulators)
  }

  @objc(deleteAll:)
  public func deleteAll(_ simulators: [FBSimulator]) -> FBFuture<NSNull> {
    return FBSimulatorDeletionStrategy.deleteAll(simulators)
  }

  @objc
  public func shutdownAll() -> FBFuture<NSNull> {
    return FBSimulatorShutdownStrategy.shutdownAll(allSimulators)
  }

  @objc
  public func deleteAll() -> FBFuture<NSNull> {
    return deleteAll(allSimulators)
  }

  // MARK: - NSObject

  public override var description: String {
    return FBCollectionInformation.oneLineDescription(from: allSimulators)
  }

  // MARK: - FBiOSTargetSet

  @objc
  public var allTargetInfos: [any FBiOSTargetInfo] {
    return allSimulators
  }

  // MARK: - Public Properties

  @objc
  public var allSimulators: [FBSimulator] {
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
      throw FBSimulatorError.describe("Expected simulator with UDID \(device.udid.uuidString) to be inflated").build()
    }
    return simulator
  }

  private static func createDeviceAsync(on deviceSet: SimDeviceSet, type deviceType: SimDeviceType, runtime: SimRuntime, name: String, queue: DispatchQueue) async throws -> SimDevice {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SimDevice, Error>) in
      deviceSet.createDeviceAsync(withType: deviceType, runtime: runtime, name: name, completionQueue: queue) { error, device in
        if let device {
          continuation.resume(returning: device)
        } else {
          continuation.resume(throwing: error ?? FBSimulatorError.describe("Failed to create device with no error").build())
        }
      }
    }
  }

  private static func cloneDeviceAsync(on deviceSet: SimDeviceSet, device: SimDevice, toDeviceSet destinationSet: SimDeviceSet, queue: DispatchQueue) async throws -> SimDevice {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SimDevice, Error>) in
      deviceSet.cloneDeviceAsync(device, name: device.name, to: destinationSet, completionQueue: queue) { error, created in
        if let created {
          continuation.resume(returning: created)
        } else {
          continuation.resume(throwing: error ?? FBSimulatorError.describe("Failed to clone device with no error").build())
        }
      }
    }
  }
}
