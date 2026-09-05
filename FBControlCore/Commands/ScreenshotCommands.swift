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

  /// Captures the screen as `configuration` describes.
  func takeScreenshot(configuration: FBScreenshotConfiguration) async throws -> FBScreenshotResult
}

public extension ScreenshotCommands {

  /// Captures the whole screen at its native resolution.
  func takeScreenshot(format: FBScreenshotFormat) async throws -> Data {
    let configuration = FBScreenshotConfiguration(encoding: try FBScreenshotEncoding(format: format))
    return try await takeScreenshot(configuration: configuration).imageData
  }
}

public enum FBScreenshotFormatError: Error, Hashable {
  case unrecognizedFormat(String)
}

extension FBScreenshotFormatError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .unrecognizedFormat(format):
      return "\(format) is not a recognized screenshot format"
    }
  }
}

public extension FBScreenshotEncoding {

  /// `FBScreenshotFormat` carries no encoder options, so JPEG gets `defaultJPEGQuality`.
  init(format: FBScreenshotFormat) throws {
    switch format {
    case .png:
      self = .png
    case .jpeg:
      self = .jpeg(quality: Self.defaultJPEGQuality)
    default:
      throw FBScreenshotFormatError.unrecognizedFormat(format.rawValue)
    }
  }
}
