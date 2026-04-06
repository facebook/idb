// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
import Foundation

private let MountRootPath = "mounted"
private let ExtractedSymbolsDirectory = "Symbols"

// MARK: - FBDeviceFileContainer

@objc(FBDeviceFileContainer)
public class FBDeviceFileContainer: NSObject, FBFileContainerProtocol {
  private let queue: DispatchQueue
  private let connection: FBAFCConnection

  @objc public init(afcConnection connection: FBAFCConnection, queue: DispatchQueue) {
    self.connection = connection
    self.queue = queue
    super.init()
  }

  // MARK: FBFileContainerProtocol

  public func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull> {
    return handleAFCOperation { afc in
      try afc.copy(fromHost: sourcePath, toContainerPath: destinationPath)
      return NSNull()
    }
  }

  public func copy(fromContainer sourcePath: String, toHost destinationPath: String) -> FBFuture<NSString> {
    var destination = destinationPath
    if FBDeviceFileContainer.isDirectory(destinationPath) {
      destination = (destinationPath as NSString).appendingPathComponent((sourcePath as NSString).lastPathComponent)
    }
    return (readFileFromPath(inContainer: sourcePath)
      .onQueue(queue, fmap: { (fileData: AnyObject) -> FBFuture<AnyObject> in
        let data = fileData as! Data
        do {
          try data.write(to: URL(fileURLWithPath: destination))
          return FBFuture(result: destination as NSString as AnyObject)
        } catch {
          return FBFuture(error: error)
        }
      })) as! FBFuture<NSString>
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) -> FBFuture<FBFuture<NSNull>> {
    return FBControlCoreError.describe("-[\(type(of: self)) \(#function)] is not implemented").failFuture() as! FBFuture<FBFuture<NSNull>>
  }

  public func createDirectory(_ directoryPath: String) -> FBFuture<NSNull> {
    return handleAFCOperation { afc in
      try afc.createDirectory(directoryPath)
      return NSNull()
    }
  }

  public func move(from sourcePath: String, to destinationPath: String) -> FBFuture<NSNull> {
    return handleAFCOperation { afc in
      try afc.renamePath(sourcePath, destination: destinationPath)
      return NSNull()
    }
  }

  public func remove(_ path: String) -> FBFuture<NSNull> {
    return handleAFCOperation { afc in
      try afc.removePath(path, recursively: true)
      return NSNull()
    }
  }

  public func contents(ofDirectory path: String) -> FBFuture<NSArray> {
    return handleAFCOperation { afc in
      return try afc.contents(ofDirectory: path) as NSArray
    }
  }

  // MARK: Private

  private func readFileFromPath(inContainer path: String) -> FBFuture<NSData> {
    return handleAFCOperation { afc in
      return try afc.contents(ofPath: path) as NSData
    }
  }

  private func handleAFCOperation<T: AnyObject>(_ operation: @escaping (FBAFCConnection) throws -> T) -> FBFuture<T> {
    return FBFuture.onQueue(queue, resolveValue: { errorPtr in
      do {
        return try operation(self.connection)
      } catch {
        errorPtr?.pointee = error as NSError
        return nil
      }
    }) as! FBFuture<T>
  }

  private static func isDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
  }
}

// MARK: - FBDeviceFileContainer_Wallpaper

private class FBDeviceFileContainer_Wallpaper: NSObject, FBFileContainerProtocol {
  let queue: DispatchQueue
  let springboard: FBSpringboardServicesClient
  let managedConfig: FBManagedConfigClient

  init(springboard: FBSpringboardServicesClient, managedConfig: FBManagedConfigClient, queue: DispatchQueue) {
    self.springboard = springboard
    self.managedConfig = managedConfig
    self.queue = queue
    super.init()
  }

  func contents(ofDirectory path: String) -> FBFuture<NSArray> {
    return FBFuture(result: [FBSpringboardServicesClient.wallpaperNameHomescreen, FBSpringboardServicesClient.wallpaperNameLockscreen] as NSArray)
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) -> FBFuture<NSString> {
    return (springboard.wallpaperImageData(forKind: (sourcePath as NSString).lastPathComponent)
      .onQueue(queue, fmap: { (data: AnyObject) -> FBFuture<AnyObject> in
        let imageData = data as! Data
        do {
          try imageData.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
          return FBFuture(result: destinationPath as NSString as AnyObject)
        } catch {
          return FBFuture(error: error)
        }
      })) as! FBFuture<NSString>
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull> {
    return unsafeBitCast(FBFuture<AnyObject>.onQueue(queue, resolve: { () -> FBFuture<AnyObject> in
      do {
        let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        return self.managedConfig.changeWallpaper(withName: (destinationPath as NSString).lastPathComponent, data: data) as! FBFuture<AnyObject>
      } catch {
        return FBFuture(error: error)
      }
    }), to: FBFuture<NSNull>.self)
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) -> FBFuture<FBFuture<NSNull>> {
    return FBControlCoreError.describe("-[\(type(of: self)) \(#function)] is not implemented").failFuture() as! FBFuture<FBFuture<NSNull>>
  }

  func createDirectory(_ directoryPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Wallpaper File Containers").failFuture() as! FBFuture<NSNull>
  }

  func move(from sourcePath: String, to destinationPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Wallpaper File Containers").failFuture() as! FBFuture<NSNull>
  }

  func remove(_ path: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Wallpaper File Containers").failFuture() as! FBFuture<NSNull>
  }
}

// MARK: - FBDeviceFileContainer_MDMProfiles

private class FBDeviceFileContainer_MDMProfiles: NSObject, FBFileContainerProtocol {
  let queue: DispatchQueue
  let managedConfig: FBManagedConfigClient

  init(managedConfig: FBManagedConfigClient, queue: DispatchQueue) {
    self.managedConfig = managedConfig
    self.queue = queue
    super.init()
  }

  func contents(ofDirectory path: String) -> FBFuture<NSArray> {
    return managedConfig.getProfileList()
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) -> FBFuture<NSString> {
    return FBControlCoreError.describe("\(#function) does not make sense for MDM Profile File Containers").failFuture() as! FBFuture<NSString>
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull> {
    return unsafeBitCast(FBFuture<AnyObject>.onQueue(queue, resolve: { () -> FBFuture<AnyObject> in
      do {
        let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        return self.managedConfig.installProfile(data) as! FBFuture<AnyObject>
      } catch {
        return FBFuture(error: error)
      }
    }), to: FBFuture<NSNull>.self)
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) -> FBFuture<FBFuture<NSNull>> {
    return FBControlCoreError.describe("-[\(type(of: self)) \(#function)] is not implemented").failFuture() as! FBFuture<FBFuture<NSNull>>
  }

  func createDirectory(_ directoryPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for MDM Profile File Containers").failFuture() as! FBFuture<NSNull>
  }

  func move(from sourcePath: String, to destinationPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for MDM Profile File Containers").failFuture() as! FBFuture<NSNull>
  }

  func remove(_ path: String) -> FBFuture<NSNull> {
    return managedConfig.removeProfile(path)
  }
}

// MARK: - FBDeviceFileCommands_DiskImages

private class FBDeviceFileCommands_DiskImages: NSObject, FBFileContainerProtocol {
  let commands: any FBDeveloperDiskImageCommands
  let queue: DispatchQueue

  init(commands: any FBDeveloperDiskImageCommands, queue: DispatchQueue) {
    self.commands = commands
    self.queue = queue
    super.init()
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Disk Images").failFuture() as! FBFuture<NSNull>
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) -> FBFuture<NSString> {
    return FBControlCoreError.describe("\(#function) does not make sense for Disk Images").failFuture() as! FBFuture<NSString>
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) -> FBFuture<FBFuture<NSNull>> {
    return FBControlCoreError.describe("-[\(type(of: self)) \(#function)] is not implemented").failFuture() as! FBFuture<FBFuture<NSNull>>
  }

  func createDirectory(_ directoryPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Disk Images").failFuture() as! FBFuture<NSNull>
  }

  func move(from sourcePath: String, to destinationPath: String) -> FBFuture<NSNull> {
    if !destinationPath.hasPrefix(MountRootPath) {
      return FBDeviceControlError.describe("\(destinationPath) only moving into mounts is supported.").failFuture() as! FBFuture<NSNull>
    }
    let mountableImagesByPath = self.mountableDiskImagesByPath
    guard let image = mountableImagesByPath[sourcePath] else {
      return FBControlCoreError.describe("\(sourcePath) is not one of \(FBCollectionInformation.oneLineDescription(from: mountableImagesByPath.keys.sorted()))").failFuture() as! FBFuture<NSNull>
    }
    return commands.mountDiskImage(image).mapReplace(NSNull()) as! FBFuture<NSNull>
  }

  func remove(_ path: String) -> FBFuture<NSNull> {
    if !path.hasPrefix(MountRootPath) {
      return FBDeviceControlError.describe("\(path) cannot be removed, only mounts can be removed").failFuture() as! FBFuture<NSNull>
    }
    return (mountedDiskImages()
      .onQueue(queue, fmap: { (mountedImagesObj: AnyObject) -> FBFuture<AnyObject> in
        let mountedImages = mountedImagesObj as! [String: FBDeveloperDiskImage]
        guard let image = mountedImages[path] else {
          return FBDeviceControlError.describe("\(path) is not one of the available mounts \(FBCollectionInformation.oneLineDescription(from: Array(mountedImages.keys)))").failFuture()
        }
        return self.commands.unmountDiskImage(image) as! FBFuture<AnyObject>
      })) as! FBFuture<NSNull>
  }

  func contents(ofDirectory path: String) -> FBFuture<NSArray> {
    return (allDiskImagePaths()
      .onQueue(queue, map: { (diskImagePathsObj: AnyObject) -> AnyObject in
        let diskImagePaths = diskImagePathsObj as! [String]
        let traversedPaths = FBDeviceFileCommands_DiskImages.traverseAndDescendPaths(diskImagePaths, path: path)
        return traversedPaths as NSArray as AnyObject
      })) as! FBFuture<NSArray>
  }

  // MARK: Private

  private var mountableDiskImagesByPath: [String: FBDeveloperDiskImage] {
    let images = commands.mountableDiskImages()
    var mapping: [String: FBDeveloperDiskImage] = [:]
    for image in images {
      mapping[FBDeviceFileCommands_DiskImages.filePath(for: image)] = image
    }
    return mapping
  }

  private func mountedDiskImages() -> FBFuture<NSDictionary> {
    return (commands.mountedDiskImages()
      .onQueue(queue, map: { (mountedImagesObj: AnyObject) -> AnyObject in
        let mountedImages = mountedImagesObj as! [FBDeveloperDiskImage]
        var imagesByPath: [String: FBDeveloperDiskImage] = [:]
        for image in mountedImages {
          let mountedFilePath = (MountRootPath as NSString).appendingPathComponent(FBDeviceFileCommands_DiskImages.filePath(for: image))
          imagesByPath[mountedFilePath] = image
        }
        return imagesByPath as NSDictionary as AnyObject
      })) as! FBFuture<NSDictionary>
  }

  private func allDiskImagePaths() -> FBFuture<NSArray> {
    return (mountedDiskImages()
      .onQueue(queue, map: { (mountedDiskImagesObj: AnyObject) -> AnyObject in
        let mountedDiskImages = mountedDiskImagesObj as! [String: FBDeveloperDiskImage]
        var paths: [String] = []
        let sortedKeys = self.mountableDiskImagesByPath.sorted { pair1, pair2 in
          let v1 = pair1.value.version
          let v2 = pair2.value.version
          if v1.majorVersion != v2.majorVersion { return v1.majorVersion < v2.majorVersion }
          return v1.minorVersion < v2.minorVersion
        }.map { $0.key }
        paths.append(contentsOf: sortedKeys)
        paths.append(MountRootPath)
        paths.append(contentsOf: mountedDiskImages.keys)
        return paths as NSArray as AnyObject
      })) as! FBFuture<NSArray>
  }

  static func traverseAndDescendPaths(_ paths: [String], path: String) -> [String] {
    let pathComponents = (path as NSString).pathComponents
    let firstPath = pathComponents.first
    if pathComponents.count == 1 && (firstPath == "." || firstPath == "/") {
      return paths
    }
    var traversedPaths: [String] = []
    for candidatePath in paths {
      if !candidatePath.hasPrefix(path) {
        continue
      }
      var relativePath = String(candidatePath.dropFirst(path.count))
      if relativePath.hasPrefix("/") {
        relativePath = String(relativePath.dropFirst())
      }
      traversedPaths.append(relativePath)
    }
    return traversedPaths
  }

  static func filePath(for image: FBDeveloperDiskImage) -> String {
    return "\(image.version.majorVersion).\(image.version.minorVersion)/\((image.diskImagePath as NSString).lastPathComponent)"
  }
}

// MARK: - FBDeviceFileCommands_Symbols

private class FBDeviceFileCommands_Symbols: NSObject, FBFileContainerProtocol {
  let commands: any FBDeviceDebugSymbolsCommandsProtocol
  let queue: DispatchQueue

  init(commands: any FBDeviceDebugSymbolsCommandsProtocol, queue: DispatchQueue) {
    self.commands = commands
    self.queue = queue
    super.init()
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Symbols").failFuture() as! FBFuture<NSNull>
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) -> FBFuture<NSString> {
    if sourcePath == ExtractedSymbolsDirectory {
      return commands.pullAndExtractSymbols(toDestinationDirectory: destinationPath)
    }
    return commands.pullSymbolFile(sourcePath, toDestinationPath: destinationPath)
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) -> FBFuture<FBFuture<NSNull>> {
    return FBControlCoreError.describe("\(#function) does not make sense for Symbols").failFuture() as! FBFuture<FBFuture<NSNull>>
  }

  func createDirectory(_ directoryPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Symbols").failFuture() as! FBFuture<NSNull>
  }

  func move(from sourcePath: String, to destinationPath: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Symbols").failFuture() as! FBFuture<NSNull>
  }

  func remove(_ path: String) -> FBFuture<NSNull> {
    return FBControlCoreError.describe("\(#function) does not make sense for Symbols").failFuture() as! FBFuture<NSNull>
  }

  func contents(ofDirectory path: String) -> FBFuture<NSArray> {
    return (commands.listSymbols()
      .onQueue(queue, map: { (listedSymbolsObj: AnyObject) -> AnyObject in
        let listedSymbols = listedSymbolsObj as! [String]
        return (listedSymbols + [ExtractedSymbolsDirectory]) as NSArray as AnyObject
      })) as! FBFuture<NSArray>
  }
}

// MARK: - FBDeviceFileCommands

@objc(FBDeviceFileCommands)
public class FBDeviceFileCommands: NSObject, FBFileCommands {
  private weak var device: FBDevice?
  private let afcCalls: AFCCalls

  // MARK: Initializers

  @objc public class func commands(with target: any FBiOSTarget) -> Self {
    return unsafeDowncast(FBDeviceFileCommands(device: target as! FBDevice, afcCalls: FBAFCConnection.defaultCalls), to: self)
  }

  @objc public class func commands(with target: any FBiOSTarget, afcCalls: AFCCalls) -> Self {
    return unsafeDowncast(FBDeviceFileCommands(device: target as! FBDevice, afcCalls: afcCalls), to: self)
  }

  init(device: FBDevice, afcCalls: AFCCalls) {
    self.device = device
    self.afcCalls = afcCalls
    super.init()
  }

  // MARK: FBFileCommands

  public func fileCommands(forContainerApplication bundleID: String) -> FBFutureContext<any FBFileContainerProtocol> {
    return device!.houseArrestAFCConnection(forBundleID: bundleID, afcCalls: afcCalls)
      .onQueue(device!.asyncQueue, pend: { (connection: AnyObject) -> FBFuture<AnyObject> in
        let conn = connection as! FBAFCConnection
        return FBFuture(result: FBDeviceFileContainer(afcConnection: conn, queue: self.device!.asyncQueue) as AnyObject)
      }) as! FBFutureContext<any FBFileContainerProtocol>
  }

  public func fileCommandsForAuxillary() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBFutureContext(result: FBFileContainer.fileContainer(forBasePath: device!.auxillaryDirectory))
  }

  public func fileCommandsForApplicationContainers() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBControlCoreError.describe("\(#function) not supported on devices, requires a rooted device").failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  public func fileCommandsForGroupContainers() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBControlCoreError.describe("\(#function) not supported on devices, requires a rooted device").failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  public func fileCommandsForRootFilesystem() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBControlCoreError.describe("\(#function) not supported on devices, requires a rooted device").failFutureContext() as! FBFutureContext<any FBFileContainerProtocol>
  }

  public func fileCommandsForMediaDirectory() -> FBFutureContext<any FBFileContainerProtocol> {
    return device!.startAFCService("com.apple.afc")
      .onQueue(device!.asyncQueue, pend: { (connection: AnyObject) -> FBFuture<AnyObject> in
        let conn = connection as! FBAFCConnection
        return FBFuture(result: FBDeviceFileContainer(afcConnection: conn, queue: self.device!.asyncQueue) as AnyObject)
      }) as! FBFutureContext<any FBFileContainerProtocol>
  }

  public func fileCommandsForProvisioningProfiles() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBFutureContext(result: FBFileContainer.fileContainer(for: FBDeviceProvisioningProfileCommands.commands(with: device!), queue: device!.workQueue))
  }

  public func fileCommandsForMDMProfiles() -> FBFutureContext<any FBFileContainerProtocol> {
    return device!.startService(FBManagedConfigClient.serviceName)
      .onQueue(device!.asyncQueue, pend: { (connection: AnyObject) -> FBFuture<AnyObject> in
        let conn = connection as! FBAMDServiceConnection
        let managedConfig = FBManagedConfigClient.managedConfigClient(connection: conn, logger: self.device!.logger!)
        return FBFuture(result: FBDeviceFileContainer_MDMProfiles(managedConfig: managedConfig, queue: self.device!.workQueue) as AnyObject)
      }) as! FBFutureContext<any FBFileContainerProtocol>
  }

  public func fileCommandsForSpringboardIconLayout() -> FBFutureContext<any FBFileContainerProtocol> {
    return device!.startService(FBSpringboardServicesClient.serviceName)
      .onQueue(device!.asyncQueue, pend: { (connection: AnyObject) -> FBFuture<AnyObject> in
        let conn = connection as! FBAMDServiceConnection
        return FBFuture(result: FBSpringboardServicesClient.springboardServicesClient(connection: conn, logger: self.device!.logger!).iconContainer() as AnyObject)
      }) as! FBFutureContext<any FBFileContainerProtocol>
  }

  public func fileCommandsForWallpaper() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBFutureContext(futureContexts: [
        unsafeBitCast(device!.startService(FBSpringboardServicesClient.serviceName), to: FBFutureContext<AnyObject>.self),
        unsafeBitCast(device!.startService(FBManagedConfigClient.serviceName), to: FBFutureContext<AnyObject>.self),
      ])
      .onQueue(device!.asyncQueue, pend: { (connections: AnyObject) -> FBFuture<AnyObject> in
        let conns = connections as! NSArray
        let springboard = FBSpringboardServicesClient.springboardServicesClient(connection: conns[0] as! FBAMDServiceConnection, logger: self.device!.logger!)
        let managedConfig = FBManagedConfigClient.managedConfigClient(connection: conns[1] as! FBAMDServiceConnection, logger: self.device!.logger!)
        return FBFuture(result: FBDeviceFileContainer_Wallpaper(springboard: springboard, managedConfig: managedConfig, queue: self.device!.workQueue) as AnyObject)
      }) as! FBFutureContext<any FBFileContainerProtocol>
  }

  public func fileCommandsForDiskImages() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBFutureContext(result: FBDeviceFileCommands_DiskImages(commands: device! as any FBDeveloperDiskImageCommands, queue: device!.asyncQueue) as any FBFileContainerProtocol)
  }

  public func fileCommandsForSymbols() -> FBFutureContext<any FBFileContainerProtocol> {
    return FBFutureContext(result: FBDeviceFileCommands_Symbols(commands: device! as any FBDeviceDebugSymbolsCommandsProtocol, queue: device!.asyncQueue) as any FBFileContainerProtocol)
  }
}
