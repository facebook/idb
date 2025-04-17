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

struct InstallMethodHandler {

  let commandExecutor: FBIDBCommandExecutor
  let targetLogger: FBControlCoreLogger

  func handle(requestStream: GRPCAsyncRequestStream<Idb_InstallRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstallResponse>, context: GRPCAsyncServerCallContext) async throws {

    let artifact = try await install(requestStream: requestStream, responseStream: responseStream)

    let response = Idb_InstallResponse.with {
      $0.name = artifact.name
      $0.uuid = artifact.uuid?.uuidString ?? ""
    }
    try await responseStream.send(response)
  }

  private func install(requestStream: GRPCAsyncRequestStream<Idb_InstallRequest>, responseStream: GRPCAsyncResponseStreamWriter<Idb_InstallResponse>) async throws -> FBInstalledArtifact {

    func extractPayloadFromRequest() throws -> Idb_Payload {
      guard let payload = request.extractPayload() else {
        throw GRPCStatus(code: .invalidArgument, message: "Expected the next item in the stream to be a payload")
      }
      return payload
    }

    var request = try await requestStream.requiredNext

    guard case let .destination(destination) = request.value else {
      throw GRPCStatus(code: .failedPrecondition, message: "Expected destination as first request in stream")
    }
    request = try await requestStream.requiredNext

    var name = UUID().uuidString
    if case let .nameHint(nameHint) = request.value {
      name = nameHint
      request = try await requestStream.requiredNext
    }

    var makeDebuggable = false
    if case let .makeDebuggable(debuggable) = request.value {
      makeDebuggable = debuggable
      request = try await requestStream.requiredNext
    }
    var overrideModificationTime = false
    if case let .overrideModificationTime(omtime) = request.value {
      overrideModificationTime = omtime
      request = try await requestStream.requiredNext
    }

    var skipSigningBundles = false
    if case let .skipSigningBundles(skip) = request.value {
      skipSigningBundles = skip
      request = try await requestStream.requiredNext
    }

    var linkToBundle: FBDsymInstallLinkToBundle?

    // (2022-03-02) REMOVE! Keeping only for retrocompatibility
    if case let .bundleID(id) = request.value {
      linkToBundle = .init(id, bundle_type: .app)
      request = try await requestStream.requiredNext
    }

    if case let .linkDsymToBundle(link) = request.value {
      linkToBundle = readLinkBundleToDsym(from: link)
      request = try await requestStream.requiredNext
    }

    var payload = try extractPayloadFromRequest()

    var compression = FBCompressionFormat.GZIP
    if case let .compression(format) = payload.source {
      compression = readCompressionFormat(from: format)
      request = try await requestStream.requiredNext
      payload = try extractPayloadFromRequest()
    }

    return try await installData(
      from: payload.source,
      to: destination,
      requestStream: requestStream,
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
    requestStream: GRPCAsyncRequestStream<Idb_InstallRequest>,
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
        return try await BridgeFuture.value(
          commandExecutor.install_app_stream(dataStream, compression: compression, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime)
        )
      case .xctest:
        return try await BridgeFuture.value(
          commandExecutor.install_xctest_app_stream(dataStream, skipSigningBundles: skipSigningBundles)
        )
      case .dsym:
        return try await BridgeFuture.value(
          commandExecutor.install_dsym_stream(dataStream, compression: compression, linkTo: linkToBundle)
        )
      case .dylib:
        return try await BridgeFuture.value(
          commandExecutor.install_dylib_stream(dataStream, name: name)
        )
      case .framework:
        return try await BridgeFuture.value(
          commandExecutor.install_framework_stream(dataStream)
        )
      case .UNRECOGNIZED:
        throw GRPCStatus(code: .invalidArgument, message: "Unrecognized destination")
      }
    }

    switch source {
    case let .data(data):
      let dataStream = pipeToInputOutput(initial: data, requestStream: requestStream) as! FBProcessInput<AnyObject>
      return try await installSource(dataStream: dataStream, skipSigningBundles: skipSigningBundles)

    case let .url(urlString):
      guard let url = URL(string: urlString) else {
        throw GRPCStatus(code: .invalidArgument, message: "Invalid url source")
      }
      let download = FBDataDownloadInput.dataDownload(with: url, logger: targetLogger)
      let input = download.input as! FBProcessInput<AnyObject>

      return try await installSource(dataStream: input, skipSigningBundles: skipSigningBundles)

    case let .filePath(filePath):
      switch destination {
      case .app:
        return try await BridgeFuture.value(
          commandExecutor.install_app_file_path(filePath, make_debuggable: makeDebuggable, override_modification_time: overrideModificationTime)
        )
      case .xctest:
        return try await BridgeFuture.value(
          commandExecutor.install_xctest_app_file_path(filePath, skipSigningBundles: skipSigningBundles)
        )
      case .dsym:
        return try await BridgeFuture.value(
          commandExecutor.install_dsym_file_path(filePath, linkTo: linkToBundle)
        )
      case .dylib:
        return try await BridgeFuture.value(
          commandExecutor.install_dylib_file_path(filePath)
        )
      case .framework:
        return try await BridgeFuture.value(
          commandExecutor.install_framework_file_path(filePath)
        )
      case .UNRECOGNIZED:
        throw GRPCStatus(code: .invalidArgument, message: "Unrecognized destination")
      }

    default:
      throw GRPCStatus(code: .invalidArgument, message: "Incorrect payload source")
    }
  }

  private func pipeToInputOutput(initial: Data, requestStream: GRPCAsyncRequestStream<Idb_InstallRequest>) -> FBProcessInput<OutputStream> {
    let input = FBProcessInput<OutputStream>.fromStream()
    let appStream = input.contents
    Task {
      appStream.open()
      defer { appStream.close() }

      var buffer = [UInt8](initial)
      appStream.write(&buffer, maxLength: buffer.count)

      for try await request in requestStream {
        guard let data = request.extractDataFrame() else {
          continue
        }

        var buffer = [UInt8](data)
        appStream.write(&buffer, maxLength: buffer.count)
      }
    }

    return input
  }

  private func readLinkBundleToDsym(from link: Idb_InstallRequest.LinkDsymToBundle) -> FBDsymInstallLinkToBundle {
    return .init(
      link.bundleID,
      bundle_type: readDsymBundleType(from: link.bundleType))
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
