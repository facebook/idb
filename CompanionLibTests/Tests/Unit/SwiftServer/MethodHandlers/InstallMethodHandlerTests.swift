/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
@preconcurrency import FBControlCore
import Foundation
import IDBGRPCSwift
import Testing

/// Installs streamed payloads through the handler onto the host Mac.
@Suite
struct InstallMethodHandlerTests {

  private struct StreamFailed: Error {}

  private let harness: MacInstallHarness
  private let handler: InstallMethodHandler

  init() throws {
    harness = try MacInstallHarness()
    handler = InstallMethodHandler(
      commandExecutor: harness.executor,
      targetLogger: FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false))
  }

  private static func request(_ destination: Idb_InstallRequest.Destination, head: Data, rest: AsyncThrowingStream<Data, any Error>) -> InstallRequest {
    InstallRequest(
      header: InstallHeader(destination: destination, payload: .with { $0.data = head }),
      payload: .data(head: head, rest: rest))
  }

  /// `payload` as a client streams it, in frames.
  private static func request(_ destination: Idb_InstallRequest.Destination, streaming payload: Data, compression: FBCompressionFormat = .GZIP) -> InstallRequest {
    let frames = stride(from: payload.startIndex, to: payload.endIndex, by: 64 * 1024).map { payload[$0..<min($0 + 64 * 1024, payload.endIndex)] }
    let rest = AsyncThrowingStream<Data, any Error> { continuation in
      frames.dropFirst().forEach { continuation.yield(Data($0)) }
      continuation.finish()
    }
    var request = Self.request(destination, head: Data(frames[0]), rest: rest)
    request.header.compression = compression
    return request
  }

  @Test
  func aZstdZipAppStreamIsInstalled() async throws {
    let app = try harness.makeBundle(named: "Sample", extension: "app", identifier: "com.example.sample")
    let payload = ArchiveFormat.zstdZipMarker + MacInstallHarness.zstd(try harness.zipData(of: app))

    let artifact = try await handler.install(Self.request(.app, streaming: payload))

    #expect(artifact.name == "com.example.sample")
  }

  @Test
  func aZstdTarDsymStreamIsInstalled() async throws {
    let dsym = try harness.makeBundle(named: "Sample", extension: "dSYM", identifier: "com.example.sample")
    let payload = MacInstallHarness.zstd(try harness.tarData(of: dsym))

    let artifact = try await handler.install(Self.request(.dsym, streaming: payload, compression: .ZSTD))

    #expect(artifact.name == "Sample.dSYM")
  }

  @Test
  func whenTheClientStreamFailsPartwayThroughATar() async throws {
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.framework")
    let archive = try await harness.gzippedTarData(of: framework)
    let rest = AsyncThrowingStream<Data, any Error> { continuation in
      continuation.finish(throwing: StreamFailed())
    }
    await #expect {
      _ = try await handler.install(Self.request(.framework, head: archive.prefix(archive.count / 2), rest: rest))
    } throws: { error in
      error is StreamFailed
    }
  }

  @Test
  func whenTheClientStreamFailsPartwayThroughAZstdZip() async throws {
    let app = try harness.makeBundle(named: "Sample", extension: "app", identifier: "com.example.sample")
    let payload = ArchiveFormat.zstdZipMarker + MacInstallHarness.zstd(try harness.zipData(of: app))
    let rest = AsyncThrowingStream<Data, any Error> { continuation in
      continuation.finish(throwing: StreamFailed())
    }
    await #expect {
      _ = try await handler.install(Self.request(.app, head: payload.prefix(payload.count / 2), rest: rest))
    } throws: { error in
      error is StreamFailed
    }
  }
}
