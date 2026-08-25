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

// MARK: - FBDeviceFileContainerError

/// The ways device file-container operations can fail, as data rather than assembled strings.
public enum FBDeviceFileContainerError: Error {
  case deviceDeallocated
  case tailNotImplemented
  case tailUnsupported(container: String)
  case operationUnsupported(operation: String, container: String)
  case moveOutsideMounts(destination: String)
  case notAMountableImage(path: String, available: [String])
  case removeOutsideMounts(path: String)
  case notAMountedImage(path: String, available: [String])
  case unexpectedServiceConnections(description: String)
  case requiresRootedDevice(operation: String)
}

extension FBDeviceFileContainerError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .deviceDeallocated:
      return "The device that these file commands were created for has been deallocated"
    case .tailNotImplemented:
      return "tail is not implemented for FBDeviceFileContainer"
    case let .tailUnsupported(container):
      return "tail is not supported for \(container)"
    case let .operationUnsupported(operation, container):
      return "\(operation) does not make sense for \(container)"
    case let .moveOutsideMounts(destination):
      return "\(destination) only moving into mounts is supported."
    case let .notAMountableImage(path, available):
      return "\(path) is not one of \(FBCollectionInformation.oneLineDescription(from: available))"
    case let .removeOutsideMounts(path):
      return "\(path) cannot be removed, only mounts can be removed"
    case let .notAMountedImage(path, available):
      return "\(path) is not one of the available mounts \(FBCollectionInformation.oneLineDescription(from: available))"
    case let .unexpectedServiceConnections(description):
      return "Expected the springboard and managed configuration connections, got \(description)"
    case let .requiresRootedDevice(operation):
      return "\(operation) not supported on devices, requires a rooted device"
    }
  }
}

// MARK: - FBDeviceFileContainer

public class FBDeviceFileContainer: AsyncFileContainer {
  private let queue: DispatchQueue
  private let connectionBox: AFCConnectionBox

  public init(afcConnection connection: FBAFCConnection, queue: DispatchQueue) {
    self.connectionBox = AFCConnectionBox(connection)
    self.queue = queue
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

  public func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw FBDeviceFileContainerError.tailNotImplemented
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

private class FBDeviceFileContainer_Wallpaper: AsyncFileContainer {
  let queue: DispatchQueue
  let springboard: FBSpringboardServicesClient
  let managedConfig: FBManagedConfigClient

  init(springboard: FBSpringboardServicesClient, managedConfig: FBManagedConfigClient, queue: DispatchQueue) {
    self.springboard = springboard
    self.managedConfig = managedConfig
    self.queue = queue
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

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw FBDeviceFileContainerError.tailUnsupported(container: "Wallpaper File Containers")
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Wallpaper File Containers")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Wallpaper File Containers")
  }

  func remove(_ path: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Wallpaper File Containers")
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    [FBSpringboardServicesClient.wallpaperNameHomescreen, FBSpringboardServicesClient.wallpaperNameLockscreen]
  }
}

// MARK: - FBDeviceFileContainer_MDMProfiles

private class FBDeviceFileContainer_MDMProfiles: AsyncFileContainer {
  let queue: DispatchQueue
  let managedConfig: FBManagedConfigClient

  init(managedConfig: FBManagedConfigClient, queue: DispatchQueue) {
    self.managedConfig = managedConfig
    self.queue = queue
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    _ = try await bridgeFBFuture(managedConfig.installProfile(data))
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "MDM Profile File Containers")
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw FBDeviceFileContainerError.tailUnsupported(container: "MDM Profile File Containers")
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "MDM Profile File Containers")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "MDM Profile File Containers")
  }

  func remove(_ path: String) async throws {
    try await bridgeFBFutureVoid(managedConfig.removeProfile(path))
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    try await bridgeFBFutureArray(managedConfig.getProfileList()) as [String]
  }
}

// MARK: - FBDeviceFileCommands_DiskImages

private class FBDeviceFileCommands_DiskImages: AsyncFileContainer {
  let commands: any DeveloperDiskImageCommands
  let queue: DispatchQueue

  init(commands: any DeveloperDiskImageCommands, queue: DispatchQueue) {
    self.commands = commands
    self.queue = queue
  }

  // MARK: AsyncFileContainer

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Disk Images")
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Disk Images")
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw FBDeviceFileContainerError.tailUnsupported(container: "Disk Images")
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Disk Images")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    if !destinationPath.hasPrefix(MountRootPath) {
      throw FBDeviceFileContainerError.moveOutsideMounts(destination: destinationPath)
    }
    let mountableImagesByPath = self.mountableDiskImagesByPath
    guard let image = mountableImagesByPath[sourcePath] else {
      throw FBDeviceFileContainerError.notAMountableImage(path: sourcePath, available: mountableImagesByPath.keys.sorted())
    }
    _ = try await commands.mountDiskImage(image)
  }

  func remove(_ path: String) async throws {
    if !path.hasPrefix(MountRootPath) {
      throw FBDeviceFileContainerError.removeOutsideMounts(path: path)
    }
    let mountedImages = try await mountedDiskImagesAsync()
    guard let image = mountedImages[path] else {
      throw FBDeviceFileContainerError.notAMountedImage(path: path, available: Array(mountedImages.keys))
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

private class FBDeviceFileCommands_Symbols: AsyncFileContainer {
  let commands: any DebugSymbolsCommands
  let queue: DispatchQueue

  init(commands: any DebugSymbolsCommands, queue: DispatchQueue) {
    self.commands = commands
    self.queue = queue
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Symbols")
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    if sourcePath == ExtractedSymbolsDirectory {
      return try await commands.pullAndExtractSymbols(toDestinationDirectory: destinationPath)
    }
    return try await commands.pullSymbolFile(sourcePath, toDestinationPath: destinationPath)
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw FBDeviceFileContainerError.tailUnsupported(container: "Symbols")
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Symbols")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Symbols")
  }

  func remove(_ path: String) async throws {
    throw FBDeviceFileContainerError.operationUnsupported(operation: #function, container: "Symbols")
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    let listedSymbols = try await commands.listSymbols()
    return listedSymbols + [ExtractedSymbolsDirectory]
  }
}

// MARK: - FBDeviceFileCommands

public class FBDeviceFileCommands {
  private weak var device: FBDevice?
  private let afcCalls: AFCCalls

  // MARK: Initializers

  public class func commands(with device: FBDevice) -> FBDeviceFileCommands {
    FBDeviceFileCommands(device: device, afcCalls: FBAFCConnection.defaultCalls)
  }

  public class func commands(with device: FBDevice, afcCalls: AFCCalls) -> FBDeviceFileCommands {
    FBDeviceFileCommands(device: device, afcCalls: afcCalls)
  }

  init(device: FBDevice, afcCalls: AFCCalls) {
    self.device = device
    self.afcCalls = afcCalls
  }

  // MARK: FBFileCommands

  private func requireDevice() throws -> FBDevice {
    guard let device else {
      throw FBDeviceFileContainerError.deviceDeallocated
    }
    return device
  }

  fileprivate func fileCommandsForContainerApplication(_ bundleID: String) throws -> FBFutureContext<FBDeviceFileContainer> {
    let device = try requireDevice()
    let queue = device.asyncQueue
    return
      device
      .houseArrestAFCConnection(forBundleID: bundleID, afcCalls: afcCalls)
      .onQueue(
        queue,
        pend: { connection -> FBFuture<AnyObject> in
          FBFuture(result: FBDeviceFileContainer(afcConnection: connection, queue: queue) as AnyObject)
        }
      ).retyped(FBFutureContext<FBDeviceFileContainer>.self)
  }

  fileprivate func fileCommandsForAuxillary() throws -> FBContainedFile_ContainedRoot {
    let device = try requireDevice()
    return FBFileContainer.fileContainer(forBasePath: device.auxillaryDirectory)
  }

  fileprivate func fileCommandsForMediaDirectory() throws -> FBFutureContext<FBDeviceFileContainer> {
    let device = try requireDevice()
    let queue = device.asyncQueue
    return
      device
      .startAFCService("com.apple.afc")
      .onQueue(
        queue,
        pend: { connection -> FBFuture<AnyObject> in
          FBFuture(result: FBDeviceFileContainer(afcConnection: connection, queue: queue) as AnyObject)
        }
      ).retyped(FBFutureContext<FBDeviceFileContainer>.self)
  }

  fileprivate func fileCommandsForProvisioningProfiles() throws -> FBFileContainer_ProvisioningProfile {
    let device = try requireDevice()
    return FBFileContainer_ProvisioningProfile(commands: FBDeviceProvisioningProfileCommands.commands(with: device))
  }

  fileprivate func fileCommandsForMDMProfiles() throws -> FBFutureContext<FBDeviceFileContainer_MDMProfiles> {
    let device = try requireDevice()
    let logger = device.logger
    let workQueue = device.workQueue
    return
      device
      .startService(FBManagedConfigClient.serviceName)
      .onQueue(
        device.asyncQueue,
        pend: { connection -> FBFuture<AnyObject> in
          let managedConfig = FBManagedConfigClient.managedConfigClient(connection: connection, logger: logger)
          return FBFuture(result: FBDeviceFileContainer_MDMProfiles(managedConfig: managedConfig, queue: workQueue) as AnyObject)
        }
      ).retyped(FBFutureContext<FBDeviceFileContainer_MDMProfiles>.self)
  }

  fileprivate func fileCommandsForWallpaper() throws -> FBFutureContext<FBDeviceFileContainer_Wallpaper> {
    let device = try requireDevice()
    let logger = device.logger
    let workQueue = device.workQueue
    return FBFutureContext(futureContexts: [
      device.startService(FBSpringboardServicesClient.serviceName).retyped(FBFutureContext<AnyObject>.self),
      device.startService(FBManagedConfigClient.serviceName).retyped(FBFutureContext<AnyObject>.self),
    ])
    .onQueue(
      device.asyncQueue,
      pend: { (started: NSArray) -> FBFuture<AnyObject> in
        guard let connections = started as? [FBAMDServiceConnection], connections.count == 2 else {
          return FBFuture(error: FBDeviceFileContainerError.unexpectedServiceConnections(description: String(describing: started)))
        }
        let springboard = FBSpringboardServicesClient.springboardServicesClient(connection: connections[0], logger: logger)
        let managedConfig = FBManagedConfigClient.managedConfigClient(connection: connections[1], logger: logger)
        return FBFuture(result: FBDeviceFileContainer_Wallpaper(springboard: springboard, managedConfig: managedConfig, queue: workQueue) as AnyObject)
      }
    ).retyped(FBFutureContext<FBDeviceFileContainer_Wallpaper>.self)
  }

  fileprivate func fileCommandsForDiskImages() throws -> FBDeviceFileCommands_DiskImages {
    let device = try requireDevice()
    return FBDeviceFileCommands_DiskImages(commands: device as any DeveloperDiskImageCommands, queue: device.asyncQueue)
  }

  fileprivate func fileCommandsForSymbols() throws -> FBDeviceFileCommands_Symbols {
    let device = try requireDevice()
    return FBDeviceFileCommands_Symbols(commands: device as any DebugSymbolsCommands, queue: device.asyncQueue)
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
    try await body(fileCommands().fileCommandsForAuxillary())
  }

  public func withFileCommandsForApplicationContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw FBDeviceFileContainerError.requiresRootedDevice(operation: #function)
  }

  public func withFileCommandsForGroupContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw FBDeviceFileContainerError.requiresRootedDevice(operation: #function)
  }

  public func withFileCommandsForRootFilesystem<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw FBDeviceFileContainerError.requiresRootedDevice(operation: #function)
  }

  public func withFileCommandsForMediaDirectory<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForMediaDirectory(), body: body)
  }

  public func withFileCommandsForProvisioningProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await body(fileCommands().fileCommandsForProvisioningProfiles())
  }

  public func withFileCommandsForMDMProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await withFileContainer(fileCommands().fileCommandsForMDMProfiles(), body: body)
  }

  public func withFileCommandsForSpringboardIconLayout<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
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
    try await body(fileCommands().fileCommandsForDiskImages())
  }

  public func withFileCommandsForSymbols<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await body(fileCommands().fileCommandsForSymbols())
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
