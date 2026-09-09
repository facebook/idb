/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public enum FBTemporaryDirectoryError: Error, LocalizedError {
  case creationFailed(directory: URL, underlying: Error)

  public var errorDescription: String? {
    switch self {
    case let .creationFailed(directory, _):
      return "Failed to create Temp Dir \(directory)"
    }
  }
}

@objc(FBTemporaryDirectory)
public final class FBTemporaryDirectory: NSObject {

  // MARK: - Properties

  @objc public let logger: FBControlCoreLogger
  @objc public let queue: DispatchQueue

  private let rootTemporaryDirectory: URL

  // MARK: - Initializers

  @objc(temporaryDirectoryWithLogger:)
  public class func temporaryDirectory(logger: FBControlCoreLogger) -> Self {
    let temporaryDirectory = uniqueTemporaryDirectoryURL()
    do {
      try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      assertionFailure("Failed to create temporary directory: \(error)")
    }
    let queue = DispatchQueue(label: "com.facebook.idb.fbtemporarydirectory")
    return self.init(rootDirectory: temporaryDirectory, queue: queue, logger: logger)
  }

  @objc(initWithLogger:)
  public convenience init(logger: FBControlCoreLogger) {
    let temporaryDirectory = FBTemporaryDirectory.uniqueTemporaryDirectoryURL()
    do {
      try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      fatalError("Failed to create temporary directory: \(error)")
    }
    let queue = DispatchQueue(label: "com.facebook.idb.fbtemporarydirectory")
    self.init(rootDirectory: temporaryDirectory, queue: queue, logger: logger)
  }

  private class func uniqueTemporaryDirectoryURL() -> URL {
    let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
    return URL(fileURLWithPath: base)
      .appendingPathComponent("IDB")
      .appendingPathComponent(UUID().uuidString)
  }

  required init(rootDirectory: URL, queue: DispatchQueue, logger: FBControlCoreLogger) {
    self.rootTemporaryDirectory = rootDirectory
    self.queue = queue
    self.logger = logger
    super.init()
  }

  // MARK: - Public Methods

  @objc public func cleanOnExit() {
    do {
      try FileManager.default.removeItem(at: rootTemporaryDirectory)
      logger.debug().log("Successfully removed temporal directory: \(rootTemporaryDirectory)")
    } catch {
      logger.error().log("Couldn't remove temporary directory: \(rootTemporaryDirectory) (\(error.localizedDescription))")
    }
  }

  @objc public func ephemeralTemporaryDirectory() -> URL {
    return rootTemporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  // MARK: - Scoped

  /// Creates a temporary directory that exists for exactly the scope of `body`: deleted when
  /// `body` returns or throws.
  public func withTemporaryDirectory<T>(_ body: (URL) async throws -> T) async throws -> T {
    let tempDirectory = ephemeralTemporaryDirectory()
    logger.log("Creating Temp Dir \(tempDirectory)")
    do {
      try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      throw FBTemporaryDirectoryError.creationFailed(directory: tempDirectory, underlying: error)
    }
    defer { delete(tempDirectory) }
    return try await body(tempDirectory)
  }

  /// Extracts the archive in `input` into a temporary directory scoped to `body`.
  public func withArchiveExtracted<T>(
    fromStream input: FBProcessInput<AnyObject>,
    compression: FBCompressionFormat,
    overrideModificationTime overrideMTime: Bool = false,
    _ body: (URL) async throws -> T
  ) async throws -> T {
    try await withTemporaryDirectory { tempDir in
      _ = try await bridgeFBFuture(
        FBArchiveOperations.extractArchive(fromStream: input, toPath: tempDir.path, overrideModificationTime: overrideMTime, logger: logger, compression: compression))
      return try await body(tempDir)
    }
  }

  /// Extracts the gzipped tar in `tarData` into a temporary directory scoped to `body`.
  public func withArchiveExtracted<T>(_ tarData: Data, _ body: (URL) async throws -> T) async throws -> T {
    let input = unsafeBitCast(FBProcessInput<NSData>(from: tarData), to: FBProcessInput<AnyObject>.self)
    return try await withArchiveExtracted(fromStream: input, compression: .GZIP, body)
  }

  /// Extracts the archive at `filePath` into a temporary directory scoped to `body`.
  public func withArchiveExtracted<T>(
    fromFile filePath: String,
    overrideModificationTime overrideMTime: Bool,
    _ body: (URL) async throws -> T
  ) async throws -> T {
    try await withTemporaryDirectory { tempDir in
      _ = try await bridgeFBFuture(
        FBArchiveOperations.extractArchive(atPath: filePath, toPath: tempDir.path, overrideModificationTime: overrideMTime, logger: logger))
      return try await body(tempDir)
    }
  }

  /// Extracts the gzip in `input` to a file named `name` inside a temporary directory scoped to
  /// `body`; the file goes with the directory when the scope ends.
  public func withGzipExtracted<T>(fromStream input: FBProcessInput<AnyObject>, name: String, _ body: (URL) async throws -> T) async throws -> T {
    try await withTemporaryDirectory { directory in
      let tempFile = directory.appendingPathComponent(name)
      _ = try await bridgeFBFuture(
        FBArchiveOperations.extractGzip(fromStream: input, toPath: tempFile.path, logger: logger))
      return try await body(tempFile)
    }
  }

  /// Returns the unique file inside each immediate subdirectory of `extractionDirectory`.
  public func files(inSubdirectoriesOf extractionDirectory: URL) throws -> [URL] {
    let subfolders = try FBStorageUtils.files(inDirectory: extractionDirectory)
    return try subfolders.map { try FBStorageUtils.findUniqueFile(inDirectory: $0) }
  }

  private func delete(_ url: URL) {
    do {
      try FileManager.default.removeItem(at: url)
      logger.log("Deleted Temp Dir \(url)")
    } catch {
      logger.log("Failed to delete Temp Dir \(url): \(error)")
    }
  }

  // MARK: - Temporary Directory

  @objc public func temporaryDirectory() -> URL {
    let tempDirectory = ephemeralTemporaryDirectory()
    logger.log("Creating Temp Dir \(tempDirectory)")
    do {
      try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      logger.log("Failed to create Temp Dir \(tempDirectory) with error \(error)")
    }
    return tempDirectory
  }

}
