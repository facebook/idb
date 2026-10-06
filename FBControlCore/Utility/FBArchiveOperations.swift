/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import os

public let BSDTarPath = "/usr/bin/bsdtar"

/// The compression types available.
public enum FBCompressionFormat: UInt, Sendable {
  case GZIP = 1
  case ZSTD = 2
}

public enum ArchiveOperationsError: Error, LocalizedError {
  case pathDoesNotExist(path: String)
  /// The tool reading a stream exited unsuccessfully, with the tail of its standard error.
  case unacceptableExitCode(Int32, standardError: String)
  case compressionFailed(path: String, exitCode: Int32, stderr: String)

  public var errorDescription: String? {
    switch self {
    case let .pathDoesNotExist(path):
      return "Path for tarring \(path) doesn't exist"
    case let .unacceptableExitCode(code, standardError):
      let description = "Exit Code \(code) is not acceptable [0]"
      return standardError.isEmpty ? description : "\(description): \(standardError)"
    case let .compressionFailed(path, exitCode, stderr):
      return "Compressing \(path) failed with exit code \(exitCode): \(stderr)"
    }
  }
}

/// Operations on zip/tar archives.
public enum FBArchiveOperations {

  /// A tar made by macOS `tar` carries an AppleDouble entry per file (e.g. for the
  /// `com.apple.provenance` xattr). Restoring them roughly triples extraction time and nothing
  /// in an app bundle's signature depends on them.
  private static let NoMacMetadataFlag = "--no-mac-metadata"

  /// Builds a command to extract from a file on disk.
  public static func commandToExtractArchive(
    atPath path: String,
    toPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    debugLogging: Bool
  ) -> [String] {
    let flags = flagStringForExtraction(overrideModificationTime: overrideMTime, debugLogging: debugLogging)
    return [flags, NoMacMetadataFlag, "-C", extractPath, "-f", path]
  }

  /// Extracts a tar or zip file archive to a directory. The file can be an uncompressed tar, a
  /// gzipped tar, or a zip.
  public static func extractArchive(
    atPath path: String,
    toPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    logger: any ControlCoreLogger
  ) async throws -> String {
    let arguments = commandToExtractArchive(
      atPath: path,
      toPath: extractPath,
      overrideModificationTime: overrideMTime,
      debugLogging: false)
    _ = try await Subprocess(executable: BSDTarPath, arguments: arguments)
      .run(output: .logger(logger.debug()), error: .loggerCapturingErrorMessage(logger.debug()), logger: logger)
    return extractPath
  }

  /// Builds a command to extract via stdin.
  public static func commandToExtractFromStdIn(
    withExtractPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    debugLogging: Bool
  ) -> [String] {
    let flags = flagStringForExtraction(overrideModificationTime: overrideMTime, debugLogging: debugLogging)
    return [flags, NoMacMetadataFlag, "-C", extractPath, "-f", "-"]
  }

  /// Extracts a tar or zip read from `source` to a directory. The stream can be an uncompressed tar, a
  /// gzipped tar, or a zip.
  public static func extractArchive(
    from source: any ByteSource,
    toPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    logger: any ControlCoreLogger
  ) async throws {
    let arguments = commandToExtractFromStdIn(
      withExtractPath: extractPath,
      overrideModificationTime: overrideMTime,
      debugLogging: false)
    try await run(Subprocess(executable: BSDTarPath, arguments: arguments), output: .logger(logger.debug()), reading: source, logger: logger)
  }

  /// Decompresses a gzip read from `source` to a single file. A plain gzip wrapping a single file is
  /// preferred when there's only a single file to transfer.
  public static func extractGzip(
    from source: any ByteSource,
    toPath extractPath: String,
    logger: any ControlCoreLogger
  ) async throws {
    try await run(
      Subprocess(executable: "/usr/bin/gunzip", arguments: ["--to-stdout"]),
      output: .file(URL(fileURLWithPath: extractPath)), reading: source, logger: logger)
  }

  /// Runs `subprocess` reading `source` on its standard input. Fails on an unsuccessful exit, and
  /// otherwise if the child stopped reading before `source` ended.
  private static func run<Out>(
    _ subprocess: Subprocess,
    output: Subprocess.Output<Out>,
    reading source: any ByteSource,
    logger: any ControlCoreLogger
  ) async throws {
    let writer = StandardInputWriter()
    let standardError = FBDataBuffer.accumulatingBuffer(withCapacity: Subprocess.errorMessageLength)
    let source = HandedOver(source)
    async let written = offCooperativePool { try writer.write(from: source.value) }
    do {
      let completed = try await subprocess.run(
        output: output,
        error: .consumer(FBCompositeDataConsumer(consumers: [standardError, FBLoggingDataConsumer(logger: logger.debug())])),
        input: .source(writer.input),
        exitPolicy: .any,
        logger: logger)
      try completed.checkExitedCleanly { code in
        ArchiveOperationsError.unacceptableExitCode(
          code, standardError: String(decoding: standardError.data(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
      }
    } catch {
      // The writer reads `source`, which the caller may close once this returns.
      writer.stop()
      _ = await written
      throw error
    }
    try await written.get()
  }

  /// Gzips the file at `path`, returning the compressed data.
  public static func createGzipData(
    forPath path: String,
    logger: any ControlCoreLogger
  ) async throws -> Data {
    let gzip = try await Subprocess(executable: "/usr/bin/gzip", arguments: ["--to-stdout", path])
      .run(output: .data, error: .loggerCapturingErrorMessage(logger), exitPolicy: .any, logger: logger)
    try gzip.checkExitedCleanly { ArchiveOperationsError.compressionFailed(path: path, exitCode: $0, stderr: gzip.standardError) }
    return gzip.standardOutput
  }

  /// A gzip that writes the compressed file at `path` to its stdout, for the caller to launch and stream.
  public static func gzipSubprocess(forPath path: String) -> Subprocess {
    Subprocess(executable: "/usr/bin/gzip", arguments: ["--to-stdout", path])
  }

  /// A bsdtar that writes a gzipped tar of `path` to its stdout, for the caller to launch and stream.
  public static func gzippedTarSubprocess(
    forPath path: String,
    logger: any ControlCoreLogger
  ) throws -> Subprocess {
    Subprocess(executable: BSDTarPath, arguments: try gzippedTarArguments(forPath: path, logger: logger))
  }

  /// Creates a gzipped tar archive, returning the data of the tar.
  public static func createGzippedTarData(
    forPath path: String,
    logger: any ControlCoreLogger
  ) async throws -> Data {
    let arguments = try gzippedTarArguments(forPath: path, logger: logger)
    return try await Subprocess(executable: BSDTarPath, arguments: arguments)
      .run(output: .data, error: .loggerCapturingErrorMessage(logger), logger: logger)
      .standardOutput
  }

  private static func flagStringForExtraction(overrideModificationTime overrideMTime: Bool, debugLogging: Bool) -> String {
    var flags = ["z", "x", "p"]
    if overrideMTime {
      flags.append("m")
    }
    if debugLogging {
      flags.append("v")
    }
    return "-\(flags.joined())"
  }

  /// A directory is tarred with itself as the root; a file is tarred relative to its parent.
  private static func gzippedTarArguments(forPath path: String, logger: any ControlCoreLogger) throws -> [String] {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      throw ArchiveOperationsError.pathDoesNotExist(path: path)
    }

    let directory: String
    let fileName: String
    if isDirectory.boolValue {
      directory = path
      fileName = "."
      logger.info().log("\(directory) is a directory, tarring with it as the root.")
      if (try? FileManager.default.contentsOfDirectory(atPath: path))?.isEmpty ?? true {
        logger.info().log("Attempting to tar directory at path \(path), but it has no contents")
      }
    } else {
      directory = (path as NSString).deletingLastPathComponent
      fileName = (path as NSString).lastPathComponent
      logger.info().log("\(path) is a file, tarring relative to it's parent \(directory)")
      let fileSize = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? UInt ?? 0
      if fileSize <= 0 {
        logger.info().log("Attempting to tar file at path \(path), but it has no content")
      }
    }
    return ["-zvc", "-f", "-", "-C", directory, fileName]
  }
}

/// Copies a source into a child's standard input, reading the next chunk only once the child has
/// taken the last, so a child that reads slowly slows the source rather than filling memory.
private final class StandardInputWriter: Sendable {

  let input = InputSource()
  private let stopped = OSAllocatedUnfairLock(initialState: false)

  /// Blocks its thread until `source` ends, the child stops reading, or `stop()` is called.
  func write(from source: any ByteSource) throws {
    defer { input.finish() }
    var chunk = [UInt8](repeating: 0, count: 1 << 16)
    while !stopped.withLock({ $0 }) {
      let count = try chunk.withUnsafeMutableBytes { try source.read(into: $0) }
      guard count > 0 else {
        return
      }
      try Self.wait { [input, data = Data(chunk[..<count])] in
        try await input.writeAndWait(data)
      }
    }
  }

  /// Ends the child's input after the chunk being written.
  func stop() {
    stopped.withLock { $0 = true }
    input.finish()
  }

  private static func wait(_ operation: @escaping @Sendable () async throws -> Void) throws {
    let finished = DispatchSemaphore(value: 0)
    let result = OSAllocatedUnfairLock<Result<Void, any Error>>(initialState: .success(()))
    Task {
      do {
        try await operation()
      } catch {
        result.withLock { $0 = .failure(error) }
      }
      finished.signal()
    }
    finished.wait()
    try result.withLock { $0 }.get()
  }
}
