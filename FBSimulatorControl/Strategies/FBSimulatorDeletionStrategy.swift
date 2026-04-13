// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import CoreSimulator
@preconcurrency import FBControlCore
@preconcurrency import Foundation

@objc(FBSimulatorDeletionStrategy)
public final class FBSimulatorDeletionStrategy: NSObject {

  // MARK: - Public Methods

  @objc
  public class func delete(_ simulator: FBSimulator) -> FBFuture<NSNull> {
    // Get the Log Directory ahead of time as the Simulator will disappear on deletion.
    let coreSimulatorLogsDirectory = simulator.coreSimulatorLogsDirectory
    let workQueue = simulator.workQueue
    let udid = simulator.udid
    let set = simulator.set

    // Kill the Simulators before deleting them.
    simulator.logger?.log("Killing Simulator, in preparation for deletion \(simulator)")
    return unsafeBitCast(FBSimulatorShutdownStrategy.shutdown(simulator), to: FBFuture<AnyObject>.self)
      .onQueue(
        workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          // Then follow through with the actual deletion of the Simulator, which will remove it from the set.
          simulator.logger?.log("Deleting Simulator \(simulator)")
          return FBSimulatorDeletionStrategy.onDeviceSet(simulator.set.deviceSet, performDeletionOfDevice: simulator.device, onQueue: simulator.asyncQueue)
        }
      )
      .onQueue(
        workQueue,
        fmap: { _ -> FBFuture<AnyObject> in
          simulator.logger?.log("Simulator \(udid) Deleted")

          // The Logfiles now need disposing of.
          if FileManager.default.fileExists(atPath: coreSimulatorLogsDirectory) {
            simulator.logger?.log("Deleting Simulator Log Directory at \(coreSimulatorLogsDirectory)")
            do {
              try FileManager.default.removeItem(atPath: coreSimulatorLogsDirectory)
              simulator.logger?.log("Deleted Simulator Log Directory at \(coreSimulatorLogsDirectory)")
            } catch {
              simulator.logger?.error().log("Failed to delete Simulator Log Directory \(coreSimulatorLogsDirectory): \(error)")
            }
          }

          simulator.logger?.log("Confirming \(udid) has been removed from set")
          return unsafeBitCast(
            FBSimulatorDeletionStrategy.confirmSimulatorUDID(udid, isRemovedFromSet: set),
            to: FBFuture<AnyObject>.self)
        }
      )
      .onQueue(
        workQueue,
        doOnResolved: { _ in
          simulator.logger?.log("\(udid) has been removed from set")
        }) as! FBFuture<NSNull>
  }

  @objc
  public class func deleteAll(_ simulators: [FBSimulator]) -> FBFuture<NSNull> {
    let futures = simulators.map { unsafeBitCast(delete($0), to: FBFuture<AnyObject>.self) }
    return FBFuture<AnyObject>.combine(futures).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  // MARK: - Private

  private class func confirmSimulatorUDID(_ udid: String, isRemovedFromSet set: FBSimulatorSet) -> FBFuture<NSNull> {
    // Deleting the device from the set can still leave it around for a few seconds.
    return
      (FBFuture<AnyObject>.onQueue(
        set.workQueue,
        resolveWhen: {
          let simulatorsInSet = Set(set.allSimulators.map { $0.udid })
          return !simulatorsInSet.contains(udid)
        }
      )
      .timeout(
        FBControlCoreGlobalConfiguration.regularTimeout,
        waitingFor: "Simulator to be removed from set")) as! FBFuture<NSNull>
  }

  private class func onDeviceSet(_ deviceSet: SimDeviceSet, performDeletionOfDevice device: SimDevice, onQueue queue: DispatchQueue) -> FBFuture<AnyObject> {
    let udid = device.udid.uuidString
    let future = FBMutableFuture<AnyObject>()
    deviceSet.deleteDeviceAsync(device, completionQueue: queue) { error in
      if let error {
        future.resolveWithError(error)
      } else {
        future.resolve(withResult: udid as NSString)
      }
    }
    return future
  }
}
