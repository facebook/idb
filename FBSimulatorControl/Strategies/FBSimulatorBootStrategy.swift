/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
import Foundation

@objc(FBSimulatorBootStrategy)
public final class FBSimulatorBootStrategy: NSObject {

  // MARK: - Public Methods

  @objc(boot:withConfiguration:)
  public class func boot(_ simulator: FBSimulator, with configuration: FBSimulatorBootConfiguration) -> FBFuture<NSNull> {
    // Return early depending on Simulator state.
    if simulator.state == .booted {
      return FBFuture<NSNull>.empty()
    }
    if simulator.state != .shutdown {
      return FBSimulatorError.describe("Cannot Boot Simulator when in \(simulator.stateString) state")
        .failFuture() as! FBFuture<NSNull>
    }

    // Boot via CoreSimulator.
    return
      (unsafeBitCast(performSimulatorBoot(simulator, with: configuration), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          return unsafeBitCast(verifySimulatorIsBooted(simulator, with: configuration), to: FBFuture<AnyObject>.self)
        })) as! FBFuture<NSNull>
  }

  // MARK: - Private

  private class func verifySimulatorIsBooted(_ simulator: FBSimulator, with configuration: FBSimulatorBootConfiguration) -> FBFuture<NSNull> {
    // Return early if the option to verify boot is not set.
    if !configuration.options.contains(.verifyUsable) {
      return FBFuture<NSNull>.empty()
    }

    // Otherwise actually perform the boot verification.
    return FBSimulatorBootVerificationStrategy.verifySimulatorIsBooted(simulator)
  }

  private class func performSimulatorBoot(_ simulator: FBSimulator, with configuration: FBSimulatorBootConfiguration) -> FBFuture<NSNull> {
    // "Persisting" means that the booted Simulator should live beyond the lifecycle of the process that calls the boot API.
    // The inverse of this is `FBSimulatorBootOptionsTieToProcessLifecycle`, which means that the Simulator should shutdown when the process that calls the boot API dies.
    let persist = !configuration.options.contains(.tieToProcessLifecycle)
    let options: [String: Any] = [
      "persist": persist,
      "env": configuration.environment,
    ]

    let future = FBMutableFuture<NSNull>()
    simulator.device.bootAsync(withOptions: options, completionQueue: simulator.workQueue) { error in
      if let error = error {
        future.resolveWithError(error)
      } else {
        future.resolve(withResult: NSNull())
      }
    }
    return unsafeBitCast(future, to: FBFuture<NSNull>.self)
  }
}
