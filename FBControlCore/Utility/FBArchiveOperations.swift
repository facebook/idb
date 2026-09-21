/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public let BSDTarPath = "/usr/bin/bsdtar"

/// The compression types available.
public enum FBCompressionFormat: UInt {
  case GZIP = 1
  case ZSTD = 2
}

public enum ArchiveOperationsError: Error, LocalizedError {
  case pathDoesNotExist(path: String)

  public var errorDescription: String? {
    switch self {
    case let .pathDoesNotExist(path):
      return "Path for tarring \(path) doesn't exist"
    }
  }
}

/// Operations on zip/tar archives.
public enum FBArchiveOperations {

  /// Builds a command to extract from a file on disk.
  public static func commandToExtractArchive(
    atPath path: String,
    toPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    debugLogging: Bool
  ) -> [String] {
    let flags = flagStringForExtraction(overrideModificationTime: overrideMTime, debugLogging: debugLogging)
    return [flags, "-C", extractPath, "-f", path]
  }

  /// Extracts a tar or zip file archive to a directory. The file can be an uncompressed tar, a
  /// gzipped tar, or a zip.
  public static func extractArchive(
    atPath path: String,
    toPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    logger: any ControlCoreLogger
  ) -> FBFuture<NSString> {
    let arguments = commandToExtractArchive(
      atPath: path,
      toPath: extractPath,
      overrideModificationTime: overrideMTime,
      debugLogging: false)
    return FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath(BSDTarPath, arguments: arguments)
      .withStdErr(toLoggerAndErrorMessage: logger.debug())
      .withStdOut(to: logger.debug())
      .withTaskLifecycleLogging(to: logger)
      .runUntilCompletion(withAcceptableExitCodes: [0])
      .mapReplace(extractPath as NSString)
      .retyped()
  }

  /// Builds a command to extract via stdin.
  public static func commandToExtractFromStdIn(
    withExtractPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    compression: FBCompressionFormat,
    debugLogging: Bool
  ) -> [String] {
    switch compression {
    case .ZSTD:
      return ["--use-compress-program", "pzstd -d", overrideMTime ? "-xpm" : "-xp", "-C", extractPath, "-f", "-"]
    case .GZIP:
      let flags = flagStringForExtraction(overrideModificationTime: overrideMTime, debugLogging: debugLogging)
      return [flags, "-C", extractPath, "-f", "-"]
    }
  }

  /// Extracts a tar or zip stream archive to a directory. The stream can be an uncompressed tar, a
  /// gzipped tar, a zstd compressed tar, or a zip.
  public static func extractArchive(
    fromStream stream: FBProcessInput<AnyObject>,
    toPath extractPath: String,
    overrideModificationTime overrideMTime: Bool,
    logger: any ControlCoreLogger,
    compression: FBCompressionFormat
  ) -> FBFuture<NSString> {
    let arguments = commandToExtractFromStdIn(
      withExtractPath: extractPath,
      overrideModificationTime: overrideMTime,
      compression: compression,
      debugLogging: false)
    return FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath(BSDTarPath, arguments: arguments)
      .withStdIn(stream)
      .withStdErr(toLoggerAndErrorMessage: logger.debug())
      .withStdOut(to: logger.debug())
      .withTaskLifecycleLogging(to: logger)
      .runUntilCompletion(withAcceptableExitCodes: [0])
      .mapReplace(extractPath as NSString)
      .retyped()
  }

  /// Extracts a gzip from a stream to a single file. A plain gzip wrapping a single file is
  /// preferred when there's only a single file to transfer.
  public static func extractGzip(
    fromStream stream: FBProcessInput<AnyObject>,
    toPath extractPath: String,
    logger: any ControlCoreLogger
  ) -> FBFuture<NSString> {
    FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/gunzip", arguments: ["--to-stdout"])
      .withStdIn(stream)
      .withStdErr(toLoggerAndErrorMessage: logger.debug())
      .withStdOutPath(extractPath)
      .withTaskLifecycleLogging(to: logger)
      .runUntilCompletion(withAcceptableExitCodes: [0])
      .mapReplace(extractPath as NSString)
      .retyped()
  }

  /// Creates a gzipped archive compressing the data provided.
  public static func createGzipData(
    from input: FBProcessInput<AnyObject>,
    logger: any ControlCoreLogger
  ) -> FBFuture<FBSubprocess<AnyObject, NSData, AnyObject>> {
    FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/gzip", arguments: ["-", "--to-stdout"])
      .withStdIn(input)
      .withStdErr(toLoggerAndErrorMessage: logger)
      .withStdOutInMemoryAsData()
      .withTaskLifecycleLogging(to: logger)
      .runUntilCompletion(withAcceptableExitCodes: [0])
      .retyped()
  }

  /// Creates a gzip archive, returning a task that has an input stream attached to stdout. Read the
  /// input stream to obtain all of the gzip output of the file. To confirm that the stream has been
  /// correctly written, the caller should check the exit code of the returned task upon completion.
  public static func createGzip(
    forPath path: String,
    logger: any ControlCoreLogger
  ) -> FBFuture<FBSubprocess<NSNull, InputStream, AnyObject>> {
    FBProcessBuilder<NSNull, NSData, NSData>
      .withLaunchPath("/usr/bin/gzip", arguments: ["--to-stdout", path])
      .withStdErr(toLoggerAndErrorMessage: logger)
      .withStdOutToInputStream()
      .withTaskLifecycleLogging(to: logger)
      .start()
      .retyped()
  }

  /// Creates a gzipped tar archive, returning a task that has an input stream attached to stdout.
  /// Read the input stream to obtain the gzipped tar output. To confirm that the stream has been
  /// correctly written, the caller should check the exit code of the returned task upon completion.
  public static func createGzippedTar(
    forPath path: String,
    logger: any ControlCoreLogger
  ) -> FBFuture<FBSubprocess<NSNull, InputStream, AnyObject>> {
    do {
      let arguments = try gzippedTarArguments(forPath: path, logger: logger)
      return FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath(BSDTarPath, arguments: arguments)
        .withStdOutToInputStream()
        .withStdErr(toLoggerAndErrorMessage: logger)
        .withTaskLifecycleLogging(to: logger)
        .start()
        .retyped()
    } catch {
      return FBFuture(error: error)
    }
  }

  /// Creates a gzipped tar archive, returning the data of the tar.
  public static func createGzippedTarData(
    forPath path: String,
    queue: DispatchQueue,
    logger: any ControlCoreLogger
  ) -> FBFuture<NSData> {
    do {
      let arguments = try gzippedTarArguments(forPath: path, logger: logger)
      return FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath(BSDTarPath, arguments: arguments)
        .withStdOutInMemoryAsData()
        .withStdErr(toLoggerAndErrorMessage: logger)
        .withTaskLifecycleLogging(to: logger)
        .runUntilCompletion(withAcceptableExitCodes: [0])
        .onQueue(queue, map: { subprocess in subprocess.stdOut ?? NSData() })
        .retyped()
    } catch {
      return FBFuture(error: error)
    }
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
