/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

// swiftlint:disable force_cast

public struct FBWallpaperName: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
}

extension FBWallpaperName {
  public static let homescreen = FBWallpaperName(rawValue: "homescreen")
  public static let lockscreen = FBWallpaperName(rawValue: "lockscreen")
}

public let FBSpringboardServiceName: String = "com.apple.springboardservices"

private let IconPlistFile = "icons.plist"
private let IconJSONFile = "icons.json"
private let IconLayoutSize: UInt = 4

/// Wraps the non-`Sendable` `FBAMDServiceConnection` so it can be captured by
/// the `@Sendable` closures dispatched on the serial connection queue. Serial
/// dispatch guarantees thread-safe access to the underlying connection.
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

@objc(FBSpringboardServicesClient)
public class FBSpringboardServicesClient: NSObject {
  private var connection: FBAMDServiceConnection
  fileprivate var queue: DispatchQueue
  private var logger: any FBControlCoreLogger

  // MARK: ObjC-visible Constants

  @objc public static let wallpaperNameHomescreen: String = "homescreen"
  @objc public static let wallpaperNameLockscreen: String = "lockscreen"
  @objc public static let serviceName: String = "com.apple.springboardservices"

  // MARK: Initializers

  @objc public static func springboardServicesClient(connection: FBAMDServiceConnection, logger: any FBControlCoreLogger) -> FBSpringboardServicesClient {
    let queue = DispatchQueue(label: "com.facebook.FBDeviceControl.springboard_services")
    return FBSpringboardServicesClient(connection: connection, queue: queue, logger: logger)
  }

  @objc public convenience init(connection: FBAMDServiceConnection, logger: any FBControlCoreLogger) {
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
    super.init()
  }

  // MARK: Public Methods (legacy FBFuture entry points)

  public func getIconLayout() -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await getIconLayoutAsync() as NSArray
    }
  }

  public func getRawIconState(formatVersion: UInt) -> FBFuture<AnyObject> {
    fbFutureFromAsync { [self] in
      try await getRawIconStateAsync(formatVersion: formatVersion)
    }
  }

  public func setIconLayout(_ iconLayout: NSArray) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await setIconLayoutAsync(iconLayout)
      return NSNull()
    }
  }

  public func getHomeScreenIconMetrics() -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await getHomeScreenIconMetricsAsync() as NSDictionary
    }
  }

  @objc public func wallpaperImageData(forKind name: String) -> FBFuture<NSData> {
    fbFutureFromAsync { [self] in
      try await wallpaperImageDataAsync(forKind: name) as NSData
    }
  }

  @objc public func iconContainer() -> any FBFileContainerProtocol {
    FBSpringboardServicesIconContainer(client: self)
  }

  // MARK: - Async

  public func getIconLayoutAsync() async throws -> [Any] {
    let raw = try await getRawIconStateAsync(formatVersion: 2)
    guard let array = raw as? [Any] else {
      throw FBControlCoreError.describe("Icon state response \(raw) is not an array").build()
    }
    return array
  }

  public func getRawIconStateAsync(formatVersion: UInt) async throws -> AnyObject {
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

  public func setIconLayoutAsync(_ iconLayout: NSArray) async throws {
    let connectionBox = SpringboardConnectionBox(connection)
    let layoutBox = SpringboardDataBox(iconLayout)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          try connectionBox.connection.sendMessage(["command": "setIconState", "iconState": layoutBox.value])
          _ = try connectionBox.connection.receive(Int(IconLayoutSize))
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func getHomeScreenIconMetricsAsync() async throws -> [String: Any] {
    let connectionBox = SpringboardConnectionBox(connection)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage(["command": "getHomeScreenIconMetrics"])
          continuation.resume(returning: (result as? [String: Any]) ?? [:])
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func wallpaperImageDataAsync(forKind name: String) async throws -> Data {
    let connectionBox = SpringboardConnectionBox(connection)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      queue.async {
        do {
          let response = try connectionBox.connection.sendAndReceiveMessage(["command": "getWallpaperPreviewImage", "wallpaperName": name])
          guard let responseDict = response as? [String: Any] else {
            continuation.resume(throwing: FBControlCoreError.describe("Response \(String(describing: response)) is not a dictionary").build())
            return
          }
          guard let data = responseDict["pngData"] as? Data else {
            continuation.resume(throwing: FBControlCoreError.describe("No pngData in response \(responseDict)").build())
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

class FBSpringboardServicesIconContainer: NSObject, FBFileContainerProtocol {
  private var client: FBSpringboardServicesClient
  private var validFilenames: [String]

  init(client: FBSpringboardServicesClient) {
    self.client = client
    self.validFilenames = [IconPlistFile, IconJSONFile]
    super.init()
  }

  // MARK: FBFileContainer Implementation

  func contents(ofDirectory path: String) -> FBFuture<NSArray> {
    FBFuture(result: validFilenames as NSArray)
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) -> FBFuture<NSString> {
    fbFutureFromAsync { [self] in
      try await copyFromContainerAsync(sourcePath: sourcePath, toHost: destinationPath) as NSString
    }
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await copyFromHostAsync(sourcePath: sourcePath, toContainer: destinationPath)
      return NSNull()
    }
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) -> FBFuture<FBFuture<NSNull>> {
    FBControlCoreError.describe("tail is not implemented for FBSpringboardServicesIconContainer").failFuture() as! FBFuture<FBFuture<NSNull>>
  }

  func createDirectory(_ directoryPath: String) -> FBFuture<NSNull> {
    FBControlCoreError.describe("createDirectory does not make sense for Springboard File Containers").failFuture() as! FBFuture<NSNull>
  }

  func move(from sourcePath: String, to destinationPath: String) -> FBFuture<NSNull> {
    FBControlCoreError.describe("moveFrom does not make sense for Springboard File Containers").failFuture() as! FBFuture<NSNull>
  }

  func remove(_ path: String) -> FBFuture<NSNull> {
    FBControlCoreError.describe("remove does not make sense for Springboard File Containers").failFuture() as! FBFuture<NSNull>
  }

  // MARK: - Async

  fileprivate func copyFromContainerAsync(sourcePath: String, toHost destinationPath: String) async throws -> String {
    let filename = (sourcePath as NSString).lastPathComponent
    guard validFilenames.contains(filename) else {
      throw FBControlCoreError.describe("\(filename) is not one of \(FBCollectionInformation.oneLineDescription(from: validFilenames))").build()
    }
    let layout = try await client.getIconLayoutAsync()
    if filename == IconJSONFile {
      let jsonLayout = FBSpringboardServicesIconContainer.flattenBaseFormat(layout as! [[Any]])
      let data = try JSONSerialization.data(withJSONObject: jsonLayout, options: .prettyPrinted)
      try data.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
    } else {
      let data = try PropertyListSerialization.data(fromPropertyList: layout, format: .xml, options: 0)
      try data.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
    }
    return destinationPath
  }

  fileprivate func copyFromHostAsync(sourcePath: String, toContainer destinationPath: String) async throws {
    let layout = try await iconLayoutFromSourcePathAsync(sourcePath, toDestinationFile: (destinationPath as NSString).lastPathComponent)
    try await client.setIconLayoutAsync(layout)
  }

  // MARK: Private

  private func iconLayoutFromSourcePathAsync(_ sourcePath: String, toDestinationFile filename: String) async throws -> NSArray {
    if filename == IconJSONFile {
      let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
      let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
      guard let layout = jsonObject as? IconLayoutJSONType else {
        throw FBControlCoreError.describe("JSON is not in the expected format").build()
      }
      return try await convertJSONFormatToWireFormatAsync(layout)
    }
    if filename == IconPlistFile {
      let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
      let layout = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
      guard let array = layout as? NSArray else {
        throw FBControlCoreError.describe("Plist is not an array").build()
      }
      return array
    }
    throw FBControlCoreError.describe("\(filename) is not one of \(FBCollectionInformation.oneLineDescription(from: validFilenames))").build()
  }

  private func convertJSONFormatToWireFormatAsync(_ jsonFormat: IconLayoutJSONType) async throws -> NSArray {
    let currentApps = try await client.getIconLayoutAsync()
    let currentAppsArray = currentApps as! [[Any]]
    let iconsByBundleID = FBSpringboardServicesIconContainer.keyIconsByBundleID(currentAppsArray)
    var format: [[Any]] = []
    for jsonPage in jsonFormat {
      var fullPage: [Any] = []
      for bundleID in jsonPage {
        if let icon = iconsByBundleID[bundleID] {
          fullPage.append(icon)
        }
      }
      format.append(fullPage)
    }
    return format as NSArray
  }

  static func flattenBaseFormat(_ baseFormat: [[Any]]) -> [[String]] {
    var flatFormat: IconLayoutJSONType = []
    for basePage in baseFormat {
      var flatPage: [String] = []
      for icon in basePage {
        if let iconDict = icon as? [String: Any], let bundleIdentifier = iconDict["bundleIdentifier"] as? String {
          flatPage.append(bundleIdentifier)
        }
      }
      flatFormat.append(flatPage)
    }
    return flatFormat
  }

  static func keyIconsByBundleID(_ layout: [[Any]]) -> [String: [String: Any]] {
    var iconsByBundleID: [String: [String: Any]] = [:]
    for page in layout {
      for icon in page {
        if let iconDict = icon as? [String: Any], let bundleIdentifier = iconDict["bundleIdentifier"] as? String {
          iconsByBundleID[bundleIdentifier] = iconDict
        }
      }
    }
    return iconsByBundleID
  }
}
