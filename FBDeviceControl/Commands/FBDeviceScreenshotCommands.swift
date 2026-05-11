/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

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

  // MARK: - FBScreenshotCommands (legacy FBFuture entry point)

  public func takeScreenshot(_ format: FBScreenshotFormat) -> FBFuture<NSData> {
    fbFutureFromAsync { [self] in
      try await takeScreenshotAsync(format) as NSData
    }
  }

  // MARK: - Async

  fileprivate func takeScreenshotAsync(_ format: FBScreenshotFormat) async throws -> Data {
    guard let device else {
      throw FBDeviceControlError().describe("Device is nil").build()
    }
    return try await withFBFutureContext(device.startDeviceLinkService("com.apple.mobile.screenshotr")) { client in
      let response = try await bridgeFBFuture(client.processMessage(["MessageType": "ScreenShotRequest"]))
      guard let screenshotData = response[ScreenShotDataKey] as? NSData else {
        throw FBDeviceControlError()
          .describe("\(String(describing: response)) is not an NSData for \(ScreenShotDataKey)")
          .build()
      }
      return screenshotData as Data
    }
  }
}

// MARK: - FBDevice+AsyncScreenshotCommands

extension FBDevice: AsyncScreenshotCommands {

  public func takeScreenshot(format: FBScreenshotFormat) async throws -> Data {
    try await screenshotCommands().takeScreenshotAsync(format)
  }
}
