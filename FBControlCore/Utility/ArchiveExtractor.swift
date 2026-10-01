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
/// Extraction is behind a protocol so the mechanism can be replaced without any
/// caller changing.
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

/// Unpacks a complete zip file in-process with `ZipExtractor`, and anything
/// else, including a zip `ZipExtractor` cannot read, with `fallback`.
/// `extractPath` must start empty: everything in it is removed before `fallback` runs.
public struct InProcessZipExtractor: ArchiveExtractor {

  private let fallback: any ArchiveExtractor

  public init(fallback: any ArchiveExtractor) {
    self.fallback = fallback
  }

  public func extract(
    _ source: ArchiveSource,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger
  ) async throws {
    guard case .filePath(let path) = source, Self.isZip(atPath: path) else {
      return try await fallback.extract(source, to: extractPath, options: options, logger: logger)
    }
    let start = Date()
    do {
      let summary = try await offCooperativePool {
        try ZipExtractor.extract(archiveAtPath: path, to: extractPath, overrideModificationTime: options.overrideModificationTime)
      }.get()
      logger.log("Extracted \(summary.files) files, \(summary.bytes) bytes, from \(path) in-process in \(String(format: "%.2f", Date().timeIntervalSince(start)))s")
      return
    } catch {
      logger.log("Extracting \(path) again with \(type(of: fallback)), as extracting it in-process failed: \(error)")
    }
    // Best effort: whatever cannot be removed is overwritten, or fails the fallback with its own error.
    for item in (try? FileManager.default.contentsOfDirectory(atPath: extractPath)) ?? [] {
      try? FileManager.default.removeItem(atPath: (extractPath as NSString).appendingPathComponent(item))
    }
    try await fallback.extract(source, to: extractPath, options: options, logger: logger)
  }

  private static func isZip(atPath path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else {
      return false
    }
    defer { try? handle.close() }
    return (try? handle.read(upToCount: 4)) == Data([0x50, 0x4B, 0x03, 0x04])
  }
}

/// Runs `work` off the cooperative pool, for work that blocks its thread.
func offCooperativePool<T>(_ work: @escaping () throws -> T) async -> Result<T, Error> {
  let work = HandedOver(work)
  return await withCheckedContinuation { (continuation: CheckedContinuation<HandedOver<Result<T, Error>>, Never>) in
    DispatchQueue.global(qos: .userInitiated).async {
      continuation.resume(returning: HandedOver(Result { try work.value() }))
    }
  }.value
}

/// A value passed from one thread to another, and used by one at a time.
struct HandedOver<Value>: @unchecked Sendable {
  let value: Value

  init(_ value: Value) {
    self.value = value
  }
}

/// The extractors available, and which one is used.
public enum ArchiveExtractors {

  public static let bsdTar: any ArchiveExtractor = BSDTarExtractor()

  public static let inProcessZip: any ArchiveExtractor = InProcessZipExtractor(fallback: bsdTar)

  /// The extractor every extraction goes through unless a caller names another.
  public static var `default`: any ArchiveExtractor { inProcessZip }
}
