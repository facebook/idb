/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc public protocol FBContainedFile: NSObjectProtocol {

  @objc(removeItemWithError:)
  func removeItem() throws

  @objc(contentsOfDirectoryWithError:)
  func contentsOfDirectory() throws -> [String]

  @objc(contentsOfFileWithError:)
  func contentsOfFile() throws -> Data

  @objc(createDirectoryWithError:)
  func createDirectory() throws

  @objc(fileExistsIsDirectory:)
  func fileExists(isDirectory isDirectoryOut: UnsafeMutablePointer<ObjCBool>?) -> Bool

  @objc(moveTo:error:)
  func move(to destination: FBContainedFile) throws

  @objc(populateWithContentsOfHostPath:error:)
  func populate(withContentsOfHostPath path: String) throws

  @objc(populateHostPathWithContents:error:)
  func populateHostPath(withContents path: String) throws

  @objc(fileByAppendingPathComponent:error:)
  func file(byAppendingPathComponent component: String) throws -> FBContainedFile

  @objc var pathOnHostFileSystem: String? { get }

  @objc var pathMapping: [String: String]? { get }
}

/// Carries a non-`Sendable` `FBContainedFile` across the serial-queue boundary.
/// The wrapped value is only ever touched on the owning serial queue.
private final class ContainedFileBox: @unchecked Sendable {
  let file: any FBContainedFile
  init(_ file: any FBContainedFile) {
    self.file = file
  }
}

/// Carries a non-`Sendable` `FBProvisioningProfileCommands` across the async boundary.
private final class ProvisioningCommandsBox: @unchecked Sendable {
  let commands: any FBProvisioningProfileCommands
  init(_ commands: any FBProvisioningProfileCommands) {
    self.commands = commands
  }
}

/// Wraps a teardown future in `FBiOSTargetOperation` shape so `tail` has an
/// operation handle to return.
private final class FileContainerTailOperation: NSObject, FBiOSTargetOperation {
  let completed: FBFuture<NSNull>
  init(completed: FBFuture<NSNull>) {
    self.completed = completed
    super.init()
  }
}

/// File container backed by a synchronous `FBContainedFile`. Each operation
/// resolves the target path and runs the synchronous file work on a serial
/// queue.
@objc(FBContainedFile_ContainedRoot)
public final class FBContainedFile_ContainedRoot: NSObject, AsyncFileContainer {

  private let rootFileBox: ContainedFileBox
  private let queue: DispatchQueue

  @objc public init(rootFile: any FBContainedFile, queue: DispatchQueue) {
    self.rootFileBox = ContainedFileBox(rootFile)
    self.queue = queue
    super.init()
  }

  // MARK: - AsyncFileContainer

  public func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let box = rootFileBox
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          var destination = try box.file.file(byAppendingPathComponent: destinationPath)
          // Attempt to delete first to overwrite.
          destination = try destination.file(byAppendingPathComponent: (sourcePath as NSString).lastPathComponent)
          try? destination.removeItem()
          do {
            try destination.populate(withContentsOfHostPath: sourcePath)
          } catch {
            throw
              FBControlCoreError
              .describe("Could not copy from \(sourcePath) to \(destinationPath): \(error)")
              .caused(by: error)
              .build()
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    let box = rootFileBox
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      queue.async {
        do {
          let source = try box.file.file(byAppendingPathComponent: sourcePath)
          var sourceIsDirectory: ObjCBool = false
          guard source.fileExists(isDirectory: &sourceIsDirectory) else {
            throw FBControlCoreError.describe("Source path does not exist: \(source)").build()
          }
          var dstPath = destinationPath
          if !sourceIsDirectory.boolValue {
            do {
              try FileManager.default.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
            } catch {
              throw
                FBControlCoreError
                .describe("Could not create temporary directory: \(error)")
                .caused(by: error)
                .build()
            }
            dstPath = (dstPath as NSString).appendingPathComponent((sourcePath as NSString).lastPathComponent)
          }
          // If it already exists at the destination path it must be removed before copying again.
          var destinationIsDirectory: ObjCBool = false
          if FileManager.default.fileExists(atPath: dstPath, isDirectory: &destinationIsDirectory) {
            do {
              try FileManager.default.removeItem(atPath: dstPath)
            } catch {
              throw
                FBControlCoreError
                .describe("Could not remove \(dstPath)")
                .caused(by: error)
                .build()
            }
          }
          do {
            try source.populateHostPath(withContents: dstPath)
          } catch {
            throw
              FBControlCoreError
              .describe("Could not copy from \(source) to \(dstPath): \(error)")
              .caused(by: error)
              .build()
          }
          continuation.resume(returning: destinationPath)
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation {
    let box = rootFileBox
    let serialQueue = queue
    let hostPath: String = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
      serialQueue.async {
        do {
          let fileToTail = try box.file.file(byAppendingPathComponent: path)
          guard let hostPath = fileToTail.pathOnHostFileSystem else {
            throw FBControlCoreError.describe("Cannot tail \(fileToTail), it is not on the local filesystem").build()
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
          unsafeBitCast(process.sendSignal(SIGTERM, backingOffToKillWithTimeout: 1, logger: nil), to: FBFuture<NSNull>.self)
        })
    return FileContainerTailOperation(completed: unsafeBitCast(completed, to: FBFuture<NSNull>.self))
  }

  public func createDirectory(_ directoryPath: String) async throws {
    let box = rootFileBox
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let directory = try box.file.file(byAppendingPathComponent: directoryPath)
          do {
            try directory.createDirectory()
          } catch {
            throw
              FBControlCoreError
              .describe("Could not create directory \(directory): \(error)")
              .caused(by: error)
              .build()
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func move(from sourcePath: String, to destinationPath: String) async throws {
    let box = rootFileBox
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let source = try box.file.file(byAppendingPathComponent: sourcePath)
          let destination = try box.file.file(byAppendingPathComponent: destinationPath)
          do {
            try source.move(to: destination)
          } catch {
            throw
              FBControlCoreError
              .describe("Could not move item at \(source) to \(destination): \(error)")
              .caused(by: error)
              .build()
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func remove(_ path: String) async throws {
    let box = rootFileBox
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let file = try box.file.file(byAppendingPathComponent: path)
          do {
            try file.removeItem()
          } catch {
            throw
              FBControlCoreError
              .describe("Could not remove item at path \(file): \(error)")
              .caused(by: error)
              .build()
          }
          continuation.resume(returning: ())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  public func contents(ofDirectory path: String) async throws -> [String] {
    let box = rootFileBox
    return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String], Error>) in
      queue.async {
        do {
          let directory = try box.file.file(byAppendingPathComponent: path)
          continuation.resume(returning: try directory.contentsOfDirectory())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

}

/// File container backed by `FBProvisioningProfileCommands`.
@objc(FBFileContainer_ProvisioningProfile)
public final class FBFileContainer_ProvisioningProfile: NSObject, AsyncFileContainer {

  private let commandsBox: ProvisioningCommandsBox

  @objc public init(commands: any FBProvisioningProfileCommands) {
    self.commandsBox = ProvisioningCommandsBox(commands)
    super.init()
  }

  // MARK: - AsyncFileContainer

  public func copy(fromHost sourcePath: String, toContainer destinationPath: String) async throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
    _ = try await bridgeFBFuture(commandsBox.commands.installProvisioningProfile(data))
  }

  public func copy(fromContainer sourcePath: String, toHost destinationPath: String) async throws -> String {
    throw FBControlCoreError.describe("\(#function) is not implemented for provisioning profiles").build()
  }

  public func tail(_ path: String, to consumer: any FBDataConsumer) async throws -> any FBiOSTargetOperation {
    throw FBControlCoreError.describe("\(#function) is not implemented for provisioning profiles").build()
  }

  public func createDirectory(_ directoryPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) is not implemented for provisioning profiles").build()
  }

  public func move(from sourcePath: String, to destinationPath: String) async throws {
    throw FBControlCoreError.describe("\(#function) is not implemented for provisioning profiles").build()
  }

  public func remove(_ path: String) async throws {
    _ = try await bridgeFBFuture(commandsBox.commands.removeProvisioningProfile(path))
  }

  public func contents(ofDirectory path: String) async throws -> [String] {
    let profiles = try await bridgeFBFuture(commandsBox.commands.allProvisioningProfiles()) as NSArray
    var files: [String] = []
    for case let profile as [String: Any] in profiles {
      if let uuid = profile["UUID"] as? String {
        files.append(uuid)
      }
    }
    return files
  }
}
