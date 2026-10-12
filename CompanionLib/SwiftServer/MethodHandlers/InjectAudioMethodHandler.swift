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
import ShimulatorAudioInjectionCore

struct InjectAudioMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(
    requestStream: RequestStreamReader<Idb_InjectAudioRequest>,
    context: ServerContext
  ) async throws -> Idb_InjectAudioResponse {
    do {
      try await Self.withAudioInjection(
        from: requestStream,
        temporaryDirectory: commandExecutor.temporaryDirectory,
        cancellation: context.cancellation
      ) { audioFileURL in
        try await commandExecutor.inject_audio(audioFileURL)
      }
    } catch let error as SimulatorAudioError {
      throw Self.rpcError(for: error)
    } catch let error as IDBCommandError {
      if let rpcError = Self.rpcError(for: error) {
        throw rpcError
      }
      throw error
    }
    return .init()
  }

  static func withAudioInjection(
    from requestStream: RequestStreamReader<Idb_InjectAudioRequest>,
    temporaryDirectory: TemporaryDirectory,
    cancellation: ServerContext.RPCCancellationHandle,
    _ body: @escaping @Sendable (URL) async throws -> Void
  ) async throws {
    try await withRPCCancellation(cancellation) {
      try await withAudioFile(from: requestStream, temporaryDirectory: temporaryDirectory, body)
    }
  }

  static func withAudioFile<T>(
    from requestStream: RequestStreamReader<Idb_InjectAudioRequest>,
    temporaryDirectory: TemporaryDirectory,
    _ body: (URL) async throws -> T
  ) async throws -> T {
    guard let payload = try await requestStream.requiredNext().extractPayload() else {
      throw RPCError(code: .invalidArgument, message: "Audio injection requires a payload")
    }
    switch payload.source {
    case let .filePath(path):
      try await requireEnd(of: requestStream)
      let url = URL(fileURLWithPath: path)
      try validateRegularFile(url)
      return try await body(url)
    case let .data(initialData):
      let data = try await collectAudioData(initialData, from: requestStream)
      return try await temporaryDirectory.withTemporaryDirectory { directory in
        let url = directory.appendingPathComponent("input.wav")
        try data.write(to: url, options: .atomic)
        return try await body(url)
      }
    case .compression, .url, .none:
      throw RPCError(
        code: .invalidArgument,
        message: "Audio injection accepts one local file path or raw WAV bytes")
    }
  }

  private static func collectAudioData(
    _ initialData: Data,
    from requestStream: RequestStreamReader<Idb_InjectAudioRequest>
  ) async throws -> Data {
    let maximumBytes = ShimulatorAudioInjection.maximumPayloadBytes
    guard initialData.count <= maximumBytes else {
      throw payloadTooLarge(maximumBytes: maximumBytes)
    }
    var audio = initialData
    for try await request in requestStream {
      guard let payload = request.extractPayload(), case let .data(data) = payload.source else {
        throw RPCError(code: .invalidArgument, message: "Audio injection data frames must contain raw WAV bytes")
      }
      guard data.count <= maximumBytes - audio.count else {
        throw payloadTooLarge(maximumBytes: maximumBytes)
      }
      audio.append(data)
    }
    return audio
  }

  private static func requireEnd(
    of requestStream: RequestStreamReader<Idb_InjectAudioRequest>
  ) async throws {
    for try await _ in requestStream {
      throw RPCError(code: .invalidArgument, message: "Audio injection requires exactly one local file path")
    }
  }

  private static func validateRegularFile(_ fileURL: URL) throws {
    guard
      let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
      values.isRegularFile == true
    else {
      throw RPCError(
        code: .invalidArgument,
        message: "Audio injection input does not exist or is not a regular file: \(fileURL.path)")
    }
  }

  private static func payloadTooLarge(maximumBytes: Int) -> RPCError {
    RPCError(
      code: .invalidArgument,
      message: "Audio injection input exceeds the \(maximumBytes)-byte limit")
  }

  static func rpcError(for error: SimulatorAudioError) -> RPCError {
    let code: RPCError.Code
    switch error {
    case .injectionUnreadable, .injectionFileUnreadable, .injectionFileTooLarge,
      .volumeOutOfRange:
      code = .invalidArgument
    case .injectionAlreadyRunning, .injectionUnclaimed, .injectionDidNotFinish,
      .injectionUnsupportedPlatform, .injectionFailedInGuest:
      code = .failedPrecondition
    case .noDataDirectory, .unreadable, .malformed, .volumeMissing,
      .injectionShimMissing, .injectionSocketUnavailable, .injectionArmingFailed:
      code = .internalError
    }
    return RPCError(code: code, message: error.localizedDescription)
  }

  static func rpcError(for error: IDBCommandError) -> RPCError? {
    guard case .notASimulator = error else {
      return nil
    }
    return RPCError(code: .failedPrecondition, message: error.localizedDescription)
  }
}
