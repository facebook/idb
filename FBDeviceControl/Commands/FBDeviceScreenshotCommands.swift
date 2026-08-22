/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let ScreenShotDataKey = "ScreenShotData"

/// The ways a device screenshot can fail, as data rather than assembled strings.
public enum FBDeviceScreenshotError: Error {
  case deviceNil
  case notImageData(response: String, key: String)
}

extension FBDeviceScreenshotError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .deviceNil:
      return "Device is nil"
    case let .notImageData(response, key):
      return "\(response) is not an NSData for \(key)"
    }
  }
}

public class FBDeviceScreenshotCommands: NSObject {
  private weak var device: FBDevice?

  // MARK: - Initializers

  public class func commands(with device: FBDevice) -> FBDeviceScreenshotCommands {
    FBDeviceScreenshotCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
    super.init()
  }

  // MARK: - Async

  fileprivate func takeScreenshotAsync(_ format: FBScreenshotFormat) async throws -> Data {
    guard let device else {
      throw FBDeviceScreenshotError.deviceNil
    }
    return try await withFBFutureContext(device.startDeviceLinkService("com.apple.mobile.screenshotr")) { client in
      let response = try await bridgeFBFuture(client.processMessage(["MessageType": "ScreenShotRequest"]))
      guard let screenshotData = response[ScreenShotDataKey] as? NSData else {
        throw FBDeviceScreenshotError.notImageData(response: String(describing: response), key: ScreenShotDataKey)
      }
      return screenshotData as Data
    }
  }
}

// MARK: - FBDevice+ScreenshotCommands

extension FBDevice: ScreenshotCommands {

  public func takeScreenshot(format: FBScreenshotFormat) async throws -> Data {
    try await screenshotCommands().takeScreenshotAsync(format)
  }
}
