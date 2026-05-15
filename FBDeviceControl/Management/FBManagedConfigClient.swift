/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

public let FBManagedConfigService: String = "com.apple.mobile.MCInstall"

private let OrderedIdentifiers = "OrderedIdentifiers"
private let ProfileMetadata = "ProfileMetadata"
private let PayloadUUID = "PayloadUUID"
private let PayloadVersion = "PayloadVersion"

/// Wraps the non-`Sendable` `FBAMDServiceConnection` so it can be captured by
/// the `@Sendable` closures dispatched on the serial connection queue. Serial
/// dispatch guarantees thread-safe access to the underlying connection.
private final class ManagedConfigConnectionBox: @unchecked Sendable {
  let connection: FBAMDServiceConnection
  init(_ connection: FBAMDServiceConnection) {
    self.connection = connection
  }
}

/// Wraps an `Any` payload so it can be captured by a `@Sendable` closure.
private final class ManagedConfigDataBox: @unchecked Sendable {
  let value: Any
  init(_ value: Any) {
    self.value = value
  }
}

@objc(FBManagedConfigClient)
public class FBManagedConfigClient: NSObject {
  private var connection: FBAMDServiceConnection
  private var queue: DispatchQueue
  private var logger: any FBControlCoreLogger

  // MARK: ObjC-visible Constants

  @objc public static let serviceName: String = "com.apple.mobile.MCInstall"

  private static let wallpaperWhereForName: [String: NSNumber] = [
    FBWallpaperName.homescreen.rawValue: 0,
    FBWallpaperName.lockscreen.rawValue: 1,
  ]

  // MARK: Initializers

  @objc public static func managedConfigClient(connection: FBAMDServiceConnection, logger: any FBControlCoreLogger) -> FBManagedConfigClient {
    let queue = DispatchQueue(label: "com.facebook.FBDeviceControl.managed_config")
    return FBManagedConfigClient(connection: connection, queue: queue, logger: logger)
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

  @objc public func getCloudConfiguration() -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await getCloudConfigurationAsync() as NSDictionary
    }
  }

  @objc public func changeWallpaper(withName name: String, data: Data) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await changeWallpaperAsync(name: name, data: data)
      return NSNull()
    }
  }

  @objc public func getProfileList() -> FBFuture<NSArray> {
    fbFutureFromAsync { [self] in
      try await getProfileListAsync() as NSArray
    }
  }

  @objc public func installProfile(_ payload: Data) -> FBFuture<NSDictionary> {
    fbFutureFromAsync { [self] in
      try await installProfileAsync(payload) as NSDictionary
    }
  }

  @objc public func removeProfile(_ profileName: String) -> FBFuture<NSNull> {
    fbFutureFromAsync { [self] in
      try await removeProfileAsync(profileName)
      return NSNull()
    }
  }

  // MARK: - Async

  public func getCloudConfigurationAsync() async throws -> [String: Any] {
    let connectionBox = ManagedConfigConnectionBox(connection)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage(["RequestType": "GetCloudConfiguration"])
          guard let resultDict = result as? [String: Any] else {
            continuation.resume(returning: [:])
            return
          }
          let filtered = FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: resultDict) as [String: Any]
          continuation.resume(returning: filtered)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func changeWallpaperAsync(name: String, data: Data) async throws {
    guard let whereNumber = FBManagedConfigClient.wallpaperWhereForName[name] else {
      throw FBControlCoreError.describe("\(name) is not a valid Wallpaper Name").build()
    }
    try await changeSettingsAsync(settings: [["Item": "Wallpaper", "Image": data, "Where": whereNumber]])
  }

  public func getProfileListAsync() async throws -> [Any] {
    let connectionBox = ManagedConfigConnectionBox(connection)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Any], Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage(["RequestType": "GetProfileList"])
          guard let resultDict = result as? [String: Any] else {
            continuation.resume(returning: [])
            return
          }
          guard let orderedIdentifiers = resultDict[OrderedIdentifiers] as? [Any] else {
            continuation.resume(throwing: FBControlCoreError.describe("\(OrderedIdentifiers) is not present in response").build())
            return
          }
          guard FBCollectionInformation.isArrayHeterogeneous(orderedIdentifiers, with: NSString.self) else {
            continuation.resume(throwing: FBControlCoreError.describe("\(OrderedIdentifiers) is not an Array<String>").build())
            return
          }
          continuation.resume(returning: orderedIdentifiers)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func installProfileAsync(_ payload: Data) async throws -> [String: Any] {
    let connectionBox = ManagedConfigConnectionBox(connection)
    let payloadBox = ManagedConfigDataBox(payload)
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage(["RequestType": "InstallProfile", "Payload": payloadBox.value])
          guard let resultDict = result as? [String: Any] else {
            continuation.resume(returning: [:])
            return
          }
          let filtered = FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: resultDict) as [String: Any]
          continuation.resume(returning: filtered)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func removeProfileAsync(_ profileName: String) async throws {
    let connectionBox = ManagedConfigConnectionBox(connection)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let result = try connectionBox.connection.sendAndReceiveMessage(["RequestType": "GetProfileList"])
          guard let resultDict = result as? [String: Any] else {
            continuation.resume(returning: ())
            return
          }
          guard let metadata = resultDict[ProfileMetadata] as? [String: Any],
            let profileMetadata = metadata[profileName] as? [String: Any]
          else {
            let identifiers = resultDict[OrderedIdentifiers] as? [Any] ?? []
            continuation.resume(throwing: FBControlCoreError.describe("\(profileName) is not one of \(FBCollectionInformation.oneLineDescription(from: identifiers))").build())
            return
          }
          let profileIdentifier: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadIdentifier": profileName,
            PayloadUUID: profileMetadata[PayloadUUID] as Any,
            PayloadVersion: profileMetadata[PayloadVersion] as Any,
          ]
          let payload = try PropertyListSerialization.data(fromPropertyList: profileIdentifier, format: .binary, options: 0)
          let removeResult = try connectionBox.connection.sendAndReceiveMessage(["RequestType": "RemoveProfile", "ProfileIdentifier": payload])
          guard let removeResultDict = removeResult as? [String: Any] else {
            continuation.resume(returning: ())
            return
          }
          if (removeResultDict["Status"] as? String) == "Error" {
            continuation.resume(throwing: FBControlCoreError.describe("Status is Error: \(removeResultDict)").build())
            return
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  // MARK: Private Methods

  private func changeSettingsAsync(settings: [[String: Any]]) async throws {
    let connectionBox = ManagedConfigConnectionBox(connection)
    let settingsBox = ManagedConfigDataBox(settings)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          _ = try connectionBox.connection.sendAndReceiveMessage(["RequestType": "Settings", "Settings": settingsBox.value])
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
