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
      let isCancelled = { context.cancellation.isCancelled }
      // Clients print every response to any other install as an installed artifact, so only an application reports its progress.
      guard request.header.destination == .app else {
        return try await install(request, isCancelled: isCancelled)
      }
      return try await InstallPercentages.reporting(to: { progress in
        try await responseStream.send(Idb_InstallResponse.with { $0.progress = progress })
      }) { onProgress in
        try await install(request, isCancelled: isCancelled, onProgress: onProgress)
      }
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

  func install(
    _ request: InstallRequest,
    isCancelled: () -> Bool = { false },
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void = { _ in }
  ) async throws -> InstalledArtifact {
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
        telemetry: telemetry,
        onProgress: onProgress)
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
    telemetry: InstallTelemetry,
    onProgress: @escaping @Sendable (InstallProgressEvent) -> Void
  ) async throws -> InstalledArtifact {

    let installDestination: InstallDestination
    switch destination {
    case .app:
      installDestination = .application(makeDebuggable: makeDebuggable)
    case .xctest:
      installDestination = .xctest(skipSigningBundles: skipSigningBundles)
    case .dsym:
      installDestination = .dsym(linkTo: linkToBundle)
    case .dylib:
      installDestination = .dylib
    case .framework:
      installDestination = .framework
    case .UNRECOGNIZED:
      throw RPCError(code: .invalidArgument, message: "Unrecognized destination")
    }

    func install(from source: InstallSource, compression: FBCompressionFormat = .GZIP) async throws -> InstalledArtifact {
      let options: InstallOptions
      switch installDestination {
      case .application:
        options = InstallOptions(overrideModificationTime: overrideModificationTime, compression: compression)
      case .dsym, .xctest, .framework, .dylib:
        options = InstallOptions(compression: compression)
      }
      return try await commandExecutor.install(
        installDestination, from: source, options: options,
        onProgress: { event in
          telemetry.observe(event)
          onProgress(event)
        },
        onReport: telemetry.staged)
    }

    /// A dylib arrives as a single gzipped file; everything else as an archive.
    func installStreamed(_ dataStream: BytePipe, compression: FBCompressionFormat) async throws -> InstalledArtifact {
      if case .dylib = installDestination {
        return try await install(from: .gzippedFile(dataStream, name: name))
      }
      return try await install(from: .stream(dataStream), compression: compression)
    }

    func installStream(_ dataStream: BytePipe, format: InstallStreamFormat, head: Data) async throws -> InstalledArtifact {
      let tarCompression: FBCompressionFormat
      switch format {
      case .zip, .zstdZip:
        return try await installStreamed(dataStream, compression: compression)
      case .gzipTar:
        tarCompression = .GZIP
      case .zstdTar:
        tarCompression = .ZSTD
      }
      if tarCompression != compression {
        let prefix = head.prefix(16).map { String(format: "%02x", $0) }.joined(separator: " ")
        targetLogger.log("Extracting a stream declared \(compression) as \(tarCompression), as it does not start with a zstd frame: \(prefix)")
      }
      return try await installStreamed(dataStream, compression: tarCompression)
    }

    switch payload {
    case let .data(head, rest):
      let format = Self.streamFormat(initial: head, declared: compression)
      if destination == .app {
        telemetry.streamed(format)
      }
      let pipe = BytePipe()
      let clientFailure = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)
      async let writePayload: Void = writePayload(head: head, rest: rest, to: pipe.input, telemetry: telemetry, clientFailure: clientFailure)
      let artifact: InstalledArtifact
      do {
        artifact = try await installStream(pipe, format: format, head: head)
      } catch {
        // A client stream that fails truncates the archive, so extraction fails too; the client's failure is the cause.
        try? await writePayload
        throw clientFailure.withLock { $0 } ?? error
      }
      try await writePayload
      return artifact

    case let .url(url):
      return try await install(from: Self.urlSource(url, for: installDestination, name: name), compression: compression)

    case let .filePath(filePath):
      return try await install(from: .localPath(filePath))
    }
  }

  /// A dylib arrives as a single gzipped file; everything else as an archive.
  static func urlSource(_ url: URL, for destination: InstallDestination, name: String) -> InstallSource {
    switch destination {
    case .application, .xctest, .dsym, .framework:
      return .remoteURL(url)
    case .dylib:
      return .remoteGzippedFile(url, name: name)
    }
  }

  /// The format of a streamed payload, from its first bytes and the compression the client declared.
  static func streamFormat(initial: Data, declared: FBCompressionFormat) -> InstallStreamFormat {
    let format = ArchiveFormat.detect(initial)
    switch format {
    case .zip:
      return .zip
    case .zstdZip:
      return .zstdZip
    case .zstd, .gzip, .other, .undetermined:
      return InstallStreamFormat(tarCompression: tarCompression(declared: declared, format: format))
    }
  }

  /// The compression to extract a streamed tar with, given the one the client declared and the format of the stream's first bytes.
  ///
  /// A stream declared zstd that does not start with a zstd frame is extracted as if undeclared, which detects gzip
  /// and plain tars from their contents, rather than by the zstd decompressor, which would reject it.
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

  /// Writes the payload to `input`, recording in `clientFailure` an error thrown by `rest` rather than by the write.
  private func writePayload(
    head: Data,
    rest: AsyncThrowingStream<Data, any Error>,
    to input: InputSource,
    telemetry: InstallTelemetry,
    clientFailure: OSAllocatedUnfairLock<(any Error)?>
  ) async throws {
    defer { input.finish() }

    try await telemetry.receive { receive in
      try await PayloadPump.write(
        head: head, frames: rest, to: input,
        onWrite: { receive.count($0) },
        onClientFailure: { error in clientFailure.withLock { $0 = error } })
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
