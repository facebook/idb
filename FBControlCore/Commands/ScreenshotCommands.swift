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

public protocol ScreenshotCommands {

  /// Captures the screen as `configuration` describes.
  func take(configuration: FBScreenshotConfiguration) async throws -> FBScreenshotResult
}

public extension ScreenshotCommands {

  /// Captures the whole screen at its native resolution.
  func take(format: FBScreenshotFormat) async throws -> Data {
    let configuration = FBScreenshotConfiguration(encoding: try FBScreenshotEncoding(format: format))
    return try await take(configuration: configuration).imageData
  }
}

enum ScreenshotFormatError: Error, Hashable {
  case unrecognizedFormat(String)
}

extension ScreenshotFormatError: LocalizedError {
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
      throw ScreenshotFormatError.unrecognizedFormat(format.rawValue)
    }
  }
}
