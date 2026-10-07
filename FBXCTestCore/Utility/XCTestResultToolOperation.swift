/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

private let XcrunPath = "/usr/bin/xcrun"
private let SipsPath = "/usr/bin/sips"
private let HEIC = "public.heic"
private let JPEG = "public.jpeg"

enum XCTestResultToolError: Error, LocalizedError {
  case unrecognizedScreenshotEncoding(encoding: String)

  public var errorDescription: String? {
    switch self {
    case let .unrecognizedScreenshotEncoding(encoding):
      return "Unrecognized XCTest screenshot encoding: \(encoding)"
    }
  }
}

final class XCTestResultToolOperation {

  public static func getJSON(from path: String, forId bundleObjectId: String?, logger: ControlCoreLogger?, timeout: TimeInterval? = nil) async throws -> NSDictionary {
    logger?.log("Getting json for id \(bundleObjectId ?? "nil")")
    var arguments = ["get", "--path", path, "--format", "json"]
    if let bundleObjectId, !bundleObjectId.isEmpty {
      arguments.append(contentsOf: ["--id", bundleObjectId])
    }
    return json(from: try await xcresulttool(arguments: arguments, logger: logger, timeout: timeout))
  }

  public static func exportFile(from path: String, to destination: String, forId bundleObjectId: String, logger: ControlCoreLogger?, timeout: TimeInterval? = nil) async throws {
    _ = try await xcresulttool(
      arguments: ["export", "--path", path, "--output-path", destination, "--id", bundleObjectId, "--type", "file"],
      logger: logger,
      timeout: timeout)
  }

  public static func exportDirectory(from path: String, to destination: String, forId bundleObjectId: String, logger: ControlCoreLogger?) async throws {
    _ = try await xcresulttool(
      arguments: ["export", "--path", path, "--output-path", destination, "--id", bundleObjectId, "--type", "directory"],
      logger: logger)
  }

  public static func exportJPEG(from path: String, to destination: String, forId bundleObjectId: String, type encodeType: String, logger: ControlCoreLogger?, timeout: TimeInterval? = nil) async throws {
    // The export runs first, so an unusable result bundle masks the encoding
    // check: a caller with both problems only learns about the export.
    try await exportFile(from: path, to: destination, forId: bundleObjectId, logger: logger, timeout: timeout)
    if encodeType == HEIC {
      _ = try await run(SipsPath, arguments: ["-s", "format", "jpeg", destination, "--out", destination], logger: logger, timeout: timeout)
    } else if encodeType == JPEG {
      return
    } else {
      throw XCTestResultToolError.unrecognizedScreenshotEncoding(encoding: encodeType)
    }
  }

  public static func describeFormat(logger: ControlCoreLogger?) async throws -> NSDictionary {
    json(from: try await xcresulttool(arguments: ["formatDescription"], logger: logger))
  }

  private static func xcresulttool(arguments: [String], logger: ControlCoreLogger?, timeout: TimeInterval? = nil) async throws -> String {
    try await run(XcrunPath, arguments: ["xcresulttool"] + arguments, logger: logger, timeout: timeout)
  }

  private static func run(_ executable: String, arguments: [String], logger: ControlCoreLogger?, timeout: TimeInterval? = nil) async throws -> String {
    let subprocess = Subprocess(executable: executable, arguments: arguments)
    guard let logger else {
      return try await subprocess.run(timeout: timeout).standardOutput
    }
    return try await subprocess.run(output: .string, error: .logger(logger), timeout: timeout, logger: logger).standardOutput
  }

  private static func json(from output: String) -> NSDictionary {
    guard let data = output.data(using: .utf8) else {
      return NSDictionary()
    }
    return (try? JSONSerialization.jsonObject(with: data, options: [])) as? NSDictionary ?? NSDictionary()
  }
}
