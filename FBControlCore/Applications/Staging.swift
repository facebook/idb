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

  /// An archive arriving on a process input that the caller is writing to.
  case processInput(FBProcessInput<AnyObject>)

  /// A zip arriving on a process input that the caller is writing to, and also
  /// writing to `spoolPath`; `spooled` returns once that file is complete.
  case zipStream(FBProcessInput<AnyObject>, spoolPath: String, spooled: @Sendable () async throws -> Void)

  /// A single file, gzipped, arriving on a process input that the caller is
  /// writing to; it is staged as `name`.
  case gzippedFile(FBProcessInput<AnyObject>, name: String)
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
    ArchiveExtractOptions(overrideModificationTime: overrideModificationTime, compression: compression)
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

/// Gets an install source onto disk for every kind of artifact: fetching,
/// decompressing and extracting it into a directory that lives as long as the
/// caller's body, and reporting the extract stage as it goes.
public enum Staging {

  /// Stages `source`, which holds an artifact of `kind`, and calls `body` with what it left on disk.
  ///
  /// `onProgress` reports stages that start and stages that finish. A stage that
  /// fails reports no terminal event; the failure is the thrown error.
  public static func withMaterialized<T>(
    _ source: InstallSource,
    as kind: ArtifactKind,
    options: InstallOptions = InstallOptions(),
    totalStart: Date = Date(),
    downloadConfiguration: URLSessionConfiguration = .default,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void = { _ in },
    _ body: (StagedTree) async throws -> T
  ) async throws -> T {
    if case .localPath(let path) = source, !unpacks(source, as: kind) {
      return try await body(.inPlace(URL(fileURLWithPath: path)))
    }
    return try await temporaryDirectory.withTemporaryDirectory { stagingDirectory in
      let tree = try await stage(
        source, in: stagingDirectory, options: options, totalStart: totalStart,
        downloadConfiguration: downloadConfiguration, temporaryDirectory: temporaryDirectory,
        logger: logger, onProgress: onProgress)
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
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void
  ) async throws -> StagedTree {
    let extractPath = stagingDirectory.path
    switch source {
    case .gzippedFile(let input, let name):
      let file = stagingDirectory.appendingPathComponent(name)
      try await runExtractStage(to: file.path, totalStart: totalStart, onProgress: onProgress) {
        _ = try await bridgeFBFuture(FBArchiveOperations.extractGzip(fromStream: input, toPath: file.path, logger: logger))
      }
      return .file(file)
    case .localPath(let path):
      try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
        try await ArchiveExtractors.default.extract(
          .filePath(path), to: extractPath, options: options.extractOptions, logger: logger)
      }
    case .processInput(let input):
      // The caller owns the writing end, so a writer that fails partway reaches
      // the extractor as nothing more than a short archive. Only the caller holds
      // the writer's own error.
      // Not extracted in-process: with a client that compresses as it sends, the
      // in-process reader is starved for input and takes twice as long as `bsdtar`.
      try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
        try await ArchiveExtractors.bsdTar.extract(
          .stream(input), to: extractPath, options: options.extractOptions, logger: logger)
      }
    case .zipStream(let input, let spoolPath, let spooled):
      try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
        try await extractZipStream(
          input, spoolPath: spoolPath, spooled: spooled, to: extractPath, options: options, logger: logger)
      }
    case .remoteURL(let url):
      try await temporaryDirectory.withTemporaryDirectory { spoolDirectory in
        try await downloadAndExtract(
          url, to: extractPath, options: options, totalStart: totalStart,
          configuration: downloadConfiguration,
          spoolPath: spoolDirectory.appendingPathComponent("download.zip").path,
          logger: logger, onProgress: onProgress)
      }
    }
    return .extracted(stagingDirectory)
  }

  /// The extractor reads the transfer as it arrives rather than waiting for a
  /// complete file, so the download and extract stages overlap and each times
  /// against its own start.
  ///
  /// A zip is also written to `spoolPath`, since it records symlinks and
  /// permissions only in the central directory at its end, which a reader of the
  /// transfer never reaches.
  private static func downloadAndExtract(
    _ url: URL,
    to extractPath: String,
    options: InstallOptions,
    totalStart: Date,
    configuration: URLSessionConfiguration,
    spoolPath: String,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void
  ) async throws {
    let downloadStart = Date()
    onProgress(.downloadStarted(timing: .measure(stageStart: downloadStart, totalStart: totalStart), url: url))

    // SAFETY: written only from the download's delegate queue, which is serial,
    // and read once after awaiting the transfer, which that same queue resolves
    // after delivering its last chunk.
    // patternlint-disable-next-line swift-nonisolated-unsafe
    nonisolated(unsafe) var progress = DownloadProgressState(startedAt: downloadStart)
    let router = ZipSpoolingConsumer(spoolPath: spoolPath)
    let download = DataDownloadInput.dataDownload(
      withURL: url, configuration: configuration, logger: logger,
      interposing: { router.forwardingTo($0) }
    ) { event in
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

    func downloadCompleted() async throws {
      try await download.completed()
      onProgress(
        .downloadCompleted(
          timing: .measure(stageStart: downloadStart, totalStart: totalStart),
          totalBytes: progress.downloadedBytes))
    }

    try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
      switch try await router.route() {
      case .stream:
        async let extraction: Void = ArchiveExtractors.default.extract(
          .stream(download.input), to: extractPath, options: options.extractOptions, logger: logger)
        // The transfer's outcome first: the extractor only sees bytes and then an
        // end of file, so a failed transfer looks to it like a short archive.
        try await downloadCompleted()
        try await extraction
      case .spooled:
        logger.log("Spooling the zip at \(url) to \(spoolPath) as it is extracted")
        try await extractZipStream(
          download.input, spoolPath: spoolPath,
          spooled: {
            try await downloadCompleted()
            try router.checkSpool()
          },
          to: extractPath, options: options, logger: logger)
      }
    }
  }

  /// Extracts a zip as it arrives, then applies what only the central directory
  /// at its end records once the spooled copy is complete. A zip the stream
  /// reader cannot handle is extracted again from the spooled copy.
  private static func extractZipStream(
    _ input: FBProcessInput<AnyObject>,
    spoolPath: String,
    spooled: () async throws -> Void,
    to extractPath: String,
    options: InstallOptions,
    logger: any ControlCoreLogger
  ) async throws {
    var streamError: Error?
    do {
      try await ZipStreamExtractor.extract(
        input, to: extractPath, overrideModificationTime: options.extractOptions.overrideModificationTime, logger: logger)
    } catch {
      streamError = error
    }
    try await spooled()
    do {
      if let streamError {
        throw streamError
      }
      try ZipCentralDirectory(archiveAtPath: spoolPath).repair(extractedAt: extractPath)
      return
    } catch {
      logger.log("Extracting the spooled zip at \(spoolPath), as extracting it as it arrived failed: \(error)")
    }
    ArchiveExtraction.removeContents(of: extractPath)
    try await ArchiveExtractors.default.extract(
      .filePath(spoolPath), to: extractPath, options: options.extractOptions, logger: logger)
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

/// Sends a download on to the extractor, and to a file as well if it is a zip,
/// deciding on the first bytes.
// SAFETY: everything but `decision` and `spoolError` is touched only from the
// download's serial delegate queue, after `forwardingTo` is called before the
// download starts; those two are read from the awaiting task under `lock`.
// patternlint-disable-next-line unchecked-sendable
private final class ZipSpoolingConsumer: NSObject, DataConsumer, @unchecked Sendable {

  enum Route {
    case stream
    case spooled
  }

  private let spoolPath: String
  private let decided = FBMutableFuture<NSNull>()
  private let lock = NSLock()
  private var downstream: (any DataConsumer)?
  private var head = Data()
  private var spool: FileHandle?
  private var decision: Route?
  private var spoolError: Error?

  init(spoolPath: String) {
    self.spoolPath = spoolPath
  }

  func forwardingTo(_ consumer: any DataConsumer) -> any DataConsumer {
    downstream = consumer
    return self
  }

  /// Waits for the first bytes, or the end of a transfer too short to have any.
  func route() async throws -> Route {
    _ = try await bridgeFBFuture(decided)
    // swiftlint:disable:next force_unwrapping
    return lock.withLock { decision! }
  }

  /// Throws if the zip could not be written in full; call once the transfer is complete.
  func checkSpool() throws {
    if let error = lock.withLock({ spoolError }) {
      throw error
    }
  }

  func consumeData(_ data: Data) {
    guard let route = lock.withLock({ decision }) else {
      head.append(data)
      if head.count >= ArchiveFormat.detectableLength {
        decide()
      }
      return
    }
    write(data, to: route)
  }

  func consumeEndOfFile() {
    if lock.withLock({ decision == nil }) {
      decide()
    }
    try? spool?.close()
    downstream?.consumeEndOfFile()
  }

  private func decide() {
    let route: Route
    switch ArchiveFormat.detect(head) {
    case .zip:
      route = .spooled
    case .zstdZip, .zstd, .gzip, .other, .undetermined:
      route = .stream
    }
    if route == .spooled {
      do {
        guard FileManager.default.createFile(atPath: spoolPath, contents: nil) else {
          throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: spoolPath])
        }
        spool = try FileHandle(forWritingTo: URL(fileURLWithPath: spoolPath))
      } catch {
        fail(error)
      }
    }
    lock.withLock { decision = route }
    write(head, to: route)
    head = Data()
    _ = decided.resolve(withResult: NSNull())
  }

  private func write(_ data: Data, to route: Route) {
    downstream?.consumeData(data)
    switch route {
    case .stream:
      return
    case .spooled:
      guard let spool else {
        return
      }
      do {
        try spool.write(contentsOf: data)
      } catch {
        fail(error)
      }
    }
  }

  private func fail(_ error: Error) {
    lock.withLock { spoolError = spoolError ?? error }
    try? spool?.close()
    spool = nil
  }
}
