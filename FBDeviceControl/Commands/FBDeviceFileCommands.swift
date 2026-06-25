/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let MountRootPath = "mounted"
private let ExtractedSymbolsDirectory = "Symbols"

/// Carries a non-`Sendable` `FBAFCConnection` across the serial-queue boundary.
/// The wrapped value is only ever touched on the owning serial queue.
private final class AFCConnectionBox: @unchecked Sendable {
  let connection: FBAFCConnection
  init(_ connection: FBAFCConnection) {
    self.connection = connection
  }
}

// MARK: - FBDeviceFileContainer

@objc(FBDeviceFileContainer)
public class FBDeviceFileContainer: NSObject, AsyncFileContainer {
  private let queue: DispatchQueue
  private let connectionBox: AFCConnectionBox

  @objc public init(afcConnection connection: FBAFCConnection, queue: DispatchQueue) {
    self.connectionBox = AFCConnectionBox(connection)
    self.queue = queue
    super.init()
  }

  // MARK: AsyncFileContainer

  public func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let box = connectionBox
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          try box.connection.copy(fromHost: sourcePath, toContainerPath: destinationPath)
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    var destination = destinationPath
    if FBDeviceFileContainer.isDirectory(destinationPath) {
      destination = (destinationPath as NSString).appendingPathComponent((sourcePath as NSString).lastPathComponent)
    }
    let data = try await readFile(inContainer: sourcePath)
    try data.write(to: URL(fileURLWithPath: destination))
    return destination
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation {
    throw FBControlCoreError.describe("tail is not implemented for FBDeviceFileContainer").build()
  }

  public func createDirectory(_ directoryPath: String) async throws {
    let box = connectionBox
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          try box.connection.createDirectory(directoryPath)
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func move(from sourcePath: String, to destinationPath: String) async throws {
    let box = connectionBox
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          try box.connection.renamePath(sourcePath, destination: destinationPath)
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func remove(_ path: String) async throws {
    let box = connectionBox
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          try box.connection.removePath(path, recursively: true)
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func contents(ofDirectory path: String) async throws -> [String] {
    let box = connectionBox
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
      queue.async {
        do {
          continuation.resume(returning: try box.connection.contents(ofDirectory: path))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  // MARK: Private

  private func readFile(inContainer path: String) async throws -> Data {
    let box = connectionBox
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
      queue.async {
        do {
          continuation.resume(returning: try box.connection.contents(ofPath: path))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func isDirectory(_ path: String) -> Bool {
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
  }
}

// MARK: - FBDeviceFileContainer_Wallpaper

private class FBDeviceFileContainer_Wallpaper: NSObject, AsyncFileContainer {
  let queue: DispatchQueue
  let springboard: FBSpringboardServicesClient
  let managedConfig: FBManagedConfigClient

  init(springboard: FBSpringboardServicesClient, managedConfig: FBManagedConfigClient, queue: DispatchQueue) {
    self.springboard = springboard
    self.managedConfig = managedConfig
    self.queue = queue
    super.init()
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    try await bridgeFBFutureVoid(managedConfig.changeWallpaper(withName: (destinationPath as NSString).lastPathComponent, data: data))
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    let imageData = try await bridgeFBFuture(springboard.wallpaperImageData(forKind: (sourcePath as NSString).lastPathComponent)) as Data
    try imageData.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
    return destinationPath
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation {
    throw FBControlCoreError.describe("tail is not supported for Wallpaper File Containers").build()
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Wallpaper File Containers").build()
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Wallpaper File Containers").build()
  }

  func remove(_ path: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Wallpaper File Containers").build()
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    [FBSpringboardServicesClient.wallpaperNameHomescreen, FBSpringboardServicesClient.wallpaperNameLockscreen]
  }
}

// MARK: - FBDeviceFileContainer_MDMProfiles

private class FBDeviceFileContainer_MDMProfiles: NSObject, AsyncFileContainer {
  let queue: DispatchQueue
  let managedConfig: FBManagedConfigClient

  init(managedConfig: FBManagedConfigClient, queue: DispatchQueue) {
    self.managedConfig = managedConfig
    self.queue = queue
    super.init()
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    _ = try await bridgeFBFuture(managedConfig.installProfile(data))
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    throw FBControlCoreError.describe("\(#function) does not make sense for MDM Profile File Containers").build()
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation {
    throw FBControlCoreError.describe("tail is not supported for MDM Profile File Containers").build()
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for MDM Profile File Containers").build()
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for MDM Profile File Containers").build()
  }

  func remove(_ path: String) async throws {
    try await bridgeFBFutureVoid(managedConfig.removeProfile(path))
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    try await bridgeFBFutureArray(managedConfig.getProfileList()) as [String]
  }
}

// MARK: - FBDeviceFileCommands_DiskImages

private class FBDeviceFileCommands_DiskImages: NSObject, AsyncFileContainer {
  let commands: any DeveloperDiskImageCommands
  let queue: DispatchQueue

  init(commands: any DeveloperDiskImageCommands, queue: DispatchQueue) {
    self.commands = commands
    self.queue = queue
    super.init()
  }

  // MARK: AsyncFileContainer

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Disk Images").build()
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    throw FBControlCoreError.describe("\(#function) does not make sense for Disk Images").build()
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation {
    throw FBControlCoreError.describe("tail is not supported for Disk Images").build()
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Disk Images").build()
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    if !destinationPath.hasPrefix(MountRootPath) {
      throw FBDeviceControlError.describe("\(destinationPath) only moving into mounts is supported.").build()
    }
    let mountableImagesByPath = self.mountableDiskImagesByPath
    guard let image = mountableImagesByPath[sourcePath] else {
      throw FBControlCoreError.describe("\(sourcePath) is not one of \(FBCollectionInformation.oneLineDescription(from: mountableImagesByPath.keys.sorted()))").build()
    }
    _ = try await commands.mountDiskImage(image)
  }

  func remove(_ path: String) async throws {
    if !path.hasPrefix(MountRootPath) {
      throw FBDeviceControlError.describe("\(path) cannot be removed, only mounts can be removed").build()
    }
    let mountedImages = try await mountedDiskImagesAsync()
    guard let image = mountedImages[path] else {
      throw FBDeviceControlError.describe("\(path) is not one of the available mounts \(FBCollectionInformation.oneLineDescription(from: Array(mountedImages.keys)))").build()
    }
    try await commands.unmountDiskImage(image)
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    let diskImagePaths = try await allDiskImagePathsAsync()
    return FBDeviceFileCommands_DiskImages.traverseAndDescendPaths(diskImagePaths, path: path)
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

  private func mountedDiskImagesAsync() async throws -> [String: FBDeveloperDiskImage] {
    let mountedImages = try await commands.mountedDiskImages()
    var imagesByPath: [String: FBDeveloperDiskImage] = [:]
    for image in mountedImages {
      let mountedFilePath = (MountRootPath as NSString).appendingPathComponent(FBDeviceFileCommands_DiskImages.filePath(for: image))
      imagesByPath[mountedFilePath] = image
    }
    return imagesByPath
  }

  private func allDiskImagePathsAsync() async throws -> [String] {
    let mountedDiskImages = try await mountedDiskImagesAsync()
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
    return paths
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
    "\(image.version.majorVersion).\(image.version.minorVersion)/\((image.diskImagePath as NSString).lastPathComponent)"
  }
}

// MARK: - FBDeviceFileCommands_Symbols

private class FBDeviceFileCommands_Symbols: NSObject, AsyncFileContainer {
  let commands: any DebugSymbolsCommands
  let queue: DispatchQueue

  init(commands: any DebugSymbolsCommands, queue: DispatchQueue) {
    self.commands = commands
    self.queue = queue
    super.init()
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Symbols").build()
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    if sourcePath == ExtractedSymbolsDirectory {
      return try await commands.pullAndExtractSymbols(toDestinationDirectory: destinationPath)
    }
    return try await commands.pullSymbolFile(sourcePath, toDestinationPath: destinationPath)
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation {
    throw FBControlCoreError.describe("tail is not supported for Symbols").build()
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Symbols").build()
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Symbols").build()
  }

  func remove(_ path: String) async throws {
    throw FBControlCoreError.describe("\(#function) does not make sense for Symbols").build()
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    let listedSymbols = try await commands.listSymbols()
    return listedSymbols + [ExtractedSymbolsDirectory]
  }
}

// MARK: - FBDeviceFileCommands

@objc(FBDeviceFileCommands)
public class FBDeviceFileCommands: NSObject, FBiOSTargetCommand {
  private weak var device: FBDevice?
  private let afcCalls: AFCCalls

  // MARK: Initializers

  @objc public class func commands(with target: any FBiOSTarget) -> Self {
    unsafeDowncast(FBDeviceFileCommands(device: target as! FBDevice, afcCalls: FBAFCConnection.defaultCalls), to: self)
  }

  @objc public class func commands(with target: any FBiOSTarget, afcCalls: AFCCalls) -> Self {
    unsafeDowncast(FBDeviceFileCommands(device: target as! FBDevice, afcCalls: afcCalls), to: self)
  }

  init(device: FBDevice, afcCalls: AFCCalls) {
    self.device = device
    self.afcCalls = afcCalls
    super.init()
  }

  // MARK: FBFileCommands

  fileprivate func fileCommandsForContainerApplication(_ bundleID: String) -> FBFutureContext<FBDeviceFileContainer> {
    device!.houseArrestAFCConnection(forBundleID: bundleID, afcCalls: afcCalls)
      .onQueue(
        device!.asyncQueue,
        pend: { (connection: AnyObject) -> FBFuture<AnyObject> in
          let conn = connection as! FBAFCConnection
          return FBFuture(result: FBDeviceFileContainer(afcConnection: conn, queue: self.device!.asyncQueue) as AnyObject)
        }) as! FBFutureContext<FBDeviceFileContainer>
  }

  fileprivate func fileCommandsForAuxillary() -> FBFutureContext<FBContainedFile_ContainedRoot> {
    // swiftlint:disable:next force_cast force_unwrapping
    FBFutureContext(result: FBFileContainer.fileContainer(forBasePath: device!.auxillaryDirectory) as! FBContainedFile_ContainedRoot)
  }

  fileprivate func fileCommandsForApplicationContainers() -> FBFutureContext<FBDeviceFileContainer> {
    // swiftlint:disable:next force_cast
    FBControlCoreError.describe("\(#function) not supported on devices, requires a rooted device").failFutureContext() as! FBFutureContext<FBDeviceFileContainer>
  }

  fileprivate func fileCommandsForGroupContainers() -> FBFutureContext<FBDeviceFileContainer> {
    // swiftlint:disable:next force_cast
    FBControlCoreError.describe("\(#function) not supported on devices, requires a rooted device").failFutureContext() as! FBFutureContext<FBDeviceFileContainer>
  }

  fileprivate func fileCommandsForRootFilesystem() -> FBFutureContext<FBDeviceFileContainer> {
    // swiftlint:disable:next force_cast
    FBControlCoreError.describe("\(#function) not supported on devices, requires a rooted device").failFutureContext() as! FBFutureContext<FBDeviceFileContainer>
  }

  fileprivate func fileCommandsForMediaDirectory() -> FBFutureContext<FBDeviceFileContainer> {
    device!.startAFCService("com.apple.afc")
      .onQueue(
        device!.asyncQueue,
        pend: { (connection: AnyObject) -> FBFuture<AnyObject> in
          let conn = connection as! FBAFCConnection
          return FBFuture(result: FBDeviceFileContainer(afcConnection: conn, queue: self.device!.asyncQueue) as AnyObject)
        }) as! FBFutureContext<FBDeviceFileContainer>
  }

  fileprivate func fileCommandsForProvisioningProfiles() -> FBFutureContext<FBFileContainer_ProvisioningProfile> {
    // swiftlint:disable:next force_unwrapping
    FBFutureContext(result: FBFileContainer_ProvisioningProfile(commands: FBDeviceProvisioningProfileCommands.commands(with: device!)))
  }

  fileprivate func fileCommandsForMDMProfiles() -> FBFutureContext<FBDeviceFileContainer_MDMProfiles> {
    device!.startService(FBManagedConfigClient.serviceName)
      .onQueue(
        device!.asyncQueue,
        pend: { (connection: AnyObject) -> FBFuture<AnyObject> in
          let conn = connection as! FBAMDServiceConnection
          let managedConfig = FBManagedConfigClient.managedConfigClient(connection: conn, logger: self.device!.logger!)
          return FBFuture(result: FBDeviceFileContainer_MDMProfiles(managedConfig: managedConfig, queue: self.device!.workQueue) as AnyObject)
        }) as! FBFutureContext<FBDeviceFileContainer_MDMProfiles>
  }

  fileprivate func fileCommandsForWallpaper() -> FBFutureContext<FBDeviceFileContainer_Wallpaper> {
    FBFutureContext(futureContexts: [
      unsafeBitCast(device!.startService(FBSpringboardServicesClient.serviceName), to: FBFutureContext<AnyObject>.self),
      unsafeBitCast(device!.startService(FBManagedConfigClient.serviceName), to: FBFutureContext<AnyObject>.self),
    ])
    .onQueue(
      device!.asyncQueue,
      pend: { (connections: AnyObject) -> FBFuture<AnyObject> in
        let conns = connections as! NSArray
        let springboard = FBSpringboardServicesClient.springboardServicesClient(connection: conns[0] as! FBAMDServiceConnection, logger: self.device!.logger!)
        let managedConfig = FBManagedConfigClient.managedConfigClient(connection: conns[1] as! FBAMDServiceConnection, logger: self.device!.logger!)
        return FBFuture(result: FBDeviceFileContainer_Wallpaper(springboard: springboard, managedConfig: managedConfig, queue: self.device!.workQueue) as AnyObject)
      }) as! FBFutureContext<FBDeviceFileContainer_Wallpaper>
  }

  fileprivate func fileCommandsForDiskImages() -> FBFutureContext<FBDeviceFileCommands_DiskImages> {
    // swiftlint:disable:next force_unwrapping
    FBFutureContext(result: FBDeviceFileCommands_DiskImages(commands: device! as any DeveloperDiskImageCommands, queue: device!.asyncQueue))
  }

  fileprivate func fileCommandsForSymbols() -> FBFutureContext<FBDeviceFileCommands_Symbols> {
    // swiftlint:disable:next force_unwrapping
    FBFutureContext(result: FBDeviceFileCommands_Symbols(commands: device! as any DebugSymbolsCommands, queue: device!.asyncQueue))
  }
}

// MARK: - FBDevice+FileCommands

extension FBDevice: FileCommands {

  public func withFileCommandsForContainerApplication<R>(
    _ bundleID: String,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForContainerApplication(bundleID), body: body)
  }

  public func withFileCommandsForAuxillary<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForAuxillary(), body: body)
  }

  public func withFileCommandsForApplicationContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForApplicationContainers(), body: body)
  }

  public func withFileCommandsForGroupContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForGroupContainers(), body: body)
  }

  public func withFileCommandsForRootFilesystem<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForRootFilesystem(), body: body)
  }

  public func withFileCommandsForMediaDirectory<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForMediaDirectory(), body: body)
  }

  public func withFileCommandsForProvisioningProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForProvisioningProfiles(), body: body)
  }

  public func withFileCommandsForMDMProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForMDMProfiles(), body: body)
  }

  public func withFileCommandsForSpringboardIconLayout<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    guard let logger else {
      throw FBDeviceControlError().describe("Device logger is nil").build()
    }
    return try await withFBFutureContext(startService(FBSpringboardServicesClient.serviceName)) { connection in
      let client = FBSpringboardServicesClient.springboardServicesClient(connection: connection, logger: logger)
      return try await body(client.iconContainer())
    }
  }

  public func withFileCommandsForWallpaper<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForWallpaper(), body: body)
  }

  public func withFileCommandsForDiskImages<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForDiskImages(), body: body)
  }

  public func withFileCommandsForSymbols<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForSymbols(), body: body)
  }

  /// Scopes the file container to `body`, exposing it through the
  /// `AsyncFileContainer` async API.
  private func withFileContainer<C: AsyncFileContainer, R>(
    _ context: FBFutureContext<C>,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFBFutureContext(context) { container in
      try await body(container)
    }
  }
}
