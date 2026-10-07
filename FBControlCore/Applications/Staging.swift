/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where an artifact to install comes from.
public enum InstallSource {

  /// A path to the artifact itself, which needs no unpacking, or, for an
  /// application, to an archive containing one.
  case localPath(String)

  /// An archive to fetch over HTTP.
  case remoteURL(URL)

  /// An archive arriving on a pipe that the caller is writing to: a zip or a
  /// tar, either of them compressed or not, told apart by its first bytes.
  case stream(BytePipe)

  /// A single file, gzipped, arriving on a pipe that the caller is writing to;
  /// it is staged as `name`.
  case gzippedFile(BytePipe, name: String)
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

/// How staging unpacked an archive that arrived as a stream: what its first bytes
/// said it was, and what extracted it.
public struct ExtractionRoute: Equatable, Sendable {

  public enum Extractor: String, Sendable {
    case inProcessTar = "tar_inprocess"
    case bsdTar = "bsdtar"
    /// A zip extracted as it arrived.
    case zipStream = "zip_stream"
    /// A zip extracted from its spooled copy, after extracting it as it arrived failed.
    case zipSpool = "zip_spool"
  }

  public let format: ArchiveFormat
  public let extractor: Extractor

  public init(format: ArchiveFormat, extractor: Extractor) {
    self.format = format
    self.extractor = extractor
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
        source, in: stagingDirectory, options: options, totalStart: totalStart,
        downloadConfiguration: downloadConfiguration, temporaryDirectory: temporaryDirectory,
        logger: logger, onProgress: onProgress, onReport: onReport)
      return try await body(tree)
    }
  }

  /// Whether staging `source` unpacks it. What is unpacked belongs to staging,
  /// which removes it afterwards, so the body may move it away; anything else is
  /// the caller's own, and must be left where it is. Only an application's local
  /// path may be an archive.
  public static func unpacks(_ source: InstallSource, as kind: ArtifactKind) -> Bool {
    guard case .localPath(let path) = source else {
      return true
    }
    switch kind {
    case .application:
      return !BundleDescriptor.isApplication(atPath: path)
    case .xctest, .framework, .dylib, .dsym:
      return false
    }
  }

  // MARK: - Stages

  private static func stage(
    _ source: InstallSource,
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
    case .gzippedFile(let pipe, let name):
      let file = stagingDirectory.appendingPathComponent(name)
      try await runExtractStage(to: file.path, totalStart: totalStart, onProgress: onProgress) {
        try await pipe.reading { source in
          try await FBArchiveOperations.extractGzip(from: source, toPath: file.path, logger: logger)
        }
      }
      return .file(file)
    case .localPath(let path):
      try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
        try await ArchiveExtractors.default.extract(
          fromFile: path, to: extractPath, options: options.extractOptions, logger: logger)
      }
    case .stream(let pipe):
      // The caller owns the writing end, so a writer that fails partway reaches
      // the extractor as nothing more than a short archive. Only the caller holds
      // the writer's own error.
      try await temporaryDirectory.withTemporaryDirectory { spoolDirectory in
        try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
          try await pipe.reading { source in
            try await extractStream(
              source, tarExtractor: ArchiveExtractors.stream(options.compression), spoolingIn: spoolDirectory,
              to: extractPath, options: options, logger: logger, onReport: onReport)
          }
        }
      }
    case .remoteURL(let url):
      try await temporaryDirectory.withTemporaryDirectory { spoolDirectory in
        try await downloadAndExtract(
          url, to: extractPath, options: options, totalStart: totalStart,
          configuration: downloadConfiguration, spoolDirectory: spoolDirectory,
          logger: logger, onProgress: onProgress, onReport: onReport)
      }
    }
    return .extracted(stagingDirectory)
  }

  /// The extractor reads the transfer as it arrives rather than waiting for a
  /// complete file, so the download and extract stages overlap and each times
  /// against its own start.
  ///
  /// A zip is spooled into `spoolDirectory` as it is extracted.
  private static func downloadAndExtract(
    _ url: URL,
    to extractPath: String,
    options: InstallOptions,
    totalStart: Date,
    configuration: URLSessionConfiguration,
    spoolDirectory: URL,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void,
    onReport: @escaping @Sendable (StagingReport) -> Void
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

    try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
      async let extraction: Void = extractDownload(
        download.pipe, spoolingIn: spoolDirectory, to: extractPath, options: options, logger: logger, onReport: onReport)
      // The transfer's outcome first: the extractor only sees bytes and then an
      // end of file, so a failed transfer looks to it like a short archive.
      onReport(.download(try await download.completed()))
      onProgress(
        .downloadCompleted(
          timing: .measure(stageStart: downloadStart, totalStart: totalStart),
          totalBytes: progress.downloadedBytes))
      try await extraction
    }
  }

  private static func extractDownload(
    _ pipe: BytePipe,
    spoolingIn spoolDirectory: URL,
    to extractPath: String,
    options: InstallOptions,
    logger: any ControlCoreLogger,
    onReport: @escaping @Sendable (StagingReport) -> Void
  ) async throws {
    try await pipe.reading { source in
      try await extractStream(
        source, tarExtractor: ArchiveExtractors.inProcessTar, spoolingIn: spoolDirectory,
        to: extractPath, options: options, logger: logger, onReport: onReport)
    }
  }

  /// Decides on the first bytes, so that only a zip is spooled; anything else goes to `tarExtractor`.
  private static func extractStream(
    _ source: any ByteSource,
    tarExtractor: any ArchiveExtractor,
    spoolingIn spoolDirectory: URL,
    to extractPath: String,
    options: InstallOptions,
    logger: any ControlCoreLogger,
    onReport: @escaping @Sendable (StagingReport) -> Void
  ) async throws {
    let peekable = HandedOver(PeekableSource(source))
    let head = try await offCooperativePool { try peekable.value.peek(ArchiveFormat.sniffLength) }.get()
    let format = ArchiveFormat.detect(head)
    switch format {
    case .zip, .zstdZip:
      onReport(.route(ExtractionRoute(format: format, extractor: .zipStream)))
      try await extractZipStream(peekable.value, spoolingIn: spoolDirectory, to: extractPath, options: options, logger: logger) {
        onReport(.route(ExtractionRoute(format: format, extractor: .zipSpool)))
      }
    case .zstd, .gzip, .other, .undetermined:
      onReport(.route(ExtractionRoute(format: format, extractor: tarExtractor is BSDTarExtractor ? .bsdTar : .inProcessTar)))
      try await tarExtractor.extract(from: peekable.value, to: extractPath, options: options.extractOptions, logger: logger)
    }
  }

  /// Extracts a zip, or a zstd-compressed zip, as it arrives, spooling it into
  /// `spoolDirectory` as it is read, since symlinks and permissions are recorded
  /// only in the central directory at its end, which a reader of the stream never
  /// reaches. A zip the stream reader cannot handle is extracted again from the
  /// spooled copy, after calling `onSpoolFallback`.
  private static func extractZipStream(
    _ source: any ByteSource,
    spoolingIn spoolDirectory: URL,
    to extractPath: String,
    options: InstallOptions,
    logger: any ControlCoreLogger,
    onSpoolFallback: () -> Void
  ) async throws {
    let spoolPath = spoolDirectory.appendingPathComponent("archive.zip").path
    let source = HandedOver(source)
    let start = Date()
    let streamed = try await offCooperativePool {
      try spool(source.value, to: spoolPath, extractingTo: extractPath, overrideModificationTime: options.overrideModificationTime)
    }.get()
    do {
      let summary = try streamed.get()
      try ZipCentralDirectory(archiveAtPath: spoolPath).repair(extractedAt: extractPath, overrideModificationTime: options.overrideModificationTime)
      logger.log(summary.description(from: "a zip stream", since: start))
      return
    } catch {
      logger.log("Extracting the spooled zip at \(spoolPath), as extracting it as it arrived failed: \(error)")
    }
    onSpoolFallback()
    ArchiveExtraction.removeContents(of: extractPath)
    try await ArchiveExtractors.default.extract(
      fromFile: spoolPath, to: extractPath, options: options.extractOptions, logger: logger)
  }

  /// Reads `source` to its end, extracting it as it goes and writing it,
  /// decompressed, to `spoolPath`. Throws if the spooled zip is incomplete;
  /// whether extracting it as it arrived worked is the result.
  private static func spool(
    _ source: any ByteSource,
    to spoolPath: String,
    extractingTo extractPath: String,
    overrideModificationTime: Bool
  ) throws -> Result<ArchiveExtractionSummary, Error> {
    do {
      guard FileManager.default.createFile(atPath: spoolPath, contents: nil) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: spoolPath])
      }
      let file = try FileHandle(forWritingTo: URL(fileURLWithPath: spoolPath))
      defer { try? file.close() }
      let tee = TeeSource(try ZstdSource.ifZstd(source), to: file)
      let streamed = Result {
        try ZipStreamExtractor.extract(from: tee, to: extractPath, overrideModificationTime: overrideModificationTime)
      }
      try tee.drain()
      return streamed
    } catch {
      // Leaves nothing writing to the input blocked on it.
      try? source.drain()
      throw error
    }
  }

  private static func runExtractStage(
    to extractPath: String,
    totalStart: Date,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void,
    operation: () async throws -> Void
  ) async throws {
    let stageStart = Date()
    onProgress(.extractStarted(timing: .measure(stageStart: stageStart, totalStart: totalStart), destinationPath: extractPath))
    do {
      try await operation()
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
  }
}
