/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import CompanionLib
import FBControlCore
import Foundation
import GRPCCore
import IDBGRPCSwift
import Testing

/// An xctrace that exits with `status` on its own, or never exits until stopped when `status` is nil.
private final class FakeRecording: XCTraceRecording, @unchecked Sendable {
  private let status: Int32?
  private let lock = NSLock()
  private var timeouts: [TimeInterval] = []

  init(exitingWith status: Int32?) {
    self.status = status
  }

  var stopTimeouts: [TimeInterval] {
    lock.lock()
    defer { lock.unlock() }
    return timeouts
  }

  func exitStatus() async throws -> Int32 {
    if let status {
      return status
    }
    try await Task.sleep(for: .seconds(3600))
    throw CancellationError()
  }

  func stop(withTimeout timeout: TimeInterval) async throws -> URL {
    lock.lock()
    timeouts.append(timeout)
    lock.unlock()
    return URL(fileURLWithPath: "/tmp/fake.trace")
  }
}

private enum Outcome {
  case returned(Idb_XctraceRecordRequest.Stop)
  case threw(any Error)
  case stillWaiting
}

/// A request stream the test controls: it yields what the test sends and never ends on its own.
private func clientStream() -> (RequestStreamReader<Idb_XctraceRecordRequest>, AsyncThrowingStream<Idb_XctraceRecordRequest, any Error>.Continuation) {
  let (stream, continuation) = AsyncThrowingStream.makeStream(of: Idb_XctraceRecordRequest.self, throwing: (any Error).self)
  return (RequestStreamReader(RPCAsyncSequence(wrapping: stream)), continuation)
}

private func stopRequest(timeout: Double) -> Idb_XctraceRecordRequest {
  .with { $0.stop = .with { $0.timeout = timeout } }
}

/// How `recordUntilStopped` has finished after `wait`, cancelling it if it has not.
private func outcome(of recording: some XCTraceRecording, requests: RequestStreamReader<Idb_XctraceRecordRequest>, after wait: Duration = .milliseconds(300)) async -> Outcome {
  await withTaskGroup(of: Outcome.self) { group in
    group.addTask {
      do {
        return .returned(try await XctraceRecordMethodHandler.recordUntilStopped(requestStream: requests, recording: recording))
      } catch {
        return .threw(error)
      }
    }
    group.addTask {
      try? await Task.sleep(for: wait)
      return .stillWaiting
    }
    let first = await group.next() ?? .stillWaiting
    group.cancelAll()
    return first
  }
}

@Suite
struct XctraceRecordMethodHandlerTests {

  @Test
  func stopFromTheClientStopsXctraceWithTheRequestedTimeout() async throws {
    let recording = FakeRecording(exitingWith: nil)
    let (requests, client) = clientStream()
    client.yield(stopRequest(timeout: 42))

    let result = await outcome(of: recording, requests: requests)

    guard case let .returned(stop) = result else {
      Issue.record("expected recording to end on Stop, got \(result)")
      return
    }
    #expect(stop.timeout == 42)
    #expect(recording.stopTimeouts == [42])
  }

  @Test
  func stopWithoutATimeoutUsesTheDefault() async throws {
    let recording = FakeRecording(exitingWith: nil)
    let (requests, client) = clientStream()
    client.yield(stopRequest(timeout: 0))

    _ = await outcome(of: recording, requests: requests)

    #expect(recording.stopTimeouts == [DefaultXCTraceRecordStopTimeout])
  }

  /// A clean exit (such as reaching its time limit) leaves a trace to collect, so the session keeps
  /// waiting for the client to ask for it.
  @Test
  func xctraceExitingCleanlyStillWaitsForStop() async throws {
    let recording = FakeRecording(exitingWith: 0)
    let (requests, _) = clientStream()

    let result = await outcome(of: recording, requests: requests)

    guard case .stillWaiting = result else {
      Issue.record("expected recording to wait for Stop after a clean exit, got \(result)")
      return
    }
  }

  @Test
  func xctraceFailingBeforeStopEndsTheSession() async throws {
    let recording = FakeRecording(exitingWith: 1)
    let (requests, _) = clientStream()

    let result = await outcome(of: recording, requests: requests)

    guard case let .threw(error) = result else {
      Issue.record("expected recording to fail once xctrace exited, got \(result)")
      return
    }
    #expect((error as? RPCError)?.message.contains("status 1") == true)
    #expect(recording.stopTimeouts.isEmpty)
  }
}
