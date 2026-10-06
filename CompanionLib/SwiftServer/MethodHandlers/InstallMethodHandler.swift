/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorControl
import Foundation
import GRPCCore
import IDBGRPCSwift
import os

struct InstallMethodHandler {

  let commandExecutor: IDBCommandExecutor
  let targetLogger: ControlCoreLogger

  func handle(requestStream: RequestStreamReader<Idb_InstallRequest>, responseStream: RPCWriter<Idb_InstallResponse>, context: ServerContext) async throws {

    let artifact = try await Self.mapSimulatorInstallErrors {
      let request = try await InstallRequest.read(requestStream)
      return try await install(request, isCancelled: { context.cancellation.isCancelled })
    }

    let response = Idb_InstallResponse.with {
      $0.name = artifact.name
      $0.uuid = artifact.uuid?.uuidString ?? ""
    }
    try await responseStream.send(response)
  }

  static func mapSimulatorInstallErrors<T>(_ operation: () async throws -> T) async throws -> T {
    do {
      return try await operation()
    } catch let error as SimulatorApplicationInstallError {
      switch error {
      case .processSuspended,
        .processDebuggerAttached,
        .targetNotBooted,
        .targetUnavailable:
        throw RPCError(code: .failedPrecondition, message: error.localizedDescription)
      default:
        throw error
      }
    }
  }

  func install(_ request: InstallRequest, isCancelled: () -> Bool = { false }) async throws -> InstalledArtifact {
    let header = request.header
    let telemetry = InstallTelemetry(payloadKind: request.payload.kind)
    defer {
      if let call = CallTelemetry.current {
        telemetry.record(into: call)
      }
    }
    do {
      return try await install(
        request.payload,
        to: header.destination,
        name: header.nameHint ?? UUID().uuidString,
        makeDebuggable: header.makeDebuggable,
        linkToBundle: header.linkDsymToBundle.map { readLinkBundleToDsym(from: $0) },
        compression: header.compression,
        overrideModificationTime: header.overrideModificationTime,
        skipSigningBundles: header.skipSigningBundles,
        telemetry: telemetry)
    } catch {
      telemetry.failed(error, rpcCancelled: isCancelled())
      throw error
    }
  }

  private func install(
    _ payload: InstallPayload,
    to destination: Idb_InstallRequest.Destination,
    name: String,
    makeDebuggable: Bool,
    linkToBundle: DsymInstallLinkToBundle?,
    compression: FBCompressionFormat,
    overrideModificationTime: Bool,
    skipSigningBundles: Bool,
    telemetry: InstallTelemetry
  ) async throws -> InstalledArtifact {

    func installSource(dataStream: FBProcessInput<AnyObject>, compression: FBCompressionFormat, skipSigningBundles: Bool) async throws -> InstalledArtifact {
      switch destination {
      case .app:
        return try await commandExecutor.install_app_stream(dataStream, compression: compression, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime, on_progress: telemetry.observe)
      case .xctest:
        return try await commandExecutor.install_xctest_app_stream(dataStream, skipSigningBundles: skipSigningBundles, on_progress: telemetry.observe)
      case .dsym:
        return try await commandExecutor.install_dsym_stream(dataStream, compression: compression, linkTo: linkToBundle, on_progress: telemetry.observe)
      case .dylib:
        return try await commandExecutor.install_dylib_stream(dataStream, name: name, on_progress: telemetry.observe)
      case .framework:
        return try await commandExecutor.install_framework_stream(dataStream, on_progress: telemetry.observe)
      case .UNRECOGNIZED:
        throw RPCError(code: .invalidArgument, message: "Unrecognized destination")
      }
    }

    switch payload {
    case let .data(head, rest):
      let format = Self.streamFormat(initial: head, declared: compression, destination: destination)
      if destination == .app {
        telemetry.streamed(format)
      }
      let tarCompression: FBCompressionFormat
      switch format {
      case .zip:
        return try await installStreamedZip(makeDebuggable: makeDebuggable, overrideModificationTime: overrideModificationTime, telemetry: telemetry) { archiveURL, tee in
          try await spool(head: head, rest: rest, to: archiveURL, teeingTo: tee, telemetry: telemetry)
        }
      case .zstdZip:
        return try await installStreamedZip(makeDebuggable: makeDebuggable, overrideModificationTime: overrideModificationTime, telemetry: telemetry) { archiveURL, tee in
          try await decompressZstd(head: head, rest: rest, to: archiveURL, teeingTo: tee, telemetry: telemetry)
        }
      case .gzipTar:
        tarCompression = .GZIP
      case .zstdTar:
        tarCompression = .ZSTD
      }
      if tarCompression != compression {
        let prefix = head.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        targetLogger.log("Extracting a stream declared \(compression) as \(tarCompression), as it does not start with a zstd frame: \(prefix)")
      }
      let input = FBProcessInput<OutputStream>.fromStream()
      let output = input.contents
      let clientFailure = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)
      async let writePayload: Void = writePayload(head: head, rest: rest, output: output, telemetry: telemetry, clientFailure: clientFailure)
      let artifact: InstalledArtifact
      do {
        artifact = try await installSource(
          dataStream: input.retyped(FBProcessInput<AnyObject>.self),
          compression: tarCompression,
          skipSigningBundles: skipSigningBundles)
      } catch {
        // A client stream that fails truncates the archive, so extraction fails too; the client's failure is the cause.
        try? await writePayload
        throw clientFailure.withLock { $0 } ?? error
      }
      try await writePayload
      return artifact

    case let .url(url):
      if destination == .app {
        return try await commandExecutor.install_app_url(url, compression: compression, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime, on_progress: telemetry.observe)
      }
      let download = DataDownloadInput.dataDownload(withURL: url, logger: targetLogger)
      return try await Self.installDownload(download) { input in
        try await installSource(dataStream: input, compression: compression, skipSigningBundles: skipSigningBundles)
      }

    case let .filePath(filePath):
      switch destination {
      case .app:
        return try await commandExecutor.install_app_file_path(filePath, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime, on_progress: telemetry.observe)
      case .xctest:
        return try await commandExecutor.install_xctest_app_file_path(filePath, skipSigningBundles: skipSigningBundles, on_progress: telemetry.observe)
      case .dsym:
        return try await commandExecutor.install_dsym_file_path(filePath, linkTo: linkToBundle, on_progress: telemetry.observe)
      case .dylib:
        return try await commandExecutor.install_dylib_file_path(filePath, on_progress: telemetry.observe)
      case .framework:
        return try await commandExecutor.install_framework_file_path(filePath, on_progress: telemetry.observe)
      case .UNRECOGNIZED:
        throw RPCError(code: .invalidArgument, message: "Unrecognized destination")
      }
    }
  }

  /// Installs a non-app artifact from a download's stream as it arrives.
  ///
  /// A failed download ends the stream early, which the install alone cannot tell from a complete one,
  /// so its failure takes precedence over the install's outcome.
  static func installDownload(
    _ download: DataDownloadInput,
    install: (FBProcessInput<AnyObject>) async throws -> InstalledArtifact
  ) async throws -> InstalledArtifact {
    let artifact: InstalledArtifact
    do {
      artifact = try await install(download.input)
    } catch {
      try await download.completed()
      throw error
    }
    try await download.completed()
    return artifact
  }

  static func isZstdZipStream(_ data: Data) -> Bool {
    ArchiveFormat.detect(data) == .zstdZip
  }

  /// The format of a streamed payload, from its first bytes and the compression the client declared. Only an app is
  /// read as a zip; anything else is a tar.
  static func streamFormat(initial: Data, declared: FBCompressionFormat, destination: Idb_InstallRequest.Destination) -> InstallStreamFormat {
    let format = ArchiveFormat.detect(initial)
    if destination == .app {
      switch format {
      case .zip:
        return .zip
      case .zstdZip:
        return .zstdZip
      case .zstd, .gzip, .other, .undetermined:
        break
      }
    }
    return InstallStreamFormat(tarCompression: tarCompression(declared: declared, format: format))
  }

  /// The compression to extract a streamed tar with, given the one the client declared and the stream's first bytes.
  ///
  /// A stream declared zstd that does not start with a zstd frame is extracted as if undeclared, which detects gzip
  /// and plain tars from their contents, rather than by the zstd decompressor, which would reject it.
  static func tarCompression(declared: FBCompressionFormat, initial: Data) -> FBCompressionFormat {
    tarCompression(declared: declared, format: ArchiveFormat.detect(initial))
  }

  private static func tarCompression(declared: FBCompressionFormat, format: ArchiveFormat) -> FBCompressionFormat {
    guard declared == .ZSTD else {
      return declared
    }
    switch format {
    case .zstd, .zstdZip, .undetermined:
      return .ZSTD
    case .zip, .gzip, .other:
      return .GZIP
    }
  }

  /// A zip is extracted as `receive` spools it to disk, and also from the spool
  /// once complete, as its central directory is at the end.
  private func installStreamedZip(
    makeDebuggable: Bool,
    overrideModificationTime: Bool,
    telemetry: InstallTelemetry,
    receive: sending @escaping (_ archiveURL: URL, _ tee: OutputStream) async throws -> Void
  ) async throws -> InstalledArtifact {
    let archiveURL = try makeArchiveFile()
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let input = FBProcessInput<OutputStream>.fromStream()
    let (spooled, spoolCompletion) = AsyncThrowingStream<Never, Error>.makeStream()
    async let receiving: Void = {
      do {
        try await receive(archiveURL, input.contents)
        spoolCompletion.finish()
      } catch {
        spoolCompletion.finish(throwing: error)
        throw error
      }
    }()
    let artifact: InstalledArtifact
    do {
      artifact = try await commandExecutor.install_app_zip_stream(
        input.retyped(FBProcessInput<AnyObject>.self),
        spoolPath: archiveURL.path,
        spooled: {
          for try await _ in spooled {}
        },
        make_debuggable: makeDebuggable,
        override_modification_time: overrideModificationTime,
        on_progress: telemetry.observe)
    } catch {
      // The installer sees a failed receive only as a failed extraction.
      try await receiving
      throw error
    }
    try await receiving
    return artifact
  }

  private func makeArchiveFile() throws -> URL {
    let archiveURL = commandExecutor.temporaryDirectory.ephemeralTemporaryDirectory().appendingPathExtension("ipa")
    guard FileManager.default.createFile(atPath: archiveURL.path, contents: nil) else {
      throw RPCError(code: .internalError, message: "Failed to create temporary install archive")
    }
    return archiveURL
  }

  private func spool(
    head: Data,
    rest: AsyncThrowingStream<Data, any Error>,
    to archiveURL: URL,
    teeingTo output: OutputStream,
    telemetry: InstallTelemetry
  ) async throws {
    let file = try FileHandle(forWritingTo: archiveURL)
    var tee: OutputStream? = output
    tee?.open()
    defer { tee?.close() }
    try await telemetry.receive { receive in
      func append(_ data: Data) throws {
        try file.write(contentsOf: data)
        receive.count(data)
        guard let stream = tee else {
          return
        }
        do {
          try stream.writeAll(data)
        } catch {
          // The reader may finish before the end or fail; the spooled file carries on regardless.
          targetLogger.log("Stopped teeing the streamed zip to its stream extractor, which extraction from the spooled file recovers from: \(error)")
          stream.close()
          tee = nil
        }
      }
      do {
        try append(head)
        for try await data in rest {
          try append(data)
        }
        try file.close()
      } catch {
        try? file.close()
        throw error
      }
    }
  }

  private func decompressZstd(
    head: Data,
    rest: AsyncThrowingStream<Data, any Error>,
    to archiveURL: URL,
    teeingTo tee: OutputStream,
    telemetry: InstallTelemetry
  ) async throws {
    let input = FBProcessInput<OutputStream>.fromStream()
    async let writePayload: Void = writePayload(head: head, rest: rest, output: input.contents, telemetry: telemetry)
    try await ZstdStreamDecompressor.decompress(
      input.retyped(FBProcessInput<AnyObject>.self),
      toPath: archiveURL.path,
      teeingTo: tee,
      logger: targetLogger)
    try await writePayload
  }

  /// Writes the payload to `output`, recording in `clientFailure` an error thrown by `rest` rather than by the write.
  private func writePayload(
    head: Data,
    rest: AsyncThrowingStream<Data, any Error>,
    output: OutputStream,
    telemetry: InstallTelemetry,
    clientFailure: OSAllocatedUnfairLock<(any Error)?>? = nil
  ) async throws {
    output.open()
    defer { output.close() }

    try await telemetry.receive { receive in
      try output.writeAll(head)
      receive.count(head)
      var frames = rest.makeAsyncIterator()
      while true {
        let frame: Data?
        do {
          frame = try await frames.next()
        } catch {
          clientFailure?.withLock { $0 = error }
          throw error
        }
        guard let data = frame else {
          return
        }
        try output.writeAll(data)
        receive.count(data)
      }
    }
  }

  private func readLinkBundleToDsym(from link: Idb_InstallRequest.LinkDsymToBundle) -> DsymInstallLinkToBundle {
    return .init(
      bundleID: link.bundleID,
      bundleType: readDsymBundleType(from: link.bundleType))
  }

  private func readDsymBundleType(from bundleType: Idb_InstallRequest.LinkDsymToBundle.BundleType) -> DsymBundleType {
    switch bundleType {
    case .app:
      return .app
    case .xctest:
      return .xcTest
    case .UNRECOGNIZED:
      return .app
    }
  }
}
