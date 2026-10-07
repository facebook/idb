/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation
import GRPCCore
import IDBGRPCSwift

enum MultisourceFileReader {

  /// Hands the file URLs from the request stream to `body`. Files extracted from a streamed
  /// archive live in a temporary directory scoped to `body`; files referenced by path belong to
  /// the caller of the RPC and are handed through untouched.
  static func withFilePathURLs<Request: PayloadExtractable, T>(
    from requestStream: RequestStreamReader<Request>,
    temporaryDirectory: TemporaryDirectory,
    extractFromSubdir: Bool,
    _ body: ([URL]) async throws -> T
  ) async throws -> T {
    func readNextPayload() async throws -> Idb_Payload {
      guard let p = try await requestStream.requiredNext().extractPayload()
      else { throw RPCError(code: .failedPrecondition, message: "Incorrect request. Expected payload") }
      return p
    }

    var payload = try await readNextPayload()

    var compression = FBCompressionFormat.GZIP

    if case let .compression(payloadCompression) = payload.source {
      compression = FBCompressionFormat(payloadCompression)
      payload = try await readNextPayload()
    }

    switch payload.source {
    case let .data(data):
      let (readTaskFromStreamTask, pipe) = pipeToInput(initialData: data, requestStream: requestStream)

      return try await temporaryDirectory.withArchiveExtracted(fromStream: pipe, compression: compression) { extractionDir in
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
      throw RPCError(code: .invalidArgument, message: "Unrecognized initial payload type \(payload.source as Any)")
    }
  }

  private static func filepathsFromStream<Request: PayloadExtractable>(initial: URL, requestStream: RequestStreamReader<Request>) async throws -> [URL] {
    var filePaths = [initial]

    for try await request in requestStream {
      guard let payload = request.extractPayload()
      else { throw RPCError(code: .invalidArgument, message: "Unrecognized buffer frame. Expect payload, got \(request)") }

      guard case .filePath(let filePath) = payload.source
      else { throw RPCError(code: .invalidArgument, message: "Unrecognized buffer frame. Expect file path, got \(payload.source as Any)") }

      filePaths.append(URL(fileURLWithPath: filePath))
    }

    return filePaths
  }

  private static func pipeToInput<Request: PayloadExtractable>(initialData: Data, requestStream: RequestStreamReader<Request>) -> (Task<Void, Error>, BytePipe) {
    let pipe = BytePipe()

    let readFromStreamTask = Task {
      defer { pipe.input.finish() }
      try await writePayloads(initialData: initialData, from: requestStream, to: pipe.input)
    }

    return (readFromStreamTask, pipe)
  }

  /// Writes `initialData` and then every payload in `requestStream` to `input`, each write awaited so
  /// the request stream is read no faster than the extractor reads the pipe.
  static func writePayloads<Request: PayloadExtractable>(
    initialData: Data,
    from requestStream: RequestStreamReader<Request>,
    to input: InputSource
  ) async throws {
    let frames = requestStream.map { request -> Data in
      guard let payload = request.extractPayload()
      else { throw RPCError(code: .invalidArgument, message: "Unrecognized buffer frame. Expect payload, got \(request)") }

      guard case .data(let data) = payload.source
      else { throw RPCError(code: .invalidArgument, message: "Unrecognized buffer frame. Expect file path, got \(payload.source as Any)") }

      return data
    }
    try await PayloadPump.write(head: initialData, frames: frames, to: input)
  }
}
