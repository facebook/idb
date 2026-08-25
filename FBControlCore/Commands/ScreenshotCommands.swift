/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A screenshot format, matching the wire names accepted over the companion's API.
public struct FBScreenshotFormat: RawRepresentable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let jpeg = FBScreenshotFormat(rawValue: "jpeg")
  public static let png = FBScreenshotFormat(rawValue: "png")
}

public protocol ScreenshotCommands: AnyObject {

  func takeScreenshot(format: FBScreenshotFormat) async throws -> Data
}
