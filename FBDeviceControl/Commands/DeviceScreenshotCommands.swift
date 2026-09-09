/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let ScreenShotDataKey = "ScreenShotData"

public enum FBDeviceScreenshotError: Error {
  case notImageData(response: String, key: String)
}

extension FBDeviceScreenshotError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .notImageData(response, key):
      return "\(response) is not an NSData for \(key)"
    }
  }
}

public final class FBDeviceScreenshotCommands {
  private weak var device: FBDevice?

  public class func commands(with device: FBDevice) -> FBDeviceScreenshotCommands {
    FBDeviceScreenshotCommands(device: device)
  }

  init(device: FBDevice) {
    self.device = device
  }

  // MARK: - Async

  fileprivate func takeScreenshot(configuration: FBScreenshotConfiguration) async throws -> FBScreenshotResult {
    guard let device else {
      throw FBDeviceNilError.deviceNil
    }
    let captured = try await capture(from: device)
    // A device hands back a finished image file rather than a framebuffer, so any crop or scale is
    // applied to the decoded image. A request for the whole screen as PNG -- which is what the
    // device already sent -- skips the round trip entirely.
    return try FBScreenshotRenderer.render(
      encoded: captured,
      configuration: configuration,
      screenScale: device.screenInfo.map { Double($0.scale) }
    )
  }

  private func capture(from device: FBDevice) async throws -> Data {
    try await device.withDeviceLinkClient("com.apple.mobile.screenshotr") { client in
      let response = try await client.processMessage(["MessageType": "ScreenShotRequest"])
      guard let screenshotData = response[ScreenShotDataKey] as? NSData else {
        throw FBDeviceScreenshotError.notImageData(response: String(describing: response), key: ScreenShotDataKey)
      }
      return screenshotData as Data
    }
  }
}

// MARK: - FBDevice+ScreenshotCommands

extension FBDevice: ScreenshotCommands {

  public func takeScreenshot(configuration: FBScreenshotConfiguration) async throws -> FBScreenshotResult {
    try await screenshot.takeScreenshot(configuration: configuration)
  }
}
