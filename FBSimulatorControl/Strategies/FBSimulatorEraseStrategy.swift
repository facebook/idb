// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

@objc(FBSimulatorEraseStrategy)
public final class FBSimulatorEraseStrategy: NSObject {

  // MARK: - Public

  @objc
  public class func erase(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    return unsafeBitCast(FBSimulatorShutdownStrategy.shutdown(simulator), to: FBFuture<AnyObject>.self)
      .onQueue(
        simulator.workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          return unsafeBitCast(self.eraseContentsAndSettings(simulator), to: FBFuture<AnyObject>.self)
        }) as! FBFuture<NSNull>
  }

  // MARK: - Private

  private class func eraseContentsAndSettings(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    let logger = simulator.logger
    let description = "\(simulator)"
    logger?.log("Erasing \(description)")
    let future = FBMutableFuture<NSNull>()
    simulator.device.eraseContentsAndSettingsAsync(withCompletionQueue: simulator.workQueue) { error in
      if let error {
        future.resolveWithError(error)
      } else {
        logger?.log("Erased \(description)")
        future.resolve(withResult: NSNull())
      }
    }
    return unsafeBitCast(future, to: FBFuture<NSNull>.self)
  }
}
