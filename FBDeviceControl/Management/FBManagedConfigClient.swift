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

  // MARK: Public Methods

  @objc public func getCloudConfiguration() -> FBFuture<NSDictionary> {
    FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          let result = try self.connection.sendAndReceiveMessage(["RequestType": "GetCloudConfiguration"])
          guard let resultDict = result as? [String: Any] else {
            return nil
          }
          return FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: resultDict) as NSDictionary
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSDictionary>
  }

  @objc public func changeWallpaper(withName name: String, data: Data) -> FBFuture<NSNull> {
    guard let whereNumber = FBManagedConfigClient.wallpaperWhereForName[name] else {
      return FBControlCoreError.describe("\(name) is not a valid Wallpaper Name").failFuture() as! FBFuture<NSNull>
    }
    return changeSettings(settings: [["Item": "Wallpaper", "Image": data, "Where": whereNumber]])
  }

  @objc public func getProfileList() -> FBFuture<NSArray> {
    FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          let result = try self.connection.sendAndReceiveMessage(["RequestType": "GetProfileList"])
          guard let resultDict = result as? [String: Any] else {
            return nil
          }
          guard let orderedIdentifiers = resultDict[OrderedIdentifiers] as? [Any] else {
            return FBControlCoreError.describe("\(OrderedIdentifiers) is not present in response").fail(errorPointer) as? NSArray
          }
          guard FBCollectionInformation.isArrayHeterogeneous(orderedIdentifiers, with: NSString.self) else {
            return FBControlCoreError.describe("\(OrderedIdentifiers) is not an Array<String>").fail(errorPointer) as? NSArray
          }
          return orderedIdentifiers as NSArray
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSArray>
  }

  @objc public func installProfile(_ payload: Data) -> FBFuture<NSDictionary> {
    FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          let result = try self.connection.sendAndReceiveMessage(["RequestType": "InstallProfile", "Payload": payload])
          guard let resultDict = result as? [String: Any] else {
            return nil
          }
          return FBCollectionOperations.recursiveFilteredJSONSerializableRepresentation(of: resultDict) as NSDictionary
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSDictionary>
  }

  @objc public func removeProfile(_ profileName: String) -> FBFuture<NSNull> {
    FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          let result = try self.connection.sendAndReceiveMessage(["RequestType": "GetProfileList"])
          guard let resultDict = result as? [String: Any] else {
            return nil
          }
          guard let metadata = resultDict[ProfileMetadata] as? [String: Any],
            let profileMetadata = metadata[profileName] as? [String: Any]
          else {
            let identifiers = resultDict[OrderedIdentifiers] as? [Any] ?? []
            return FBControlCoreError.describe("\(profileName) is not one of \(FBCollectionInformation.oneLineDescription(from: identifiers))").fail(errorPointer) as? NSNull
          }
          let profileIdentifier: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadIdentifier": profileName,
            PayloadUUID: profileMetadata[PayloadUUID] as Any,
            PayloadVersion: profileMetadata[PayloadVersion] as Any,
          ]
          let payload = try PropertyListSerialization.data(fromPropertyList: profileIdentifier, format: .binary, options: 0)
          let removeResult = try self.connection.sendAndReceiveMessage(["RequestType": "RemoveProfile", "ProfileIdentifier": payload])
          guard let removeResultDict = removeResult as? [String: Any] else {
            return nil
          }
          if (removeResultDict["Status"] as? String) == "Error" {
            return FBControlCoreError.describe("Status is Error: \(removeResultDict)").fail(errorPointer) as? NSNull
          }
          return NSNull()
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSNull>
  }

  // MARK: Private Methods

  private func changeSettings(settings: [[String: Any]]) -> FBFuture<NSNull> {
    FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          _ = try self.connection.sendAndReceiveMessage(["RequestType": "Settings", "Settings": settings])
          return NSNull()
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSNull>
  }
}
