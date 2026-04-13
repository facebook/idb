/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorShutdownStrategy)
public final class FBSimulatorShutdownStrategy: NSObject {

  // MARK: - Public Methods

  @objc
  public class func shutdown(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    let logger = simulator.logger
    logger?.debug().log("Starting Safe Shutdown of \(simulator.udid)")

    // If the device is in a strange state, we should bail now
    if simulator.state == .unknown {
      return FBSimulatorError.describe("Failed to prepare simulator for usage as it is in an unknown state")
        .failFuture() as! FBFuture<NSNull>
    }

    // Calling shutdown when already shutdown should be avoided (if detected).
    if simulator.state == .shutdown {
      logger?.debug().log("Shutdown of \(simulator.udid) succeeded as it is already shutdown")
      return FBFuture<NSNull>.empty()
    }

    // Xcode 7 has a 'Creating' step that we should wait on before confirming the simulator is ready.
    if simulator.state == .creating {
      return transitionCreatingToShutdown(simulator)
    }

    return shutdownSimulator(simulator)
  }

  @objc
  public class func shutdownAll(_ simulators: [FBSimulator]) -> FBFuture<NSNull> {
    let futures = simulators.map { unsafeBitCast(shutdown($0), to: FBFuture<AnyObject>.self) }
    return FBFuture<AnyObject>.combine(futures).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  // MARK: - Private

  private static let shutdownWhenShuttingDownErrorCode: Int = 164

  private class func shutdownSimulator(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    let future = FBMutableFuture<NSNull>()
    let logger = simulator.logger
    let errorCode = shutdownWhenShuttingDownErrorCode

    logger?.debug().log("Shutting down Simulator \(simulator.udid)")
    simulator.device.shutdownAsync(withCompletionQueue: simulator.asyncQueue) { error in
      if let error = error as NSError?, error.code == errorCode {
        logger?.log("Got Error Code \(error.code) from shutdown, simulator is already shutdown")
        future.resolve(withResult: NSNull())
      } else if let error {
        future.resolveWithError(error)
      } else {
        future.resolve(withResult: NSNull())
      }
    }
    return
      future
      .onQueue(
        simulator.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          return unsafeBitCast(FBiOSTargetResolveState(simulator, .shutdown), to: FBFuture<AnyObject>.self)
        }) as! FBFuture<NSNull>
  }

  private class func transitionCreatingToShutdown(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    return
      (unsafeBitCast(FBiOSTargetResolveState(simulator, .shutdown), to: FBFuture<AnyObject>.self)
      .timeout(
        FBControlCoreGlobalConfiguration.regularTimeout,
        waitingFor: "Simulator to resolve state \(FBiOSTargetStateString.shutdown)"
      )
      .onQueue(
        simulator.workQueue,
        chain: { future -> FBFuture<AnyObject> in
          if future.result != nil {
            return FBFuture(result: NSNull())
          }
          return unsafeBitCast(FBSimulatorShutdownStrategy.eraseSimulator(simulator), to: FBFuture<AnyObject>.self)
        })) as! FBFuture<NSNull>
  }

  private class func eraseSimulator(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    let future = FBMutableFuture<NSNull>()
    let logger = simulator.logger

    logger?.debug().log("Erasing Simulator \(simulator.udid)")
    simulator.device.eraseContentsAndSettingsAsync(withCompletionQueue: simulator.asyncQueue) { error in
      if let error {
        future.resolveWithError(error)
      } else {
        future.resolve(withResult: NSNull())
      }
    }

    return
      future
      .onQueue(
        simulator.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          return unsafeBitCast(FBiOSTargetResolveState(simulator, .shutdown), to: FBFuture<AnyObject>.self)
            .timeout(
              FBControlCoreGlobalConfiguration.regularTimeout,
              waitingFor: "Timed out waiting for Simulator to transition from Creating -> Shutdown")
        }) as! FBFuture<NSNull>
  }
}
