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
    return (try? handle.read(upToCount: 4)) == ZipSignature.localHeaderBytes
  }
}

/// Unpacks a tar stream in-process with `TarStreamExtractor`, decompressing
/// zstd with the same decompressor `bsdtar` would run, and anything else with
/// `fallback`. A stream that turns out not to be a tar is passed on to
/// `fallback` as read, decompressed.
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
    let outcome: TarStreamExtractor.Outcome
    switch options.compression {
    case .GZIP:
      let fileDescriptor = try await bridgeFBFuture(input.attach()).fileDescriptor
      let result = await offCooperativePool {
        try TarStreamExtractor.extract(
          reading: TarStreamExtractor.reading(fileDescriptor: fileDescriptor), to: extractPath,
          overrideModificationTime: options.overrideModificationTime)
      }
      if case .success(.notTar(let prefix, let rest)) = result {
        return try await replay(prefix: prefix, rest: rest, to: extractPath, options: options, logger: logger) {
          _ = try? await bridgeFBFuture(input.detach())
        }
      }
      _ = try? await bridgeFBFuture(input.detach())
      outcome = try result.get()
    case .ZSTD:
      guard let decompressorPath = FBArchiveOperations.zstdDecompressorPath(searchPath: ProcessInfo.processInfo.environment["PATH"]) else {
        return try await fallback.extract(source, to: extractPath, options: options, logger: logger)
      }
      let decompressor = try await bridgeFBFuture(
        FBArchiveOperations.decompressZstd(fromStream: input, decompressorPath: decompressorPath, logger: logger))
      guard let stream = decompressor.stdOut else {
        throw TarExtractorError.corrupt("\(decompressorPath) has no output")
      }
      let read = Self.reading(stream)
      let result = await offCooperativePool {
        stream.open()
        return try TarStreamExtractor.extract(reading: read, to: extractPath, overrideModificationTime: options.overrideModificationTime)
      }
      if case .success(.notTar(let prefix, let rest)) = result {
        var decompressed = options
        decompressed.compression = .GZIP
        return try await replay(prefix: prefix, rest: rest, to: extractPath, options: decompressed, logger: logger) {
          _ = try await bridgeFBFuture(decompressor.exited(withCodes: [0]))
        }
      }
      guard case .success(let extracted) = result else {
        // Nothing reads the decompressor any more, so closing its output ends it.
        stream.close()
        outcome = try result.get()
        break
      }
      _ = try await bridgeFBFuture(decompressor.exited(withCodes: [0]))
      outcome = extracted
    }
    if case .extracted(let summary, let waits) = outcome {
      logger.log("\(summary.description(from: "a tar stream", since: start)), waiting \(String(format: "%.2f", waits.input))s for input and \(String(format: "%.2f", waits.writers))s for writers")
    }
  }

  /// Writes what was read, then the rest, into `fallback`.
  private func replay(
    prefix: Data,
    rest: @escaping TarStreamExtractor.Read,
    to extractPath: String,
    options: ArchiveExtractOptions,
    logger: any ControlCoreLogger,
    finished: () async throws -> Void
  ) async throws {
    logger.log("Extracting a stream that is not a tar with \(type(of: fallback))")
    let replayed = FBProcessInput<OutputStream>.fromStream()
    let input = HandedOver(replayed.retyped(FBProcessInput<AnyObject>.self))
    async let extraction: Void = fallback.extract(.stream(input.value), to: extractPath, options: options, logger: logger)
    let output = replayed.contents
    let written = await offCooperativePool {
      output.open()
      defer { output.close() }
      func write(_ bytes: UnsafeRawBufferPointer) throws {
        guard let base = bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count > 0 else {
          return
        }
        guard output.write(base, maxLength: bytes.count) == bytes.count else {
          throw output.streamError ?? TarExtractorError.corrupt("cannot write to \(type(of: fallback))")
        }
      }
      try prefix.withUnsafeBytes(write)
      var chunk = [UInt8](repeating: 0, count: 1 << 16)
      while true {
        let count = try chunk.withUnsafeMutableBytes { try rest($0) }
        guard count > 0 else {
          return
        }
        try chunk.withUnsafeBytes { try write(UnsafeRawBufferPointer(rebasing: $0[..<count])) }
      }
    }
    // The fallback's error first: it is why writing to it would fail.
    try await extraction
    try written.get()
    try await finished()
  }

  private static func reading(_ stream: InputStream) -> TarStreamExtractor.Read {
    // The stream closes itself at its end, after which reading it fails.
    var ended = false
    return { buffer in
      guard !ended, let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
        return 0
      }
      let count = stream.read(base, maxLength: buffer.count)
      guard count >= 0 else {
        throw stream.streamError ?? TarExtractorError.corrupt("the decompressor's output cannot be read")
      }
      ended = count == 0
      return count
    }
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
}
