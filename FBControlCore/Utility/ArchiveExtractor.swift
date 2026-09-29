/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where an archive is read from.
///
/// The distinction matters to the extractor rather than to the caller: a file can
/// be seeked, so a format that keeps its index at the end of the archive can be
/// read in full, whereas a stream can only be read forwards.
public enum ArchiveSource {
  case filePath(String)
  case stream(FBProcessInput<AnyObject>)
}

/// How to unpack, as opposed to what to unpack.
public struct ArchiveExtractOptions: Sendable {

  /// Discard the modification times recorded in the archive, stamping everything
  /// written with the current time instead.
  public var overrideModificationTime: Bool

  /// The compression the producer applied. This only chooses between gzip and
  /// zstd; the container is detected from the bytes, so it has no bearing on a
  /// zip.
  public var compression: FBCompressionFormat

  public init(
    overrideModificationTime: Bool = false,
    compression: FBCompressionFormat = .GZIP
  ) {
    self.overrideModificationTime = overrideModificationTime
    self.compression = compression
  }
}

/// Unpacks an archive into a directory.
///
/// Extraction is behind a protocol so the mechanism can be replaced: an
/// in-process implementation would conform here, and no caller would change.
public protocol ArchiveExtractor: Sendable {

  func extract(
    _ source: ArchiveSource,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger
  ) async throws
}

/// Unpacks by running `bsdtar` as a subprocess, reading either a file it is
/// pointed at or its own stdin.
public struct BSDTarExtractor: ArchiveExtractor {

  public init() {}

  public func extract(
    _ source: ArchiveSource,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger
  ) async throws {
    let future: FBFuture<NSString>
    switch source {
    case .filePath(let path):
      future = FBArchiveOperations.extractArchive(
        atPath: path,
        toPath: extractPath,
        overrideModificationTime: options.overrideModificationTime,
        logger: logger)
    case .stream(let input):
      future = FBArchiveOperations.extractArchive(
        fromStream: input,
        toPath: extractPath,
        overrideModificationTime: options.overrideModificationTime,
        logger: logger,
        compression: options.compression)
    }
    _ = try await bridgeFBFuture(future)
  }
}

/// The extractors available, and which one is used.
public enum ArchiveExtractors {

  public static let bsdTar: any ArchiveExtractor = BSDTarExtractor()

  /// The extractor every extraction goes through unless a caller names another.
  public static var `default`: any ArchiveExtractor { bsdTar }
}
