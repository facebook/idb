// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
import Foundation

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

  // MARK: Public Methods

  public func getIconLayout() -> FBFuture<NSArray> {
    (getRawIconState(formatVersion: 2)
      .onQueue(
        queue,
        map: { result -> AnyObject in
          result as! NSArray as AnyObject
        })) as! FBFuture<NSArray>
  }

  public func getRawIconState(formatVersion: UInt) -> FBFuture<AnyObject> {
    let formatVersionString = "\(formatVersion)"
    return FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          let result = try self.connection.sendAndReceiveMessage(["command": "getIconState", "formatVersion": formatVersionString])
          return result as AnyObject
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<AnyObject>
  }

  public func setIconLayout(_ iconLayout: NSArray) -> FBFuture<NSNull> {
    FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          try self.connection.sendMessage(["command": "setIconState", "iconState": iconLayout])
          _ = try self.connection.receive(Int(IconLayoutSize))
          return NSNull()
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSNull>
  }

  public func getHomeScreenIconMetrics() -> FBFuture<NSDictionary> {
    FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          let result = try self.connection.sendAndReceiveMessage(["command": "getHomeScreenIconMetrics"])
          return result as? NSDictionary
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSDictionary>
  }

  @objc public func wallpaperImageData(forKind name: String) -> FBFuture<NSData> {
    FBFuture.onQueue(
      queue,
      resolveValue: { errorPointer in
        do {
          let response = try self.connection.sendAndReceiveMessage(["command": "getWallpaperPreviewImage", "wallpaperName": name])
          guard let responseDict = response as? [String: Any] else {
            return nil
          }
          guard let data = responseDict["pngData"] as? NSData else {
            return FBControlCoreError.describe("No pngData in response \(responseDict)").fail(errorPointer) as? NSData
          }
          return data
        } catch {
          errorPointer?.pointee = error as NSError
          return nil
        }
      }) as! FBFuture<NSData>
  }

  @objc public func iconContainer() -> any FBFileContainerProtocol {
    FBSpringboardServicesIconContainer(client: self)
  }
}

fileprivate typealias IconLayoutJSONType = [[String]]

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
    let filename = (sourcePath as NSString).lastPathComponent
    guard validFilenames.contains(filename) else {
      return FBControlCoreError.describe("\(filename) is not one of \(FBCollectionInformation.oneLineDescription(from: validFilenames))").failFuture() as! FBFuture<NSString>
    }
    return
      (client.getIconLayout()
      .onQueue(
        client.queue,
        fmap: { layout -> FBFuture<AnyObject> in
          let layoutArray = layout as! [[Any]]
          do {
            if filename == IconJSONFile {
              let jsonLayout = FBSpringboardServicesIconContainer.flattenBaseFormat(layoutArray)
              let data = try JSONSerialization.data(withJSONObject: jsonLayout, options: .prettyPrinted)
              try data.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
              return FBFuture(result: destinationPath as NSString as AnyObject)
            } else {
              let data = try PropertyListSerialization.data(fromPropertyList: layout, format: .xml, options: 0)
              try data.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
              return FBFuture(result: destinationPath as NSString as AnyObject)
            }
          } catch {
            return FBFuture(error: error)
          }
        })) as! FBFuture<NSString>
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull> {
    (iconLayoutFromSourcePath(sourcePath, toDestinationFile: (destinationPath as NSString).lastPathComponent)
      .onQueue(
        client.queue,
        fmap: { layout -> FBFuture<AnyObject> in
          self.client.setIconLayout(layout) as! FBFuture<AnyObject>
        })) as! FBFuture<NSNull>
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

  // MARK: Private

  private func iconLayoutFromSourcePath(_ sourcePath: String, toDestinationFile filename: String) -> FBFuture<NSArray> {
    if filename == IconJSONFile {
      let jsonFuture: FBFuture<NSArray> =
        FBFuture.onQueue(
          client.queue,
          resolveValue: { errorPointer in
            let data: Data
            let jsonObject: Any
            do {
              data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
              jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            } catch {
              errorPointer?.pointee = error as NSError
              return nil
            }
            guard let layout = jsonObject as? IconLayoutJSONType else {
              return FBControlCoreError.describe("JSON is not in the expected format").fail(errorPointer) as? NSArray
            }
            return layout as NSArray
          }) as! FBFuture<NSArray>
      return
        (jsonFuture.onQueue(
          client.queue,
          fmap: { jsonArray -> FBFuture<AnyObject> in
            let parsed = jsonArray as! IconLayoutJSONType
            return self.convertJSONFormatToWireFormat(parsed) as! FBFuture<AnyObject>
          })) as! FBFuture<NSArray>
    }
    if filename == IconPlistFile {
      return FBFuture.onQueue(
        client.queue,
        resolveValue: { errorOut in
          do {
            let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
            let layout = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            return layout as? NSArray
          } catch {
            errorOut?.pointee = error as NSError
            return nil
          }
        }) as! FBFuture<NSArray>
    }
    return FBControlCoreError.describe("\(filename) is not one of \(FBCollectionInformation.oneLineDescription(from: validFilenames))").failFuture() as! FBFuture<NSArray>
  }

  private func convertJSONFormatToWireFormat(_ jsonFormat: IconLayoutJSONType) -> FBFuture<NSArray> {
    (client.getIconLayout()
      .onQueue(
        client.queue,
        map: { currentApps -> AnyObject in
          let currentAppsArray = currentApps as! [[Any]]
          let iconsByBundleID = FBSpringboardServicesIconContainer.keyIconsByBundleID(currentAppsArray)
          var format: [[Any]] = []
          for jsonPage in jsonFormat {
            var fullPage: [Any] = []
            for bundleID in jsonPage {
              let icon = iconsByBundleID[bundleID]
              if let icon {
                fullPage.append(icon)
              }
            }
            format.append(fullPage)
          }
          return format as NSArray as AnyObject
        })) as! FBFuture<NSArray>
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
