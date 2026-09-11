/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A file addressed within some container. Conformers are value types holding only
/// the address, so the existential is `Sendable` and hops queues without boxing.
public protocol FBContainedFile: Sendable {

  func removeItem() throws

  func contentsOfDirectory() throws -> [String]

  func contentsOfFile() throws -> Data

  func createDirectory() throws

  func fileExists() -> (exists: Bool, isDirectory: Bool)

  func move(to destination: FBContainedFile) throws

  func populate(withContentsOfHostPath path: String) throws

  func populateHostPath(withContents path: String) throws

  func file(byAppendingPathComponent component: String) throws -> FBContainedFile

  var pathOnHostFileSystem: String? { get }

  var pathMapping: [String: String]? { get }
}

enum FileContainerError: Error {
  case copyIntoContainerFailed(source: String, destination: String, underlying: Error)
  case sourceDoesNotExist(source: String)
  case temporaryDirectoryCreationFailed(underlying: Error)
  case removalBeforeOverwriteFailed(path: String, underlying: Error)
  case copyOutOfContainerFailed(source: String, destination: String, underlying: Error)
  case notOnLocalFilesystem(file: String)
  case directoryCreationFailed(directory: String, underlying: Error)
  case moveFailed(source: String, destination: String, underlying: Error)
  case removalFailed(path: String, underlying: Error)
  case unsupportedForProvisioningProfiles(operation: String)
  case destinationNotOnHostFilesystem(destination: String)
  case unsupportedOnVirtualRoot(operation: String)
  case movingUnsupportedOnVirtualRoot
  case invalidRootPath(component: String, available: [String])
}

extension FileContainerError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case let .copyIntoContainerFailed(source, destination, underlying):
      return "Could not copy from \(source) to \(destination): \(underlying)"
    case let .sourceDoesNotExist(source):
      return "Source path does not exist: \(source)"
    case let .temporaryDirectoryCreationFailed(underlying):
      return "Could not create temporary directory: \(underlying)"
    case let .removalBeforeOverwriteFailed(path, underlying):
      return "Could not remove \(path): \(underlying)"
    case let .copyOutOfContainerFailed(source, destination, underlying):
      return "Could not copy from \(source) to \(destination): \(underlying)"
    case let .notOnLocalFilesystem(file):
      return "Cannot tail \(file), it is not on the local filesystem"
    case let .directoryCreationFailed(directory, underlying):
      return "Could not create directory \(directory): \(underlying)"
    case let .moveFailed(source, destination, underlying):
      return "Could not move item at \(source) to \(destination): \(underlying)"
    case let .removalFailed(path, underlying):
      return "Could not remove item at path \(path): \(underlying)"
    case let .unsupportedForProvisioningProfiles(operation):
      return "\(operation) is not implemented for provisioning profiles"
    case let .destinationNotOnHostFilesystem(destination):
      return "Cannot move to \(destination), it is not on the host filesystem"
    case let .unsupportedOnVirtualRoot(operation):
      return "\(operation) does not operate on root virtual containers"
    case .movingUnsupportedOnVirtualRoot:
      return "Moving files does not work on root virtual containers"
    case let .invalidRootPath(component, available):
      return "'\(component)' is not a valid root path out of \(CollectionInformation.oneLineDescription(from: available))"
    }
  }
}

/// Carries a non-`Sendable` `ProvisioningProfileCommands` across the async boundary.
private final class ProvisioningCommandsBox: @unchecked Sendable {
  let commands: any ProvisioningProfileCommands
  init(_ commands: any ProvisioningProfileCommands) {
    self.commands = commands
  }
}

/// Handle to a running `tail` started by a file container. Cancelling stops the
/// underlying `tail` subprocess and waits for it to exit.
public final class FileContainerTailOperation {
  private let completed: FBFuture<NSNull>
  init(completed: FBFuture<NSNull>) {
    self.completed = completed
  }

  public func cancel() async throws {
    try await bridgeFBFutureVoid(self.completed.cancel())
  }
}

/// File container backed by a synchronous `FBContainedFile`. Each operation
/// resolves the target path and runs the synchronous file work on a serial
/// queue.
public final class ContainedFile_ContainedRoot: AsyncFileContainer {

  private let rootFile: any FBContainedFile
  private let queue: DispatchQueue

  public init(rootFile: any FBContainedFile, queue: DispatchQueue) {
    self.rootFile = rootFile
    self.queue = queue
  }

  // MARK: - Host path access

  public var pathOnHostFileSystem: String? { rootFile.pathOnHostFileSystem }

  public var pathMapping: [String: String]? { rootFile.pathMapping }

  // MARK: - AsyncFileContainer

  public func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let rootFile = self.rootFile
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          var destination = try rootFile.file(byAppendingPathComponent: destinationPath)
          // Attempt to delete first to overwrite.
          destination = try destination.file(byAppendingPathComponent: (sourcePath as NSString).lastPathComponent)
          try? destination.removeItem()
          do {
            try destination.populate(withContentsOfHostPath: sourcePath)
          } catch {
            throw FileContainerError.copyIntoContainerFailed(source: sourcePath, destination: destinationPath, underlying: error)
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    let rootFile = self.rootFile
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      queue.async {
        do {
          let source = try rootFile.file(byAppendingPathComponent: sourcePath)
          let (sourceExists, sourceIsDirectory) = source.fileExists()
          guard sourceExists else {
            throw FileContainerError.sourceDoesNotExist(source: String(describing: source))
          }
          var dstPath = destinationPath
          if !sourceIsDirectory {
            do {
              try FileManager.default.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
            } catch {
              throw FileContainerError.temporaryDirectoryCreationFailed(underlying: error)
            }
            dstPath = (dstPath as NSString).appendingPathComponent((sourcePath as NSString).lastPathComponent)
          }
          // If it already exists at the destination path it must be removed before copying again.
          var destinationIsDirectory: ObjCBool = false
          if FileManager.default.fileExists(atPath: dstPath, isDirectory: &destinationIsDirectory) {
            do {
              try FileManager.default.removeItem(atPath: dstPath)
            } catch {
              throw FileContainerError.removalBeforeOverwriteFailed(path: dstPath, underlying: error)
            }
          }
          do {
            try source.populateHostPath(withContents: dstPath)
          } catch {
            throw FileContainerError.copyOutOfContainerFailed(source: String(describing: source), destination: dstPath, underlying: error)
          }
          continuation.resume(returning: destinationPath)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    let rootFile = self.rootFile
    let serialQueue = queue
    let hostPath: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      serialQueue.async {
        do {
          let fileToTail = try rootFile.file(byAppendingPathComponent: path)
          guard let hostPath = fileToTail.pathOnHostFileSystem else {
            throw FileContainerError.notOnLocalFilesystem(file: String(describing: fileToTail))
          }
          continuation.resume(returning: hostPath)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
    let builder = FBProcessBuilder<AnyObject, AnyObject, AnyObject>
      .withLaunchPath("/usr/bin/tail", arguments: ["-c+1", "-f", hostPath])
      .withStdOutConsumer(consumer)
    let process = try await awaitStart(of: builder)
    let completed = process.statLoc
      .mapReplace(NSNull())
      .onQueue(
        serialQueue,
        respondToCancellation: {
          process.sendSignal(SIGTERM, backingOffToKillWithTimeout: 1, logger: nil).retyped(FBFuture<NSNull>.self)
        })
    return FileContainerTailOperation(completed: completed.retyped(FBFuture<NSNull>.self))
  }

  public func createDirectory(_ directoryPath: String) async throws {
    let rootFile = self.rootFile
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let directory = try rootFile.file(byAppendingPathComponent: directoryPath)
          do {
            try directory.createDirectory()
          } catch {
            throw FileContainerError.directoryCreationFailed(directory: String(describing: directory), underlying: error)
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func move(from sourcePath: String, to destinationPath: String) async throws {
    let rootFile = self.rootFile
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let source = try rootFile.file(byAppendingPathComponent: sourcePath)
          let destination = try rootFile.file(byAppendingPathComponent: destinationPath)
          do {
            try source.move(to: destination)
          } catch {
            throw FileContainerError.moveFailed(source: String(describing: source), destination: String(describing: destination), underlying: error)
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func remove(_ path: String) async throws {
    let rootFile = self.rootFile
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let file = try rootFile.file(byAppendingPathComponent: path)
          do {
            try file.removeItem()
          } catch {
            throw FileContainerError.removalFailed(path: String(describing: file), underlying: error)
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func contents(ofDirectory path: String) async throws -> [String] {
    let rootFile = self.rootFile
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
      queue.async {
        do {
          let directory = try rootFile.file(byAppendingPathComponent: path)
          continuation.resume(returning: try directory.contentsOfDirectory())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

}

/// File container backed by `ProvisioningProfileCommands`.
public final class FBFileContainer_ProvisioningProfile: AsyncFileContainer {

  private let commandsBox: ProvisioningCommandsBox

  public init(commands: any ProvisioningProfileCommands) {
    self.commandsBox = ProvisioningCommandsBox(commands)
  }

  // MARK: - AsyncFileContainer

  public func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    _ = try await commandsBox.commands.install(data)
  }

  public func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    throw FileContainerError.unsupportedForProvisioningProfiles(operation: #function)
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> FileContainerTailOperation {
    throw FileContainerError.unsupportedForProvisioningProfiles(operation: #function)
  }

  public func createDirectory(_ directoryPath: String) async throws {
    throw FileContainerError.unsupportedForProvisioningProfiles(operation: #function)
  }

  public func move(from sourcePath: String, to destinationPath: String) async throws {
    throw FileContainerError.unsupportedForProvisioningProfiles(operation: #function)
  }

  public func remove(_ path: String) async throws {
    _ = try await commandsBox.commands.remove(uuid: path)
  }

  public func contents(ofDirectory path: String) async throws -> [String] {
    let profiles = try await commandsBox.commands.all()
    var files: [String] = []
    for profile in profiles {
      if let uuid = profile["UUID"] as? String {
        files.append(uuid)
      }
    }
    return files
  }
}

// MARK: - Container Kinds

/// The names of the file containers a target can expose.
public struct FBFileContainerKind: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public static let application = FBFileContainerKind(rawValue: "application")
  public static let auxillary = FBFileContainerKind(rawValue: "auxillary")
  public static let crashes = FBFileContainerKind(rawValue: "crashes")
  public static let diskImages = FBFileContainerKind(rawValue: "disk_images")
  public static let group = FBFileContainerKind(rawValue: "group")
  public static let mdmProfiles = FBFileContainerKind(rawValue: "mdm_profiles")
  public static let media = FBFileContainerKind(rawValue: "media")
  public static let provisioningProfiles = FBFileContainerKind(rawValue: "provisioning_profiles")
  public static let root = FBFileContainerKind(rawValue: "root")
  public static let springboardIcons = FBFileContainerKind(rawValue: "springboard_icons")
  public static let symbols = FBFileContainerKind(rawValue: "symbols")
  public static let wallpaper = FBFileContainerKind(rawValue: "wallpaper")
  public static let xctest = FBFileContainerKind(rawValue: "xctest")
  public static let dylib = FBFileContainerKind(rawValue: "dylib")
  public static let dsym = FBFileContainerKind(rawValue: "dsym")
  public static let framework = FBFileContainerKind(rawValue: "framework")
}

// MARK: - Host Filesystem Contained Files

/// A file on the host filesystem, addressed by absolute path.
private struct ContainedFile_Host: FBContainedFile, CustomStringConvertible {

  let path: String

  func removeItem() throws {
    try FileManager.default.removeItem(atPath: path)
  }

  func contentsOfDirectory() throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: path)
  }

  func contentsOfFile() throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: path))
  }

  func createDirectory() throws {
    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
  }

  func fileExists() -> (exists: Bool, isDirectory: Bool) {
    var isDirectory: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
    return (exists, isDirectory.boolValue)
  }

  func move(to destination: FBContainedFile) throws {
    guard let hostDestination = destination as? ContainedFile_Host else {
      throw FileContainerError.destinationNotOnHostFilesystem(destination: String(describing: destination))
    }
    try FileManager.default.moveItem(atPath: path, toPath: hostDestination.path)
  }

  func populate(withContentsOfHostPath path: String) throws {
    try FileManager.default.copyItem(atPath: path, toPath: self.path)
  }

  func populateHostPath(withContents path: String) throws {
    try FileManager.default.copyItem(atPath: self.path, toPath: path)
  }

  func file(byAppendingPathComponent component: String) throws -> FBContainedFile {
    ContainedFile_Host(path: (path as NSString).appendingPathComponent(component))
  }

  var pathOnHostFileSystem: String? { path }

  var pathMapping: [String: String]? { nil }

  var description: String {
    "Host File \(path)"
  }
}

/// A virtual root that maps first path components onto host paths.
private struct ContainedFile_Mapped_Host: FBContainedFile, CustomStringConvertible {

  let mappingPaths: [String: String]

  func removeItem() throws {
    throw FileContainerError.unsupportedOnVirtualRoot(operation: #function)
  }

  func contentsOfDirectory() throws -> [String] {
    Array(mappingPaths.keys)
  }

  func contentsOfFile() throws -> Data {
    throw FileContainerError.unsupportedOnVirtualRoot(operation: #function)
  }

  func createDirectory() throws {
    throw FileContainerError.unsupportedOnVirtualRoot(operation: #function)
  }

  func fileExists() -> (exists: Bool, isDirectory: Bool) {
    (false, false)
  }

  func move(to destination: FBContainedFile) throws {
    throw FileContainerError.movingUnsupportedOnVirtualRoot
  }

  func populate(withContentsOfHostPath path: String) throws {
    throw FileContainerError.unsupportedOnVirtualRoot(operation: #function)
  }

  func populateHostPath(withContents path: String) throws {
    throw FileContainerError.unsupportedOnVirtualRoot(operation: #function)
  }

  func file(byAppendingPathComponent component: String) throws -> FBContainedFile {
    // The root of the mapping itself has nothing further to resolve.
    let pathComponents = (component as NSString).pathComponents
    if Self.isRootPathOfContainer(pathComponents) {
      return self
    }
    guard let firstComponent = pathComponents.first, let mappedPath = mappingPaths[firstComponent] else {
      throw FileContainerError.invalidRootPath(component: pathComponents.first ?? "", available: Array(mappingPaths.keys))
    }
    let mapped = ContainedFile_Host(path: mappedPath)
    return try mapped.file(byAppendingPathComponent: Self.popFirstPathComponent(pathComponents))
  }

  var pathOnHostFileSystem: String? { nil }

  var pathMapping: [String: String]? { mappingPaths }

  var description: String {
    "Root mapping: \(CollectionInformation.oneLineDescription(from: Array(mappingPaths.keys)))"
  }

  private static func isRootPathOfContainer(_ pathComponents: [String]) -> Bool {
    if pathComponents.isEmpty {
      return true
    }
    if pathComponents.count == 1, let first = pathComponents.first, first == "." || first == "/" {
      return true
    }
    return false
  }

  private static func popFirstPathComponent(_ pathComponents: [String]) -> String {
    pathComponents.dropFirst().reduce("") { ($0 as NSString).appendingPathComponent($1) }
  }
}

// MARK: - Factories

/// Factories for the file containers a target exposes.
public enum FBFileContainer {

  public static func containedFile(forBasePath basePath: String) -> FBContainedFile {
    ContainedFile_Host(path: basePath)
  }

  public static func containedFile(forPathMapping pathMapping: [String: String]) -> FBContainedFile {
    ContainedFile_Mapped_Host(mappingPaths: pathMapping)
  }

  public static func fileContainer(forBasePath basePath: String) -> ContainedFile_ContainedRoot {
    fileContainer(for: containedFile(forBasePath: basePath))
  }

  public static func fileContainer(forPathMapping pathMapping: [String: String]) -> ContainedFile_ContainedRoot {
    fileContainer(for: containedFile(forPathMapping: pathMapping))
  }

  public static func fileContainer(for containedFile: FBContainedFile) -> ContainedFile_ContainedRoot {
    ContainedFile_ContainedRoot(rootFile: containedFile, queue: DispatchQueue(label: "com.facebook.fbcontrolcore.file_container"))
  }
}
