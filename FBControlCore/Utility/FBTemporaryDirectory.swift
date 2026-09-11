/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

enum TemporaryDirectoryError: Error, LocalizedError {
  case creationFailed(directory: URL, underlying: Error)

  public var errorDescription: String? {
    switch self {
    case let .creationFailed(directory, _):
      return "Failed to create Temp Dir \(directory)"
    }
  }
}

/// A value over the root it manages: two values with the same root are the same directory.
public struct FBTemporaryDirectory: Equatable {

  // MARK: - Properties

  public let logger: any FBControlCoreLogger

  private let rootTemporaryDirectory: URL

  public static func == (lhs: FBTemporaryDirectory, rhs: FBTemporaryDirectory) -> Bool {
    lhs.rootTemporaryDirectory == rhs.rootTemporaryDirectory
  }

  // MARK: - Initializers

  public static func temporaryDirectory(logger: any FBControlCoreLogger) -> FBTemporaryDirectory {
    let temporaryDirectory = uniqueTemporaryDirectoryURL()
    do {
      try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      assertionFailure("Failed to create temporary directory: \(error)")
    }
    return FBTemporaryDirectory(rootDirectory: temporaryDirectory, logger: logger)
  }

  public init(logger: any FBControlCoreLogger) {
    let temporaryDirectory = FBTemporaryDirectory.uniqueTemporaryDirectoryURL()
    do {
      try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true, attributes: nil)
    } catch {
      fatalError("Failed to create temporary directory: \(error)")
    }
    self.init(rootDirectory: temporaryDirectory, logger: logger)
  }

  private static func uniqueTemporaryDirectoryURL() -> URL {
    let base = ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()
    return URL(fileURLWithPath: base)
      .appendingPathComponent("IDB")
      .appendingPathComponent(UUID().uuidString)
  }

  init(rootDirectory: URL, logger: any FBControlCoreLogger) {
    self.rootTemporaryDirectory = rootDirectory
    self.logger = logger
  }

  // MARK: - Public Methods

  public func cleanOnExit() {
    do {
      try FileManager.default.removeItem(at: rootTemporaryDirectory)
      logger.debug().log("Successfully removed temporal directory: \(rootTemporaryDirectory)")
    } catch {
      logger.error().log("Couldn't remove temporary directory: \(rootTemporaryDirectory) (\(error.localizedDescription))")
    }
  }

  public func ephemeralTemporaryDirectory() -> URL {
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
      throw TemporaryDirectoryError.creationFailed(directory: tempDirectory, underlying: error)
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
    let input = FBProcessInput<NSData>(from: tarData).retyped(FBProcessInput<AnyObject>.self)
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
    let subfolders = try StorageUtils.files(inDirectory: extractionDirectory)
    return try subfolders.map { try StorageUtils.findUniqueFile(inDirectory: $0) }
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

  public func temporaryDirectory() -> URL {
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
