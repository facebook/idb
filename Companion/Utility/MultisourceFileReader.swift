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

enum MultisourceFileReader {

  /// Hands the file URLs from the request stream to `body`. Files extracted from a streamed
  /// archive live in a temporary directory scoped to `body`; files referenced by path belong to
  /// the caller of the RPC and are handed through untouched.
  static func withFilePathURLs<Request: PayloadExtractable, T>(
    from requestStream: GRPCAsyncRequestStream<Request>,
    temporaryDirectory: FBTemporaryDirectory,
    extractFromSubdir: Bool,
    _ body: ([URL]) async throws -> T
  ) async throws -> T {
    func readNextPayload() async throws -> Idb_Payload {
      guard let p = try await requestStream.requiredNext.extractPayload()
      else { throw GRPCStatus(code: .failedPrecondition, message: "Incorrect request. Expected payload") }
      return p
    }

    var payload = try await readNextPayload()

    var compression = FBCompressionFormat.GZIP

    if case let .compression(payloadCompression) = payload.source {
      compression = compressionFormat(from: payloadCompression)
      payload = try await readNextPayload()
    }

    switch payload.source {
    case let .data(data):
      let (readTaskFromStreamTask, input) = pipeToInput(initialData: data, requestStream: requestStream)
      let mappedInput = input.retyped(FBProcessInput<AnyObject>.self)

      return try await temporaryDirectory.withArchiveExtracted(fromStream: mappedInput, compression: compression) { extractionDir in
        let files: [URL]
        if extractFromSubdir {
          files = try temporaryDirectory.files(inSubdirectoriesOf: extractionDir)
        } else {
          files = try FileManager.default.contentsOfDirectory(at: extractionDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
        }
        // We just check that read from request stream did not produce any errors
        _ = try await readTaskFromStreamTask.value
        return try await body(files)
      }

    case let .filePath(filePath):
      let filePaths = try await filepathsFromStream(initial: .init(fileURLWithPath: filePath), requestStream: requestStream)
      return try await body(filePaths)

    case .url, .compression, .none:
      throw GRPCStatus(code: .invalidArgument, message: "Unrecogized initial payload type \(payload.source as Any)")
    }
  }

  private static func compressionFormat(from request: Idb_Payload.Compression) -> FBCompressionFormat {
    switch request {
    case .gzip:
      return .GZIP
    case .zstd:
      return .ZSTD
    case .UNRECOGNIZED:
      return .GZIP
    }
  }

  private static func filepathsFromStream<Request: PayloadExtractable>(initial: URL, requestStream: GRPCAsyncRequestStream<Request>) async throws -> [URL] {
    var filePaths = [initial]

    for try await request in requestStream {
      guard let payload = request.extractPayload()
      else { throw GRPCStatus(code: .invalidArgument, message: "Unrecogized buffer frame. Expect payload, got \(request)") }

      guard case .filePath(let filePath) = payload.source
      else { throw GRPCStatus(code: .invalidArgument, message: "Unrecogized buffer frame. Expect file path, got \(payload.source as Any)") }

      filePaths.append(URL(fileURLWithPath: filePath))
    }

    return filePaths
  }

  // TODO: Do we really need multithreading here? Isnt we just fill the stream sequentially while read is blocked and only then read starts?
  private static func pipeToInput<Request: PayloadExtractable>(initialData: Data, requestStream: GRPCAsyncRequestStream<Request>) -> (Task<Void, Error>, FBProcessInput<OutputStream>) {
    let input = FBProcessInput<OutputStream>.fromStream()
    let stream = input.contents

    let readFromStreamTask = Task {
      stream.open()
      defer { stream.close() }

      var buffer = [UInt8](initialData)
      stream.write(&buffer, maxLength: buffer.count)

      for try await request in requestStream {
        guard let payload = request.extractPayload()
        else { throw GRPCStatus(code: .invalidArgument, message: "Unrecogized buffer frame. Expect payload, got \(request)") }

        guard case .data(let data) = payload.source
        else { throw GRPCStatus(code: .invalidArgument, message: "Unrecogized buffer frame. Expect file path, got \(payload.source as Any)") }

        var buffer = [UInt8](data)
        stream.write(&buffer, maxLength: buffer.count)
      }
    }

    return (readFromStreamTask, input)
  }
}
