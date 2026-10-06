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
      targetLogger: FBControlCoreLoggerFactory.systemLoggerWriting(toStderr: false, withDebugLogging: false),
      streamCapabilities: StreamCapabilities(searchPath: nil))
  }

  private static func request(_ destination: Idb_InstallRequest.Destination, head: Data, rest: AsyncThrowingStream<Data, any Error>) -> InstallRequest {
    InstallRequest(
      header: InstallHeader(destination: destination, payload: .with { $0.data = head }),
      payload: .data(head: head, rest: rest))
  }

  @Test
  func whenTheClientStreamFailsPartwayThroughATar() async throws {
    let framework = try harness.makeBundle(named: "Sample", extension: "framework", identifier: "com.example.framework")
    let archive = try harness.gzippedTarData(of: framework)
    let rest = AsyncThrowingStream<Data, any Error> { continuation in
      continuation.finish(throwing: StreamFailed())
    }
    await #expect {
      _ = try await handler.install(Self.request(.framework, head: archive.prefix(archive.count / 2), rest: rest))
    } throws: { error in
      // BUG: the truncated archive's extraction failure is reported instead of the stream failure that caused it — flipped in the following commit.
      guard case InstallError.extractionFailed = error else {
        return false
      }
      return true
    }
  }
}
