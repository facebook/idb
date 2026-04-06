// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import Foundation

private let ScreenShotDataKey = "ScreenShotData"

@objc(FBDeviceScreenshotCommands)
public class FBDeviceScreenshotCommands: NSObject, FBScreenshotCommands {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with target: any FBiOSTarget) -> Self {
    return self.init(device: target as! FBDevice)
  }

  required init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - FBScreenshotCommands

  public func takeScreenshot(_ format: FBScreenshotFormat) -> FBFuture<NSData> {
    guard let device = device else {
      return FBFuture(error: FBDeviceControlError().describe("Device is nil").build())
    }
    return
      (device
      .startDeviceLinkService("com.apple.mobile.screenshotr")
      .onQueue(
        device.workQueue,
        pop: { client -> FBFuture<AnyObject> in
          return client.processMessage(["MessageType": "ScreenShotRequest"]) as! FBFuture<AnyObject>
        }
      )
      .onQueue(
        device.workQueue,
        fmap: { response -> FBFuture<AnyObject> in
          guard let dict = response as? NSDictionary,
            let screenshotData = dict[ScreenShotDataKey] as? NSData
          else {
            return FBDeviceControlError()
              .describe("\(String(describing: response)) is not an NSData for \(ScreenShotDataKey)")
              .failFuture()
          }
          return FBFuture(result: screenshotData)
        })) as! FBFuture<NSData>
  }
}
