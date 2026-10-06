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

  /// Extracts what `source` reads, which is already open and may already have been read from.
  func extract(
    from source: any ByteSource,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger
  ) async throws
}

// MARK: - Extracting a source

extension ArchiveExtractor {

  /// Writes what `source` reads into a stream this extractor reads.
  public func extract(
    from source: any ByteSource,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger
  ) async throws {
    let replayed = FBProcessInput<OutputStream>.fromStream()
    let input = HandedOver(replayed.retyped(FBProcessInput<AnyObject>.self))
    async let extraction: Void = extract(.stream(input.value), to: extractPath, options: options, logger: logger)
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
    // The extractor's error first: it is why writing to it would fail.
    try await extraction
    try written.get()
  }
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
      try await withAttached(input) { source in
        try await extract(from: source, to: extractPath, options: options, logger: logger)
      }
    }
  }

  public func extract(
    from source: any ByteSource,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger
  ) async throws {
    try await FBArchiveOperations.extractArchive(
      from: source,
      toPath: extractPath,
      overrideModificationTime: options.overrideModificationTime,
      logger: logger)
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
    try await withAttached(input) { source in
      try await extract(from: source, to: extractPath, options: options, logger: logger)
    }
  }

  public func extract(
    from source: any ByteSource,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger
  ) async throws {
    let start = Date()
    let source = HandedOver(source)
    let result = await offCooperativePool {
      try TarStreamExtractor.extract(
        from: source.value, to: extractPath,
        overrideModificationTime: options.overrideModificationTime)
    }
    switch try result.get() {
    case .notTar(let read):
      logger.log("Extracting a stream that is not a tar with \(type(of: fallback))")
      try await fallback.extract(from: read, to: extractPath, options: options, logger: logger)
    case .extracted(let summary, let waits):
      logger.log("\(summary.description(from: "a tar stream", since: start)), waiting \(String(format: "%.2f", waits.input))s for input and \(String(format: "%.2f", waits.writers))s for writers")
    }
  }
}

/// Calls `body` with a source reading `input`, detaching it however `body` returns.
func withAttached(_ input: FBProcessInput<AnyObject>, _ body: (any ByteSource) async throws -> Void) async throws {
  let fileDescriptor = try await bridgeFBFuture(input.attach()).fileDescriptor
  do {
    try await body(FileDescriptorSource(fileDescriptor))
  } catch {
    _ = try? await bridgeFBFuture(input.detach())
    throw error
  }
  _ = try? await bridgeFBFuture(input.detach())
}

/// Runs `work` off the cooperative pool, for work that blocks its thread.
///
/// Each call gets a thread of its own. The global queues run only a bounded number of threads at once, and blocking
/// work there that waits on other blocking work, such as a reader on a pipe whose writer is another call, deadlocks
/// once every one of those threads is waiting.
func offCooperativePool<T>(_ work: @escaping () throws -> T) async -> Result<T, Error> {
  let work = HandedOver(work)
  return await withCheckedContinuation { (continuation: CheckedContinuation<HandedOver<Result<T, Error>>, Never>) in
    let thread = Thread {
      continuation.resume(returning: HandedOver(Result { try work.value() }))
    }
    thread.qualityOfService = .userInitiated
    thread.start()
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
