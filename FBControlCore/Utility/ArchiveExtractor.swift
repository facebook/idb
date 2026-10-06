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

  public init(overrideModificationTime: Bool = false) {
    self.overrideModificationTime = overrideModificationTime
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
    switch source {
    case .filePath(let path):
      _ = try await FBArchiveOperations.extractArchive(
        atPath: path,
        toPath: extractPath,
        overrideModificationTime: options.overrideModificationTime,
        logger: logger)
    case .stream(let input):
      _ = try await bridgeFBFuture(
        FBArchiveOperations.extractArchive(
          fromStream: input,
          toPath: extractPath,
          overrideModificationTime: options.overrideModificationTime,
          logger: logger))
    }
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
      logger.log(summary.description(from: path, since: start))
      return
    } catch {
      logger.log("Extracting \(path) again with \(type(of: fallback)), as extracting it in-process failed: \(error)")
    }
    ArchiveExtraction.removeContents(of: extractPath)
    try await fallback.extract(source, to: extractPath, options: options, logger: logger)
  }

  private static func isZip(atPath path: String) -> Bool {
    guard let handle = FileHandle(forReadingAtPath: path) else {
      return false
    }
    defer { try? handle.close() }
    return ArchiveFormat.detect((try? handle.read(upToCount: ArchiveFormat.detectableLength)) ?? Data()) == .zip
  }
}

/// Unpacks a tar stream in-process with `TarStreamExtractor`, and anything else
/// with `fallback`. A stream that turns out not to be a tar is passed on to
/// `fallback` as read, already decompressed.
public struct InProcessTarExtractor: ArchiveExtractor {

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
    guard case .stream(let input) = source else {
      return try await fallback.extract(source, to: extractPath, options: options, logger: logger)
    }
    let start = Date()
    let fileDescriptor = try await bridgeFBFuture(input.attach()).fileDescriptor
    let result = await offCooperativePool {
      try TarStreamExtractor.extract(
        from: FileDescriptorSource(fileDescriptor), to: extractPath,
        overrideModificationTime: options.overrideModificationTime)
    }
    if case .success(.notTar(let read)) = result {
      try await replay(read, to: extractPath, options: options, logger: logger)
      _ = try? await bridgeFBFuture(input.detach())
      return
    }
    _ = try? await bridgeFBFuture(input.detach())
    if case .extracted(let summary, let waits) = try result.get() {
      logger.log("\(summary.description(from: "a tar stream", since: start)), waiting \(String(format: "%.2f", waits.input))s for input and \(String(format: "%.2f", waits.writers))s for writers")
    }
  }

  /// Writes what `source` reads into `fallback`.
  private func replay(
    _ source: any ByteSource,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger
  ) async throws {
    logger.log("Extracting a stream that is not a tar with \(type(of: fallback))")
    let replayed = FBProcessInput<OutputStream>.fromStream()
    let input = HandedOver(replayed.retyped(FBProcessInput<AnyObject>.self))
    async let extraction: Void = fallback.extract(.stream(input.value), to: extractPath, options: options, logger: logger)
    let output = replayed.contents
    let source = HandedOver(source)
    let written = await offCooperativePool {
      output.open()
      defer { output.close() }
      var chunk = [UInt8](repeating: 0, count: 1 << 16)
      while true {
        let count = try chunk.withUnsafeMutableBytes { try source.value.read(into: $0) }
        guard count > 0 else {
          return
        }
        try chunk.withUnsafeBytes { try output.writeAll(UnsafeRawBufferPointer(rebasing: $0[..<count])) }
      }
    }
    // The fallback's error first: it is why writing to it would fail.
    try await extraction
    try written.get()
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

  public static let inProcessTar: any ArchiveExtractor = InProcessTarExtractor(fallback: bsdTar)

  public static let inProcessZip: any ArchiveExtractor = InProcessZipExtractor(fallback: inProcessTar)

  /// The extractor every extraction goes through unless a caller names another.
  public static var `default`: any ArchiveExtractor { inProcessZip }

  /// The extractor for a stream that a client compresses as it sends. `bsdtar`
  /// reads a gzip twice as fast as an in-process reader starved of input, but
  /// macOS has no zstd decompressor for it to run.
  public static func stream(_ compression: FBCompressionFormat) -> any ArchiveExtractor {
    switch compression {
    case .GZIP:
      return bsdTar
    case .ZSTD:
      return inProcessTar
    }
  }
}
