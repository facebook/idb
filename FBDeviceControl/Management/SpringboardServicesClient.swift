/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public struct WallpaperName: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
}

extension WallpaperName {
  public static let homescreen = WallpaperName(rawValue: "homescreen")
  public static let lockscreen = WallpaperName(rawValue: "lockscreen")
}

let FBSpringboardServiceName: String = "com.apple.springboardservices"

private let IconPlistFile = "icons.plist"
private let IconJSONFile = "icons.json"
private let IconLayoutSize: UInt = 4

public enum SpringboardServicesError: Error, LocalizedError {
  case unexpectedResponse(command: String, expected: String, actual: String)
  case invalidIconLayoutJSON(path: String)
  case invalidIconLayoutPlist(path: String)
  case invalidIconLayoutFile(filename: String, validFilenames: [String])
  case responseNotADictionary(response: String)
  case missingImageData(response: String)
  case tailNotImplemented
  case operationUnsupported(operation: String)

  public var errorDescription: String? {
    switch self {
    case .unexpectedResponse(let command, let expected, let actual):
      return "SpringBoardServices command '\(command)' returned \(actual), expected \(expected)"
    case .invalidIconLayoutJSON(let path):
      return "Icon layout JSON at '\(path)' is not in the expected format"
    case .invalidIconLayoutPlist(let path):
      return "Icon layout plist at '\(path)' is not in the expected format"
    case .invalidIconLayoutFile(let filename, let validFilenames):
      return "\(filename) is not one of \(FBCollectionInformation.oneLineDescription(from: validFilenames))"
    case .responseNotADictionary(let response):
      return "Response \(response) is not a dictionary"
    case .missingImageData(let response):
      return "No pngData in response \(response)"
    case .tailNotImplemented:
      return "tail is not implemented for SpringboardServicesIconContainer"
    case .operationUnsupported(let operation):
      return "\(operation) does not make sense for Springboard File Containers"
    }
  }
}

/// Carries the non-`Sendable` connection across the serial-queue boundary; only touched on that queue.
private final class SpringboardConnectionBox: @unchecked Sendable {
  let connection: FBAMDServiceConnection
  init(_ connection: FBAMDServiceConnection) {
    self.connection = connection
  }
}

/// Wraps an `Any` payload so it can be captured by a `@Sendable` closure.
private final class SpringboardDataBox: @unchecked Sendable {
  let value: Any
  init(_ value: Any) {
    self.value = value
  }
}

class SpringboardServicesClient {
  private let connection: FBAMDServiceConnection
  fileprivate let queue: DispatchQueue
  private let logger: any FBControlCoreLogger

  // MARK: - Constants

  static let wallpaperNameHomescreen: String = "homescreen"
  static let wallpaperNameLockscreen: String = "lockscreen"
  static let serviceName: String = "com.apple.springboardservices"

  // MARK: - Initializers

  static func springboardServicesClient(connection: FBAMDServiceConnection, logger: any FBControlCoreLogger) -> SpringboardServicesClient {
    let queue = DispatchQueue(label: "com.facebook.FBDeviceControl.springboard_services")
    return SpringboardServicesClient(connection: connection, queue: queue, logger: logger)
  }

  convenience init(connection: FBAMDServiceConnection, logger: any FBControlCoreLogger) {
    let queue = DispatchQueue(label: "com.facebook.FBDeviceControl.springboard_services")
    self.init(connection: connection, queue: queue, logger: logger)
  }

  init(
    connection: FBAMDServiceConnection,
    queue: DispatchQueue,
    logger: any FBControlCoreLogger
  ) {
    self.connection = connection
    self.queue = queue
    self.logger = logger
  }

  func iconContainer() -> any AsyncFileContainer {
    SpringboardServicesIconContainer(client: self)
  }

  // MARK: - Async

  func getIconLayout() async throws -> SpringboardIconLayout {
    let raw = try await getRawIconState(formatVersion: 2)
    return try SpringboardIconLayout(rawValue: raw)
  }

  func getRawIconState(formatVersion: UInt) async throws -> AnyObject {
    let connectionBox = SpringboardConnectionBox(connection)
    let formatVersionString = "\(formatVersion)"
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<AnyObject, Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage(["command": "getIconState", "formatVersion": formatVersionString])
          continuation.resume(returning: result as AnyObject)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func setIconLayout(_ iconLayout: SpringboardIconLayout) async throws {
    try await sendIconLayout(iconLayout.rawValue)
  }

  private func sendIconLayout(_ iconLayout: NSArray) async throws {
    let connectionBox = SpringboardConnectionBox(connection)
    let layoutBox = SpringboardDataBox(iconLayout)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          try connectionBox.connection.sendMessage(["command": "setIconState", "iconState": layoutBox.value])
          let response = try connectionBox.connection.receive(Int(IconLayoutSize))
          if response.count != Int(IconLayoutSize) {
            continuation.resume(
              throwing: SpringboardServicesError.unexpectedResponse(
                command: "setIconState",
                expected: "\(IconLayoutSize) response bytes",
                actual: "\(response.count) response bytes"))
            return
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func getHomeScreenIconMetrics() async throws -> [String: Any] {
    let connectionBox = SpringboardConnectionBox(connection)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage(["command": "getHomeScreenIconMetrics"])
          guard let metrics = result as? [String: Any] else {
            continuation.resume(
              throwing: SpringboardServicesError.unexpectedResponse(
                command: "getHomeScreenIconMetrics",
                expected: "a dictionary",
                actual: String(describing: result)))
            return
          }
          continuation.resume(returning: metrics)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func wallpaperImageData(forKind name: String) async throws -> Data {
    let connectionBox = SpringboardConnectionBox(connection)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      queue.async {
        do {
          let response = try connectionBox.connection.sendAndReceiveMessage(["command": "getWallpaperPreviewImage", "wallpaperName": name])
          guard let responseDict = response as? [String: Any] else {
            continuation.resume(throwing: SpringboardServicesError.responseNotADictionary(response: String(describing: response)))
            return
          }
          guard let data = responseDict["pngData"] as? Data else {
            continuation.resume(throwing: SpringboardServicesError.missingImageData(response: String(describing: responseDict)))
            return
          }
          continuation.resume(returning: data)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}

private typealias IconLayoutJSONType = [[String]]

class SpringboardServicesIconContainer: AsyncFileContainer {
  private let client: SpringboardServicesClient
  private let validFilenames: [String]

  init(client: SpringboardServicesClient) {
    self.client = client
    self.validFilenames = [IconPlistFile, IconJSONFile]
  }

  // MARK: - AsyncFileContainer

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    try await copyFromHost(sourcePath: sourcePath, toContainer: destinationPath)
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    try await copyFromContainer(sourcePath: sourcePath, toHost: destinationPath)
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw SpringboardServicesError.tailNotImplemented
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw SpringboardServicesError.operationUnsupported(operation: "createDirectory")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw SpringboardServicesError.operationUnsupported(operation: "moveFrom")
  }

  func remove(_ path: String) async throws {
    throw SpringboardServicesError.operationUnsupported(operation: "remove")
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    validFilenames
  }

  // MARK: - Async

  fileprivate func copyFromContainer(sourcePath: String, toHost destinationPath: String) async throws -> String {
    let filename = (sourcePath as NSString).lastPathComponent
    guard validFilenames.contains(filename) else {
      throw SpringboardServicesError.invalidIconLayoutFile(filename: filename, validFilenames: validFilenames)
    }
    let layout = try await client.getIconLayout()
    if filename == IconJSONFile {
      let data = try JSONSerialization.data(withJSONObject: layout.flattenedBundleIdentifierPages(), options: .prettyPrinted)
      try data.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
    } else {
      let data = try PropertyListSerialization.data(fromPropertyList: layout.pages, format: .xml, options: 0)
      try data.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
    }
    return destinationPath
  }

  fileprivate func copyFromHost(sourcePath: String, toContainer destinationPath: String) async throws {
    let layout = try await iconLayoutFromSourcePath(sourcePath, toDestinationFile: (destinationPath as NSString).lastPathComponent)
    try await client.setIconLayout(layout)
  }

  // MARK: - Private

  private func iconLayoutFromSourcePath(_ sourcePath: String, toDestinationFile filename: String) async throws -> SpringboardIconLayout {
    if filename == IconJSONFile {
      let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
      let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
      guard let layout = jsonObject as? IconLayoutJSONType else {
        throw SpringboardServicesError.invalidIconLayoutJSON(path: sourcePath)
      }
      return try await convertJSONFormatToWireFormat(layout)
    }
    if filename == IconPlistFile {
      let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
      let layout = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
      do {
        return try SpringboardIconLayout(rawValue: layout)
      } catch {
        throw SpringboardServicesError.invalidIconLayoutPlist(path: sourcePath)
      }
    }
    throw SpringboardServicesError.invalidIconLayoutFile(filename: filename, validFilenames: validFilenames)
  }

  private func convertJSONFormatToWireFormat(_ jsonFormat: IconLayoutJSONType) async throws -> SpringboardIconLayout {
    let currentLayout = try await client.getIconLayout()
    let iconsByBundleID = currentLayout.iconsByBundleID
    var format: [[[String: Any]]] = []
    for jsonPage in jsonFormat {
      var fullPage: [[String: Any]] = []
      for bundleID in jsonPage {
        if let icon = iconsByBundleID[bundleID] {
          fullPage.append(icon)
        }
      }
      format.append(fullPage)
    }
    return SpringboardIconLayout(pages: format)
  }
}
