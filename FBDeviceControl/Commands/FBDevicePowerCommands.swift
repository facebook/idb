// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import Foundation

@objc(FBDevicePowerCommands)
public class FBDevicePowerCommands: NSObject, FBPowerCommands {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBPowerCommands

  public func shutdown() -> FBFuture<NSNull> {
    return sendRelayCommand("Shutdown")
  }

  public func reboot() -> FBFuture<NSNull> {
    return sendRelayCommand("Restart")
  }

  // MARK: - Private

  private func sendRelayCommand(_ request: String) -> FBFuture<NSNull> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (device
      .startService("com.apple.mobile.diagnostics_relay")
      .onQueue(
        device.workQueue,
        pop: { connection -> FBFuture<AnyObject> in
          do {
            guard let result = try connection.sendAndReceiveMessage(["Request": request]) as? NSDictionary else {
              return FBControlCoreError.describe("Unexpected response").failFuture()
            }
            if (result["Status"] as? String) != "Success" {
              return FBControlCoreError.describe("Not successful \(result)").failFuture()
            }
            return FBFuture(result: NSNull() as AnyObject)
          } catch {
            return FBFuture(error: error)
          }
        })) as! FBFuture<NSNull>
  }
}
