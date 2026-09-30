/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where an application to install comes from.
public enum InstallSource {

  /// A path to either an `.app` bundle, which needs no unpacking, or an archive
  /// containing one.
  case localPath(String)

  /// An archive to fetch over HTTP.
  case remoteURL(URL)

  /// An archive arriving on a process input that the caller is writing to.
  case processInput(FBProcessInput<AnyObject>)
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

/// Gets from "somewhere an application lives" to "an application bundle on
/// disk", reporting what it is doing as it goes.
///
/// This deliberately stops short of installing. Installing means different things
/// to different callers -- some persist the bundle alongside the target, some
/// codesign it first -- and all of them need the bundle rather than the installed
/// application.
public enum ApplicationArchive {

  /// Resolves `source` to a bundle and calls `perform` with it.
  ///
  /// The bundle is only valid for the duration of `perform`: anything unpacked is
  /// removed afterwards.
  ///
  /// `onProgress` reports stages that start and stages that finish. A stage that
  /// fails reports no terminal event; the failure is the thrown error.
  public static func withResolvedBundle<T>(
    from source: InstallSource,
    options: InstallOptions = InstallOptions(),
    totalStart: Date = Date(),
    downloadConfiguration: URLSessionConfiguration = .default,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void = { _ in },
    perform: (BundleDescriptor) async throws -> T
  ) async throws -> T {
    if case .localPath(let path) = source, !unpacks(source) {
      return try await perform(try BundleDescriptor.bundle(fromPath: path))
    }
    return try await temporaryDirectory.withTemporaryDirectory { extractDirectory in
      try await extract(
        source, to: extractDirectory.path, options: options, totalStart: totalStart,
        downloadConfiguration: downloadConfiguration, temporaryDirectory: temporaryDirectory,
        logger: logger, onProgress: onProgress)
      let bundle: BundleDescriptor
      do {
        bundle = try BundleDescriptor.findAppPath(fromDirectory: extractDirectory, logger: logger)
      } catch {
        throw InstallError.noInstallableBundle(inDirectory: extractDirectory.path, underlying: error)
      }
      return try await perform(bundle)
    }
  }

  /// Whether resolving `source` unpacks it. An unpacked bundle belongs to
  /// `withResolvedBundle`, which removes it afterwards, so `perform` may move it
  /// away; any other bundle is the caller's own, and must be left where it is.
  public static func unpacks(_ source: InstallSource) -> Bool {
    guard case .localPath(let path) = source else {
      return true
    }
    return !BundleDescriptor.isApplication(atPath: path)
  }

  // MARK: - Stages

  private static func extract(
    _ source: InstallSource,
    to extractPath: String,
    options: InstallOptions,
    totalStart: Date,
    downloadConfiguration: URLSessionConfiguration,
    temporaryDirectory: TemporaryDirectory,
    logger: any ControlCoreLogger,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void
  ) async throws {
    switch source {
    case .localPath(let path):
      try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
        try await ArchiveExtractors.default.extract(
          .filePath(path), to: extractPath, options: options.extractOptions, logger: logger)
      }
    case .processInput(let input):
      // The caller owns the writing end, so a writer that fails partway reaches
      // the extractor as nothing more than a short archive. Only the caller holds
      // the writer's own error.
      try await runExtractStage(to: extractPath, totalStart: totalStart, onProgress: onProgress) {
        try await ArchiveExtractors.default.extract(
          .stream(input), to: extractPath, options: options.extractOptions, logger: logger)
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
  }

  /// The extractor reads the transfer as it arrives rather than waiting for a
  /// complete file, so the download and extract stages overlap and each times
  /// against its own start.
  ///
  /// A zip is the exception: it is written to `spoolPath` and extracted once
  /// complete, since it records symlinks and permissions only in the central
  /// directory at its end, which a reader of the transfer never reaches.
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
        logger.log("Spooling the zip at \(url) to \(spoolPath) before extracting it")
        try await downloadCompleted()
        try router.checkSpool()
        try await ArchiveExtractors.default.extract(
          .filePath(spoolPath), to: extractPath, options: options.extractOptions, logger: logger)
      }
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

/// Sends a download to a file if it is a zip, and on to the extractor otherwise,
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

  private static let zipSignature = Data([0x50, 0x4B, 0x03, 0x04])

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
      if head.count >= Self.zipSignature.count {
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
    // The extractor's pipe is closed even when the zip went to the spool.
    downstream?.consumeEndOfFile()
  }

  private func decide() {
    let route: Route = head.starts(with: Self.zipSignature) ? .spooled : .stream
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
    switch route {
    case .stream:
      downstream?.consumeData(data)
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
