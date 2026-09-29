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
    if case .localPath(let path) = source, BundleDescriptor.isApplication(atPath: path) {
      return try await perform(try BundleDescriptor.bundle(fromPath: path))
    }
    return try await temporaryDirectory.withTemporaryDirectory { extractDirectory in
      try await extract(
        source, to: extractDirectory.path, options: options, totalStart: totalStart,
        downloadConfiguration: downloadConfiguration, logger: logger, onProgress: onProgress)
      let bundle = try BundleDescriptor.findAppPath(fromDirectory: extractDirectory, logger: logger)
      return try await perform(bundle)
    }
  }

  // MARK: - Stages

  private static func extract(
    _ source: InstallSource,
    to extractPath: String,
    options: InstallOptions,
    totalStart: Date,
    downloadConfiguration: URLSessionConfiguration,
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
      try await downloadAndExtract(
        url, to: extractPath, options: options, totalStart: totalStart,
        configuration: downloadConfiguration, logger: logger, onProgress: onProgress)
    }
  }

  /// The extractor reads the transfer as it arrives rather than waiting for a
  /// complete file, so the download and extract stages overlap and each times
  /// against its own start.
  private static func downloadAndExtract(
    _ url: URL,
    to extractPath: String,
    options: InstallOptions,
    totalStart: Date,
    configuration: URLSessionConfiguration,
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
      async let extraction: Void = ArchiveExtractors.default.extract(
        .stream(download.input), to: extractPath, options: options.extractOptions, logger: logger)
      // The transfer's outcome first: the extractor only sees bytes and then an
      // end of file, so a failed transfer looks to it like a short archive.
      try await download.completed()
      onProgress(
        .downloadCompleted(
          timing: .measure(stageStart: downloadStart, totalStart: totalStart),
          totalBytes: progress.downloadedBytes))
      try await extraction
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
    try await operation()
    onProgress(.extractCompleted(timing: .measure(stageStart: stageStart, totalStart: totalStart), destinationPath: extractPath))
  }
}
