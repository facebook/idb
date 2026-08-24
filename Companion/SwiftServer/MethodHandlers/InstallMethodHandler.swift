/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift

struct InstallMethodHandler: @unchecked Sendable {

  let commandExecutor: FBIDBCommandExecutor
  let targetLogger: FBControlCoreLogger

  func handle(requestStream: GRPCAsyncRequestStream<Idb_InstallRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstallResponse>, context: GRPCAsyncServerCallContext) async throws {

    let stream = SingleIteratorRequestStream(requestStream)
    let artifact = try await install(stream: stream, responseStream: responseStream)

    let response = Idb_InstallResponse.with {
      $0.name = artifact.name
      $0.uuid = artifact.uuid?.uuidString ?? ""
    }
    try await responseStream.send(response)
  }

  private func install(stream: SingleIteratorRequestStream<GRPCAsyncRequestStream<Idb_InstallRequest>>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstallResponse>) async throws -> FBInstalledArtifact {

    func extractPayloadFromRequest() throws -> Idb_Payload {
      guard let payload = request.extractPayload() else {
        throw GRPCStatus(code: .invalidArgument, message: "Expected the next item in the stream to be a payload")
      }
      return payload
    }

    var request = try await stream.requiredNext

    guard case let .destination(destination) = request.value else {
      throw GRPCStatus(code: .failedPrecondition, message: "Expected destination as first request in stream")
    }
    request = try await stream.requiredNext

    var name = UUID().uuidString
    if case let .nameHint(nameHint) = request.value {
      name = nameHint
      request = try await stream.requiredNext
    }

    var makeDebuggable = false
    if case let .makeDebuggable(debuggable) = request.value {
      makeDebuggable = debuggable
      request = try await stream.requiredNext
    }
    var overrideModificationTime = false
    if case let .overrideModificationTime(omtime) = request.value {
      overrideModificationTime = omtime
      request = try await stream.requiredNext
    }

    var skipSigningBundles = false
    if case let .skipSigningBundles(skip) = request.value {
      skipSigningBundles = skip
      request = try await stream.requiredNext
    }

    var linkToBundle: FBDsymInstallLinkToBundle?

    // (2022-03-02) REMOVE! Keeping only for retrocompatibility
    if case let .bundleID(id) = request.value {
      linkToBundle = .init(bundleID: id, bundleType: .app)
      request = try await stream.requiredNext
    }

    if case let .linkDsymToBundle(link) = request.value {
      linkToBundle = readLinkBundleToDsym(from: link)
      request = try await stream.requiredNext
    }

    var payload = try extractPayloadFromRequest()

    var compression = FBCompressionFormat.GZIP
    if case let .compression(format) = payload.source {
      compression = readCompressionFormat(from: format)
      request = try await stream.requiredNext
      payload = try extractPayloadFromRequest()
    }

    return try await installData(
      from: payload.source,
      to: destination,
      stream: stream,
      name: name,
      makeDebuggable: makeDebuggable,
      linkToBundle: linkToBundle,
      compression: compression,
      overrideModificationTime: overrideModificationTime,
      skipSigningBundles: skipSigningBundles)
  }

  private func installData(
    from source: Idb_Payload.OneOf_Source?,
    to destination: Idb_InstallRequest.Destination,
    stream: SingleIteratorRequestStream<GRPCAsyncRequestStream<Idb_InstallRequest>>,
    name: String,
    makeDebuggable: Bool,
    linkToBundle: FBDsymInstallLinkToBundle?,
    compression: FBCompressionFormat,
    overrideModificationTime: Bool,
    skipSigningBundles: Bool
  ) async throws -> FBInstalledArtifact {

    func installSource(dataStream: FBProcessInput<AnyObject>, skipSigningBundles: Bool) async throws -> FBInstalledArtifact {
      switch destination {
      case .app:
        return try await commandExecutor.install_app_stream(dataStream, compression: compression, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime)
      case .xctest:
        return try await commandExecutor.install_xctest_app_stream(dataStream, skipSigningBundles: skipSigningBundles)
      case .dsym:
        return try await commandExecutor.install_dsym_stream(dataStream, compression: compression, linkTo: linkToBundle)
      case .dylib:
        return try await commandExecutor.install_dylib_stream(dataStream, name: name)
      case .framework:
        return try await commandExecutor.install_framework_stream(dataStream)
      case .UNRECOGNIZED:
        throw GRPCStatus(code: .invalidArgument, message: "Unrecognized destination")
      }
    }

    switch source {
    case let .data(data):
      if destination == .app && isZipArchive(data) {
        return try await installZipArchive(
          initial: data,
          stream: stream,
          makeDebuggable: makeDebuggable,
          overrideModificationTime: overrideModificationTime)
      }

      let input = FBProcessInput<OutputStream>.fromStream()
      let output = input.contents
      async let writePayload: Void = writePayload(initial: data, stream: stream, output: output)
      let artifact = try await installSource(
        dataStream: unsafeBitCast(input, to: FBProcessInput<AnyObject>.self),
        skipSigningBundles: skipSigningBundles)
      try await writePayload
      return artifact

    case let .url(urlString):
      guard let url = URL(string: urlString) else {
        throw GRPCStatus(code: .invalidArgument, message: "Invalid url source")
      }
      let download = FBDataDownloadInput.dataDownload(withURL: url, logger: targetLogger)
      let input = download.input

      return try await installSource(dataStream: input, skipSigningBundles: skipSigningBundles)

    case let .filePath(filePath):
      switch destination {
      case .app:
        return try await commandExecutor.install_app_file_path(filePath, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime)
      case .xctest:
        return try await commandExecutor.install_xctest_app_file_path(filePath, skipSigningBundles: skipSigningBundles)
      case .dsym:
        return try await commandExecutor.install_dsym_file_path(filePath, linkTo: linkToBundle)
      case .dylib:
        return try await commandExecutor.install_dylib_file_path(filePath)
      case .framework:
        return try await commandExecutor.install_framework_file_path(filePath)
      case .UNRECOGNIZED:
        throw GRPCStatus(code: .invalidArgument, message: "Unrecognized destination")
      }

    default:
      throw GRPCStatus(code: .invalidArgument, message: "Incorrect payload source")
    }
  }

  private func isZipArchive(_ data: Data) -> Bool {
    data.starts(with: [0x50, 0x4B, 0x03, 0x04])
  }

  private func installZipArchive(
    initial: Data,
    stream: SingleIteratorRequestStream<GRPCAsyncRequestStream<Idb_InstallRequest>>,
    makeDebuggable: Bool,
    overrideModificationTime: Bool
  ) async throws -> FBInstalledArtifact {
    let archiveURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("ipa")
    guard FileManager.default.createFile(atPath: archiveURL.path, contents: nil) else {
      throw GRPCStatus(code: .internalError, message: "Failed to create temporary install archive")
    }
    defer { try? FileManager.default.removeItem(at: archiveURL) }

    let file = try FileHandle(forWritingTo: archiveURL)
    do {
      try file.write(contentsOf: initial)
      while let request = try await stream.next() {
        guard let data = request.extractDataFrame() else {
          continue
        }
        try file.write(contentsOf: data)
      }
      try file.close()
    } catch {
      try? file.close()
      throw error
    }

    return try await commandExecutor.install_app_file_path(
      archiveURL.path,
      make_debuggable: makeDebuggable,
      override_modification_time: overrideModificationTime)
  }

  private func writePayload(
    initial: Data,
    stream: SingleIteratorRequestStream<GRPCAsyncRequestStream<Idb_InstallRequest>>,
    output: OutputStream
  ) async throws {
    output.open()
    defer { output.close() }

    try write(initial, to: output)
    while let request = try await stream.next() {
      guard let data = request.extractDataFrame() else {
        continue
      }
      try write(data, to: output)
    }
  }

  private func write(_ data: Data, to output: OutputStream) throws {
    var buffer = [UInt8](data)
    guard output.write(&buffer, maxLength: buffer.count) == buffer.count else {
      throw output.streamError ?? GRPCStatus(code: .internalError, message: "Failed to write install payload")
    }
  }

  private func readLinkBundleToDsym(from link: Idb_InstallRequest.LinkDsymToBundle) -> FBDsymInstallLinkToBundle {
    return .init(
      bundleID: link.bundleID,
      bundleType: readDsymBundleType(from: link.bundleType))
  }

  private func readDsymBundleType(from bundleType: Idb_InstallRequest.LinkDsymToBundle.BundleType) -> FBDsymBundleType {
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
