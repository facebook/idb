/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import os

/// Where an artifact to install comes from.
public enum InstallSource {

  /// A path to the artifact itself, which needs no unpacking, or to an archive
  /// containing it.
  case localPath(String)

  /// An artifact or an archive containing it, to fetch over HTTP.
  case remoteURL(URL)

  /// An artifact or an archive containing it, which the caller's source reads as
  /// it arrives: a zip or a tar, either of them compressed or not, told apart by
  /// its first bytes. A dylib may also be the file itself, or the file gzipped.
  case stream(any ByteSource)
}

/// How to get from a source to an installable bundle.
public struct InstallOptions: Sendable {

  /// Discard the modification times recorded in the archive.
  public var overrideModificationTime: Bool

  /// The compression the producer applied, where the container does not say.
  public var compression: FBCompressionFormat

  public init(overrideModificationTime: Bool = false, compression: FBCompressionFormat = .GZIP) {
    self.overrideModificationTime = overrideModificationTime
    self.compression = compression
  }

  fileprivate var extractOptions: ArchiveExtractOptions {
    ArchiveExtractOptions(overrideModificationTime: overrideModificationTime)
  }
}

/// What staging an install source leaves on disk while its body runs.
public enum StagedTree: Sendable {

  /// A directory holding what an archive held, removed once the body returns.
  case extracted(URL)

  /// A single decompressed file, removed once the body returns.
  case file(URL)

  /// The caller's own item, which staging leaves where it is.
  case inPlace(URL)

  public var url: URL {
    switch self {
    case .extracted(let url), .file(let url), .inPlace(let url):
      return url
    }
  }

  /// Whether the item outlives the body, so storage can link to it rather than move it.
  public var isInPlace: Bool {
    switch self {
    case .inPlace:
      return true
    case .extracted, .file:
      return false
    }
  }
}

/// What staging learned about how it fetched and unpacked a source, beyond the progress of its stages.
public enum StagingReport: Equatable, Sendable {
  case route(ExtractionRoute)
  /// A download that completed. One that failed carries its report in its `InstallError.transferFailed`.
  case download(DownloadReport)
}

/// Gets an install source onto disk for every kind of artifact: fetching,
/// decompressing and extracting it into a directory that lives as long as the
/// caller's body, and reporting the extract stage as it goes.
public enum Staging {

  /// Stages `source`, which holds an artifact of `kind`, and calls `body` with what it left on disk.
  ///
  /// `onProgress` reports stages that start and stages that finish. A stage that
  /// fails reports no terminal event; the failure is the thrown error.
  ///
  /// `onReport` reports how a streamed or downloaded archive is unpacked once that is
  /// decided, so a failed extraction has reported it too, and again if it changes.
  public static func withMaterialized<T>(
    _ source: InstallSource,
    as kind: ArtifactKind,
    options: InstallOptions = InstallOptions(),
    totalStart: Date = Date(),
    downloadConfiguration: URLSessionConfiguration = .default,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void = { _ in },
    onReport: @escaping @Sendable (StagingReport) -> Void = { _ in },
    _ body: (StagedTree) async throws -> T
  ) async throws -> T {
    if case .localPath(let path) = source, !unpacks(source, as: kind) {
      return try await body(.inPlace(URL(fileURLWithPath: path)))
    }
    return try await temporaryDirectory.withTemporaryDirectory { stagingDirectory in
      let tree = try await stage(
        source, as: kind, in: stagingDirectory, options: options, totalStart: totalStart,
        downloadConfiguration: downloadConfiguration, temporaryDirectory: temporaryDirectory,
        logger: logger, onProgress: onProgress, onReport: onReport)
      return try await body(tree)
    }
  }

  /// Stages `source`, identifies the artifact of `kind` in it and installs that with `install`, reporting the install
  /// stage alongside the ones staging reports.
  ///
  /// `install` is told whether the artifact is in place; one that is not is deleted once `install` returns. `name` is
  /// what the installed artifact is known by on the target, for the stage's completion.
  public static func install<Installed>(
    _ source: InstallSource,
    as kind: ArtifactKind,
    options: InstallOptions = InstallOptions(),
    totalStart: Date = Date(),
    downloadConfiguration: URLSessionConfiguration = .default,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void = { _ in },
    onReport: @escaping @Sendable (StagingReport) -> Void = { _ in },
    name: (Installed) -> String,
    _ install: (_ artifact: Artifact, _ inPlace: Bool) async throws -> Installed
  ) async throws -> Installed {
    try await withMaterialized(
      source, as: kind, options: options, totalStart: totalStart, downloadConfiguration: downloadConfiguration,
      temporaryDirectory: temporaryDirectory, logger: logger, onProgress: onProgress, onReport: onReport
    ) { tree in
      let artifact: Artifact
      do {
        artifact = try kind.identify(in: tree, logger: logger)
      } catch let error as InstallError {
        throw error
      } catch {
        // The kinds other than an application identify through storage helpers shared with callers that aren't
        // installing anything, so they report failures unclassified; this is the boundary that knows better.
        throw InstallError.unidentifiable(kind: kind, underlying: error)
      }
      let installStart = Date()
      onProgress(.installStarted(timing: .measure(stageStart: installStart, totalStart: totalStart), artifactPath: artifact.url.path))
      let installed = try await install(artifact, tree.isInPlace)
      onProgress(
        .installCompleted(
          timing: .measure(stageStart: installStart, totalStart: totalStart), artifactPath: artifact.url.path, name: name(installed)))
      return installed
    }
  }

  /// Whether staging `source` unpacks it. What is unpacked belongs to staging,
  /// which removes it afterwards, so the body may move it away; anything else is
  /// the caller's own, and must be left where it is.
  ///
  /// The same rule for every kind: a directory is the artifact, and so is a file
  /// for a kind whose artifact can be one -- a dylib or a test run -- unless its
  /// first bytes say it is an archive or compressed. Any other file is an archive.
  public static func unpacks(_ source: InstallSource, as kind: ArtifactKind) -> Bool {
    guard case .localPath(let path) = source else {
      return true
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
      return false
    }
    guard kind.canBeAFile else {
      return true
    }
    guard let handle = FileHandle(forReadingAtPath: path) else {
      return false
    }
    defer { try? handle.close() }
    let head = (try? handle.read(upToCount: 512)) ?? Data()
    switch ArchiveFormat.detect(head) {
    case .zip, .zstdZip, .zstd, .gzip:
      return true
    case .other:
      return head.count >= 263 && head[head.startIndex + 257..<head.startIndex + 262].elementsEqual(Array("ustar".utf8))
    case .undetermined:
      return false
    }
  }

  // MARK: - Stages

  private static func stage(
    _ source: InstallSource,
    as kind: ArtifactKind,
    in stagingDirectory: URL,
    options: InstallOptions,
    totalStart: Date,
    downloadConfiguration: URLSessionConfiguration,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void,
    onReport: @escaping @Sendable (StagingReport) -> Void
  ) async throws -> StagedTree {
    let extractPath = stagingDirectory.path
    switch source {
    case .localPath(let path):
      return try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
        if case .dylib(let name) = kind {
          let descriptor = open(path, O_RDONLY | O_CLOEXEC)
          guard descriptor >= 0 else {
            throw POSIXError.current
          }
          defer { close(descriptor) }
          if let file = try await stageSingleFile(PeekableSource(FileDescriptorSource(descriptor)), named: name, in: stagingDirectory) {
            return .file(file)
          }
        }
        try await ArchiveExtractors.default.extract(fromFile: path, to: extractPath, options: options.extractOptions, logger: logger)
        return .extracted(stagingDirectory)
      }
    case .stream(let source):
      return try await temporaryDirectory.withTemporaryDirectory { spoolDirectory in
        try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
          try await stagePayload(
            source, as: kind, with: ArchiveExtractors.stream(options.compression), in: stagingDirectory, spoolingIn: spoolDirectory,
            options: options, logger: logger, onReport: onReport)
        }
      }
    case .remoteURL(let url):
      return try await temporaryDirectory.withTemporaryDirectory { spoolDirectory in
        let staged = OSAllocatedUnfairLock<StagedTree?>(initialState: nil)
        try await download(
          url, extractingTo: extractPath, totalStart: totalStart, configuration: downloadConfiguration,
          logger: logger, onProgress: onProgress, onReport: onReport
        ) { spool in
          let tree = try await spool.reading { source in
            try await stagePayload(
              source, as: kind, with: ArchiveExtractors.inProcess, in: stagingDirectory, spoolingIn: spoolDirectory,
              options: options, logger: logger, onReport: onReport)
          }
          staged.withLock { $0 = tree }
        }
        return staged.withLock { $0 } ?? .extracted(stagingDirectory)
      }
    }
  }

  /// Stages what `source` reads with `extractor`, unless `kind` is a dylib that arrives as a single file. A zip is
  /// spooled into `spoolDirectory` as it is extracted.
  private static func stagePayload(
    _ source: any ByteSource,
    as kind: ArtifactKind,
    with extractor: SniffingExtractor,
    in stagingDirectory: URL,
    spoolingIn spoolDirectory: URL,
    options: InstallOptions,
    logger: any ControlCoreLogger,
    onReport: @escaping @Sendable (StagingReport) -> Void
  ) async throws -> StagedTree {
    let peekable = PeekableSource(source)
    if case .dylib(let name) = kind, let file = try await stageSingleFile(peekable, named: name, in: stagingDirectory) {
      return .file(file)
    }
    try await extractor.extract(
      from: peekable, spoolingIn: spoolDirectory, to: stagingDirectory.path, options: options.extractOptions, logger: logger
    ) { onReport(.route($0)) }
    return .extracted(stagingDirectory)
  }

  /// A dylib arrives as the file itself or gzipped, which writes it into `directory` as `name`; anything else is an
  /// archive holding it, and `nil`. A gzip can't be told from a gzipped tar by its first bytes, so for a dylib a gzip
  /// is taken to be the one file, as clients send them.
  private static func stageSingleFile(_ source: PeekableSource, named name: String, in directory: URL) async throws -> URL? {
    let handedOver = HandedOver(source)
    let head = try await offCooperativePool { try handedOver.value.peek(ArchiveFormat.sniffLength) }.get()
    let file = directory.appendingPathComponent(name)
    if ArchiveFormat.detect(head) == .gzip {
      try await FBArchiveOperations.extractGzip(from: source, toPath: file.path)
      return file
    }
    guard isMachO(head) else {
      return nil
    }
    try await offCooperativePool {
      FileManager.default.createFile(atPath: file.path, contents: nil)
      let output = try FileHandle(forWritingTo: file)
      defer { try? output.close() }
      var chunk = [UInt8](repeating: 0, count: 1 << 16)
      while case let count = try chunk.withUnsafeMutableBytes({ try handedOver.value.read(into: $0) }), count > 0 {
        try output.write(contentsOf: chunk[..<count])
      }
    }.get()
    return file
  }

  /// Whether `head` starts a Mach-O file, thin or fat, of either byte order.
  private static func isMachO(_ head: Data) -> Bool {
    guard head.count >= 4 else {
      return false
    }
    let magic = head.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    return [0xFEED_FACE, 0xFEED_FACF, 0xCEFA_EDFE, 0xCFFA_EDFE, 0xCAFE_BABE, 0xBEBA_FECA, 0xCAFE_BABF, 0xBFBA_FECA].contains(magic)
  }

  /// `extract` reads the transfer as it arrives rather than waiting for a
  /// complete file, so the download and extract stages overlap and each times
  /// against its own start.
  private static func download(
    _ url: URL,
    extractingTo extractPath: String,
    totalStart: Date,
    configuration: URLSessionConfiguration,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void,
    onReport: @escaping @Sendable (StagingReport) -> Void,
    extract: @escaping @Sendable (DownloadSpool) async throws -> Void
  ) async throws {
    let downloadStart = Date()
    onProgress(.downloadStarted(timing: .measure(stageStart: downloadStart, totalStart: totalStart), url: url))

    // SAFETY: written only from the download's delegate queue, which is serial,
    // and read once after awaiting the transfer, which that same queue resolves
    // after delivering its last chunk.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) var progress = DownloadProgressState(startedAt: downloadStart)
    let download = DataDownloadInput.dataDownload(withURL: url, configuration: configuration, logger: logger) { event in
      switch event {
      case .response(let expectedContentLength):
        progress.observe(expectedContentLength: expectedContentLength)
      case .data(let byteCount):
        guard let update = progress.track(byteCount: byteCount) else {
          return
        }
        onProgress(
          .downloadProgress(
            timing: .measure(stageStart: downloadStart, totalStart: totalStart),
            bytesDownloaded: update.bytesDownloaded,
            totalBytes: update.totalBytes))
      }
    }

    let extractionFailure = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)
    // An extraction that has failed has no use for the rest of the transfer.
    @Sendable func extractStoppingTheDownloadOnFailure() async throws {
      do {
        try await extract(download.spool)
      } catch {
        extractionFailure.withLock { $0 = error }
        download.cancel()
        throw error
      }
    }

    try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
      try await withTaskCancellationHandler {
        async let extraction: Void = extractStoppingTheDownloadOnFailure()
        // The transfer's outcome first: the extractor only sees bytes and then an
        // end of file, so a failed transfer looks to it like a short archive. A
        // transfer stopped because the extraction failed reports the extraction.
        let report: DownloadReport
        do {
          report = try await download.completed()
        } catch {
          throw extractionFailure.withLock { $0 } ?? error
        }
        onReport(.download(report))
        onProgress(
          .downloadCompleted(
            timing: .measure(stageStart: downloadStart, totalStart: totalStart),
            totalBytes: progress.downloadedBytes))
        try await extraction
      } onCancel: {
        download.cancel()
      }
    }
  }

  @discardableResult
  private static func runExtractStage<T>(
    to extractPath: String,
    totalStart: Date,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void,
    operation: () async throws -> T
  ) async throws -> T {
    let stageStart = Date()
    onProgress(.extractStarted(timing: .measure(stageStart: stageStart, totalStart: totalStart), destinationPath: extractPath))
    let result: T
    do {
      result = try await operation()
    } catch let error as InstallError {
      // Already classified: the transfer is awaited inside this stage, and a
      // dropped connection is not a corrupt archive.
      throw error
    } catch {
      // The extractor is shared with callers that are not installing anything, so
      // it reports failures unclassified; this is the boundary that knows better.
      throw InstallError.extractionFailed(underlying: error)
    }
    onProgress(.extractCompleted(timing: .measure(stageStart: stageStart, totalStart: totalStart), destinationPath: extractPath))
    return result
  }
}
