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

struct InstallMethodHandler: @unchecked Sendable {

  let commandExecutor: IDBCommandExecutor
  let targetLogger: ControlCoreLogger

  func handle(requestStream: RequestStreamReader<Idb_InstallRequest>, responseStream: RPCWriter<Idb_InstallResponse>, context: ServerContext) async throws {

    let artifact = try await Self.mapSimulatorInstallErrors {
      try await install(requestStream: requestStream, responseStream: responseStream, context: context)
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

  private func install(requestStream: RequestStreamReader<Idb_InstallRequest>, responseStream: RPCWriter<Idb_InstallResponse>, context: ServerContext) async throws -> InstalledArtifact {

    func extractPayloadFromRequest() throws -> Idb_Payload {
      guard let payload = request.extractPayload() else {
        throw RPCError(code: .invalidArgument, message: "Expected the next item in the stream to be a payload")
      }
      return payload
    }

    var request = try await requestStream.requiredNext()

    guard case let .destination(destination) = request.value else {
      throw RPCError(code: .failedPrecondition, message: "Expected destination as first request in stream")
    }
    request = try await requestStream.requiredNext()

    var name = UUID().uuidString
    if case let .nameHint(nameHint) = request.value {
      name = nameHint
      request = try await requestStream.requiredNext()
    }

    var makeDebuggable = false
    if case let .makeDebuggable(debuggable) = request.value {
      makeDebuggable = debuggable
      request = try await requestStream.requiredNext()
    }
    var overrideModificationTime = false
    if case let .overrideModificationTime(omtime) = request.value {
      overrideModificationTime = omtime
      request = try await requestStream.requiredNext()
    }

    var skipSigningBundles = false
    if case let .skipSigningBundles(skip) = request.value {
      skipSigningBundles = skip
      request = try await requestStream.requiredNext()
    }

    var linkToBundle: DsymInstallLinkToBundle?
    if case let .linkDsymToBundle(link) = request.value {
      linkToBundle = readLinkBundleToDsym(from: link)
      request = try await requestStream.requiredNext()
    }

    var payload = try extractPayloadFromRequest()

    var compression = FBCompressionFormat.GZIP
    if case let .compression(format) = payload.source {
      compression = readCompressionFormat(from: format)
      request = try await requestStream.requiredNext()
      payload = try extractPayloadFromRequest()
    }

    let telemetry = InstallTelemetry(payloadKind: try payloadKind(of: payload.source))
    defer {
      if let call = CallTelemetry.current {
        telemetry.record(into: call)
      }
    }
    do {
      return try await installData(
        from: payload.source,
        to: destination,
        requestStream: requestStream,
        name: name,
        makeDebuggable: makeDebuggable,
        linkToBundle: linkToBundle,
        compression: compression,
        overrideModificationTime: overrideModificationTime,
        skipSigningBundles: skipSigningBundles,
        telemetry: telemetry)
    } catch {
      telemetry.failed(error, rpcCancelled: context.cancellation.isCancelled)
      throw error
    }
  }

  private func payloadKind(of source: Idb_Payload.OneOf_Source?) throws -> InstallPayloadKind {
    switch source {
    case .data:
      return .data
    case .url:
      return .url
    case .filePath:
      return .filePath
    default:
      throw RPCError(code: .invalidArgument, message: "Incorrect payload source")
    }
  }

  private func installData(
    from source: Idb_Payload.OneOf_Source?,
    to destination: Idb_InstallRequest.Destination,
    requestStream: RequestStreamReader<Idb_InstallRequest>,
    name: String,
    makeDebuggable: Bool,
    linkToBundle: DsymInstallLinkToBundle?,
    compression: FBCompressionFormat,
    overrideModificationTime: Bool,
    skipSigningBundles: Bool,
    telemetry: InstallTelemetry
  ) async throws -> InstalledArtifact {

    func installSource(dataStream: FBProcessInput<AnyObject>, skipSigningBundles: Bool) async throws -> InstalledArtifact {
      switch destination {
      case .app:
        return try await commandExecutor.install_app_stream(dataStream, compression: compression, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime, on_progress: telemetry.observe)
      case .xctest:
        return try await commandExecutor.install_xctest_app_stream(dataStream, skipSigningBundles: skipSigningBundles)
      case .dsym:
        return try await commandExecutor.install_dsym_stream(dataStream, compression: compression, linkTo: linkToBundle)
      case .dylib:
        return try await commandExecutor.install_dylib_stream(dataStream, name: name)
      case .framework:
        return try await commandExecutor.install_framework_stream(dataStream)
      case .UNRECOGNIZED:
        throw RPCError(code: .invalidArgument, message: "Unrecognized destination")
      }
    }

    switch source {
    case let .data(data):
      if destination == .app && isZipArchive(data) {
        telemetry.streamed(.zip)
        return try await installStreamedZip(makeDebuggable: makeDebuggable, overrideModificationTime: overrideModificationTime, telemetry: telemetry) { archiveURL, tee in
          try await spool(initial: data, requestStream: requestStream, to: archiveURL, teeingTo: tee, telemetry: telemetry)
        }
      }
      if destination == .app && Self.isZstdZipStream(data) {
        telemetry.streamed(.zstdZip)
        return try await installStreamedZip(makeDebuggable: makeDebuggable, overrideModificationTime: overrideModificationTime, telemetry: telemetry) { archiveURL, tee in
          try await decompressZstd(initial: data, requestStream: requestStream, to: archiveURL, teeingTo: tee, telemetry: telemetry)
        }
      }

      if destination == .app {
        telemetry.streamed(InstallStreamFormat(tarCompression: compression))
      }
      let input = FBProcessInput<OutputStream>.fromStream()
      let output = input.contents
      async let writePayload: Void = writePayload(initial: data, requestStream: requestStream, output: output, telemetry: telemetry)
      let artifact = try await installSource(
        dataStream: input.retyped(FBProcessInput<AnyObject>.self),
        skipSigningBundles: skipSigningBundles)
      try await writePayload
      return artifact

    case let .url(urlString):
      guard let url = URL(string: urlString) else {
        throw RPCError(code: .invalidArgument, message: "Invalid url source")
      }
      if destination == .app {
        return try await commandExecutor.install_app_url(url, compression: compression, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime, on_progress: telemetry.observe)
      }
      let download = DataDownloadInput.dataDownload(withURL: url, logger: targetLogger)
      let input = download.input

      return try await installSource(dataStream: input, skipSigningBundles: skipSigningBundles)

    case let .filePath(filePath):
      switch destination {
      case .app:
        return try await commandExecutor.install_app_file_path(filePath, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime, on_progress: telemetry.observe)
      case .xctest:
        return try await commandExecutor.install_xctest_app_file_path(filePath, skipSigningBundles: skipSigningBundles)
      case .dsym:
        return try await commandExecutor.install_dsym_file_path(filePath, linkTo: linkToBundle)
      case .dylib:
        return try await commandExecutor.install_dylib_file_path(filePath)
      case .framework:
        return try await commandExecutor.install_framework_file_path(filePath)
      case .UNRECOGNIZED:
        throw RPCError(code: .invalidArgument, message: "Unrecognized destination")
      }

    default:
      throw RPCError(code: .invalidArgument, message: "Incorrect payload source")
    }
  }

  private func isZipArchive(_ data: Data) -> Bool {
    data.starts(with: [0x50, 0x4B, 0x03, 0x04])
  }

  /// The zstd skippable frame that `CompanionInfo.zstd_zip_streams` clients start a compressed zip with.
  static let zstdZipStreamMarker: [UInt8] = [0x5E, 0x2A, 0x4D, 0x18, 0x08, 0x00, 0x00, 0x00] + Array("idb-zip\0".utf8)

  static func isZstdZipStream(_ data: Data) -> Bool {
    data.starts(with: zstdZipStreamMarker)
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
    let archiveURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("ipa")
    guard FileManager.default.createFile(atPath: archiveURL.path, contents: nil) else {
      throw RPCError(code: .internalError, message: "Failed to create temporary install archive")
    }
    return archiveURL
  }

  private func spool(
    initial: Data,
    requestStream: RequestStreamReader<Idb_InstallRequest>,
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
          try write(data, to: stream)
        } catch {
          // The reader may finish before the end or fail; the spooled file carries on regardless.
          stream.close()
          tee = nil
        }
      }
      do {
        try append(initial)
        for try await request in requestStream {
          guard let data = request.extractDataFrame() else {
            continue
          }
          try append(data)
        }
        try file.close()
      } catch {
        try? file.close()
        throw error
      }
    }
  }

  /// The decompressor writes to the archive file, which is followed as it grows
  /// to tee the zip, as a pipe between them would need a third process.
  private func decompressZstd(
    initial: Data,
    requestStream: RequestStreamReader<Idb_InstallRequest>,
    to archiveURL: URL,
    teeingTo tee: OutputStream,
    telemetry: InstallTelemetry
  ) async throws {
    guard let decompressor = FBArchiveOperations.zstdDecompressorPath(searchPath: ProcessInfo.processInfo.environment["PATH"]) else {
      throw RPCError(code: .failedPrecondition, message: "A zstd zip stream needs pzstd on the companion's PATH")
    }
    targetLogger.log("Decompressing a zstd zip stream with \(decompressor)")
    let input = FBProcessInput<OutputStream>.fromStream()
    let decompressed = OSAllocatedUnfairLock(initialState: false)
    async let writePayload: Void = writePayload(initial: initial, requestStream: requestStream, output: input.contents, telemetry: telemetry)
    async let decompressing: Void = {
      defer { decompressed.withLock { $0 = true } }
      _ = try await bridgeFBFuture(
        FBArchiveOperations.extractZstd(
          fromStream: input.retyped(FBProcessInput<AnyObject>.self),
          toPath: archiveURL.path,
          decompressorPath: decompressor,
          logger: targetLogger))
    }()
    tee.open()
    defer { tee.close() }
    do {
      try await GrowingFile.copy(from: archiveURL.path, to: tee) { decompressed.withLock { $0 } }
    } catch {
      // The reader may finish before the end or fail; the archive file carries on regardless.
      targetLogger.log("Stopped teeing the decompressed zip to its stream extractor, which extraction from the archive file recovers from: \(error)")
      tee.close()
    }
    try await decompressing
    try await writePayload
  }

  private func writePayload(
    initial: Data,
    requestStream: RequestStreamReader<Idb_InstallRequest>,
    output: OutputStream,
    telemetry: InstallTelemetry
  ) async throws {
    output.open()
    defer { output.close() }

    try await telemetry.receive { receive in
      try write(initial, to: output)
      receive.count(initial)
      for try await request in requestStream {
        guard let data = request.extractDataFrame() else {
          continue
        }
        try write(data, to: output)
        receive.count(data)
      }
    }
  }

  private func write(_ data: Data, to output: OutputStream) throws {
    var buffer = [UInt8](data)
    guard output.write(&buffer, maxLength: buffer.count) == buffer.count else {
      throw output.streamError ?? RPCError(code: .internalError, message: "Failed to write install payload")
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

  private func readCompressionFormat(from compression: Idb_Payload.Compression) -> FBCompressionFormat {
    switch compression {
    case .gzip, .UNRECOGNIZED:
      return .GZIP
    case .zstd:
      return .ZSTD
    }
  }
}
