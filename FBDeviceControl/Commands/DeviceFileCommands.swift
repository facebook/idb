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

/// Carries the non-`Sendable` connection across the serial-queue boundary; only touched on that queue.
private final class AFCConnectionBox: @unchecked Sendable {
  let connection: FBAFCConnection
  init(_ connection: FBAFCConnection) {
    self.connection = connection
  }
}

// MARK: - DeviceFileContainerError

public enum DeviceFileContainerError: Error {
  case deviceDeallocated
  case tailNotImplemented
  case tailUnsupported(container: String)
  case operationUnsupported(operation: String, container: String)
  case moveOutsideMounts(destination: String)
  case notAMountableImage(path: String, available: [String])
  case removeOutsideMounts(path: String)
  case notAMountedImage(path: String, available: [String])
  case requiresRootedDevice(operation: String)
}

extension DeviceFileContainerError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .deviceDeallocated:
      return "The device that these file commands were created for has been deallocated"
    case .tailNotImplemented:
      return "tail is not implemented for DeviceFileContainer"
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
    case let .requiresRootedDevice(operation):
      return "\(operation) not supported on devices, requires a rooted device"
    }
  }
}

// MARK: - DeviceFileContainer

public final class DeviceFileContainer: AsyncFileContainer {
  private let queue: DispatchQueue
  private let connectionBox: AFCConnectionBox

  public init(afcConnection connection: FBAFCConnection, queue: DispatchQueue) {
    self.connectionBox = AFCConnectionBox(connection)
    self.queue = queue
  }

  // MARK: - AsyncFileContainer

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
    if DeviceFileContainer.isDirectory(destinationPath) {
      destination = (destinationPath as NSString).appendingPathComponent((sourcePath as NSString).lastPathComponent)
    }
    let data = try await readFile(inContainer: sourcePath)
    try data.write(to: URL(fileURLWithPath: destination))
    return destination
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw DeviceFileContainerError.tailNotImplemented
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

  // MARK: - Private

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

// MARK: - DeviceFileContainer_Wallpaper

private class DeviceFileContainer_Wallpaper: AsyncFileContainer {
  let queue: DispatchQueue
  let springboard: SpringboardServicesClient
  let managedConfig: ManagedConfigClient

  init(springboard: SpringboardServicesClient, managedConfig: ManagedConfigClient, queue: DispatchQueue) {
    self.springboard = springboard
    self.managedConfig = managedConfig
    self.queue = queue
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    try await managedConfig.changeWallpaper(name: (destinationPath as NSString).lastPathComponent, data: data)
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    let imageData = try await springboard.wallpaperImageData(forKind: (sourcePath as NSString).lastPathComponent)
    try imageData.write(to: URL(fileURLWithPath: destinationPath), options: .atomic)
    return destinationPath
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw DeviceFileContainerError.tailUnsupported(container: "Wallpaper File Containers")
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Wallpaper File Containers")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Wallpaper File Containers")
  }

  func remove(_ path: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Wallpaper File Containers")
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    [SpringboardServicesClient.wallpaperNameHomescreen, SpringboardServicesClient.wallpaperNameLockscreen]
  }
}

// MARK: - DeviceFileContainer_MDMProfiles

private class DeviceFileContainer_MDMProfiles: AsyncFileContainer {
  let queue: DispatchQueue
  let managedConfig: ManagedConfigClient

  init(managedConfig: ManagedConfigClient, queue: DispatchQueue) {
    self.managedConfig = managedConfig
    self.queue = queue
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    _ = try await managedConfig.installProfile(data)
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "MDM Profile File Containers")
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw DeviceFileContainerError.tailUnsupported(container: "MDM Profile File Containers")
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "MDM Profile File Containers")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "MDM Profile File Containers")
  }

  func remove(_ path: String) async throws {
    try await managedConfig.removeProfile(path)
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    try await managedConfig.getProfileList()
  }
}

// MARK: - DeviceFileCommands_DiskImages

private class DeviceFileCommands_DiskImages: AsyncFileContainer {
  let commands: any DeveloperDiskImageCommands
  let queue: DispatchQueue

  init(commands: any DeveloperDiskImageCommands, queue: DispatchQueue) {
    self.commands = commands
    self.queue = queue
  }

  // MARK: - AsyncFileContainer

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Disk Images")
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Disk Images")
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw DeviceFileContainerError.tailUnsupported(container: "Disk Images")
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Disk Images")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    if !destinationPath.hasPrefix(MountRootPath) {
      throw DeviceFileContainerError.moveOutsideMounts(destination: destinationPath)
    }
    let mountableImagesByPath = self.mountableDiskImagesByPath
    guard let image = mountableImagesByPath[sourcePath] else {
      throw DeviceFileContainerError.notAMountableImage(path: sourcePath, available: mountableImagesByPath.keys.sorted())
    }
    _ = try await commands.mountDiskImage(image)
  }

  func remove(_ path: String) async throws {
    if !path.hasPrefix(MountRootPath) {
      throw DeviceFileContainerError.removeOutsideMounts(path: path)
    }
    let mountedImages = try await mountedDiskImages()
    guard let image = mountedImages[path] else {
      throw DeviceFileContainerError.notAMountedImage(path: path, available: Array(mountedImages.keys))
    }
    try await commands.unmountDiskImage(image)
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    let diskImagePaths = try await allDiskImagePaths()
    return DeviceFileCommands_DiskImages.traverseAndDescendPaths(diskImagePaths, path: path)
  }

  // MARK: - Private

  private var mountableDiskImagesByPath: [String: FBDeveloperDiskImage] {
    let images = commands.mountableDiskImages()
    var mapping: [String: FBDeveloperDiskImage] = [:]
    for image in images {
      mapping[DeviceFileCommands_DiskImages.filePath(for: image)] = image
    }
    return mapping
  }

  private func mountedDiskImages() async throws -> [String: FBDeveloperDiskImage] {
    let mountedImages = try await commands.mountedDiskImages()
    var imagesByPath: [String: FBDeveloperDiskImage] = [:]
    for image in mountedImages {
      let mountedFilePath = (MountRootPath as NSString).appendingPathComponent(DeviceFileCommands_DiskImages.filePath(for: image))
      imagesByPath[mountedFilePath] = image
    }
    return imagesByPath
  }

  private func allDiskImagePaths() async throws -> [String] {
    let mountedDiskImages = try await mountedDiskImages()
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

// MARK: - DeviceFileCommands_Symbols

private class DeviceFileCommands_Symbols: AsyncFileContainer {
  let commands: DeviceDebugSymbolsCommands
  let queue: DispatchQueue

  init(commands: DeviceDebugSymbolsCommands, queue: DispatchQueue) {
    self.commands = commands
    self.queue = queue
  }

  func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Symbols")
  }

  func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    if sourcePath == ExtractedSymbolsDirectory {
      return try await commands.pullAndExtractSymbols(toDestinationDirectory: destinationPath)
    }
    return try await commands.pullSymbolFile(sourcePath, toDestinationPath: destinationPath)
  }

  func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw DeviceFileContainerError.tailUnsupported(container: "Symbols")
  }

  func createDirectory(_ directoryPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Symbols")
  }

  func move(from sourcePath: String, to destinationPath: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Symbols")
  }

  func remove(_ path: String) async throws {
    throw DeviceFileContainerError.operationUnsupported(operation: #function, container: "Symbols")
  }

  func contents(ofDirectory path: String) async throws -> [String] {
    let listedSymbols = try await commands.listSymbols()
    return listedSymbols + [ExtractedSymbolsDirectory]
  }
}

// MARK: - DeviceFileCommands

public final class DeviceFileCommands: FileCommands {
  private weak var device: FBDevice?
  private let afcCalls: AFCCalls

  // MARK: - Initializers

  public class func commands(with device: FBDevice) -> DeviceFileCommands {
    DeviceFileCommands(device: device, afcCalls: FBAFCConnection.defaultCalls)
  }

  public class func commands(with device: FBDevice, afcCalls: AFCCalls) -> DeviceFileCommands {
    DeviceFileCommands(device: device, afcCalls: afcCalls)
  }

  init(device: FBDevice, afcCalls: AFCCalls) {
    self.device = device
    self.afcCalls = afcCalls
  }

  // MARK: - FBFileCommands

  private func requireDevice() throws -> FBDevice {
    guard let device else {
      throw DeviceFileContainerError.deviceDeallocated
    }
    return device
  }

  public func withFileCommandsForContainerApplication<R>(
    _ bundleID: String,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    let queue = device.asyncQueue
    return try await device.withHouseArrestAFCConnection(forBundleID: bundleID, afcCalls: afcCalls) { connection in
      try await body(DeviceFileContainer(afcConnection: connection, queue: queue))
    }
  }

  public func withFileCommandsForAuxillary<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    return try await body(FBFileContainer.fileContainer(forBasePath: device.auxillaryDirectory))
  }

  public func withFileCommandsForApplicationContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw DeviceFileContainerError.requiresRootedDevice(operation: #function)
  }

  public func withFileCommandsForGroupContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw DeviceFileContainerError.requiresRootedDevice(operation: #function)
  }

  public func withFileCommandsForRootFilesystem<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    throw DeviceFileContainerError.requiresRootedDevice(operation: #function)
  }

  public func withFileCommandsForMediaDirectory<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    let queue = device.asyncQueue
    return try await device.withAFCConnection("com.apple.afc") { afc in
      try await body(DeviceFileContainer(afcConnection: afc, queue: queue))
    }
  }

  public func withFileCommandsForProvisioningProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    return try await body(FBFileContainer_ProvisioningProfile(commands: DeviceProvisioningProfileCommands.commands(with: device)))
  }

  public func withFileCommandsForMDMProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    return try await device.withServiceConnection(ManagedConfigClient.serviceName) { connection in
      let managedConfig = ManagedConfigClient.managedConfigClient(connection: connection, logger: device.logger)
      return try await body(DeviceFileContainer_MDMProfiles(managedConfig: managedConfig, queue: device.workQueue))
    }
  }

  public func withFileCommandsForSpringboardIconLayout<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    return try await device.withServiceConnection(SpringboardServicesClient.serviceName) { connection in
      let client = SpringboardServicesClient.springboardServicesClient(connection: connection, logger: device.logger)
      return try await body(client.iconContainer())
    }
  }

  public func withFileCommandsForWallpaper<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    return try await device.withServiceConnection(SpringboardServicesClient.serviceName) { springboardConnection in
      try await device.withServiceConnection(ManagedConfigClient.serviceName) { managedConfigConnection in
        let springboard = SpringboardServicesClient.springboardServicesClient(connection: springboardConnection, logger: device.logger)
        let managedConfig = ManagedConfigClient.managedConfigClient(connection: managedConfigConnection, logger: device.logger)
        return try await body(
          DeviceFileContainer_Wallpaper(springboard: springboard, managedConfig: managedConfig, queue: device.workQueue))
      }
    }
  }

  public func withFileCommandsForDiskImages<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    return try await body(DeviceFileCommands_DiskImages(commands: device.developerDiskImage, queue: device.asyncQueue))
  }

  public func withFileCommandsForSymbols<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    let device = try requireDevice()
    return try await body(DeviceFileCommands_Symbols(commands: device.debugSymbols, queue: device.asyncQueue))
  }
}

// MARK: - FBDevice+FileCommands

extension FBDevice: FileCommands {

  public func withFileCommandsForContainerApplication<R>(
    _ bundleID: String,
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForContainerApplication(bundleID, body: body)
  }

  public func withFileCommandsForAuxillary<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForAuxillary(body: body)
  }

  public func withFileCommandsForApplicationContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForApplicationContainers(body: body)
  }

  public func withFileCommandsForGroupContainers<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForGroupContainers(body: body)
  }

  public func withFileCommandsForRootFilesystem<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForRootFilesystem(body: body)
  }

  public func withFileCommandsForMediaDirectory<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForMediaDirectory(body: body)
  }

  public func withFileCommandsForProvisioningProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForProvisioningProfiles(body: body)
  }

  public func withFileCommandsForMDMProfiles<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForMDMProfiles(body: body)
  }

  public func withFileCommandsForSpringboardIconLayout<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForSpringboardIconLayout(body: body)
  }

  public func withFileCommandsForWallpaper<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForWallpaper(body: body)
  }

  public func withFileCommandsForDiskImages<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForDiskImages(body: body)
  }

  public func withFileCommandsForSymbols<R>(
    body: (any AsyncFileContainer) async throws -> R
  ) async throws -> R {
    try await file.withFileCommandsForSymbols(body: body)
  }
}
