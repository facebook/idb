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

/// Seam over the `IDBCommandExecutor` calls this handler drives, so the request-to-stream wiring can be
/// tested against a double.
protocol AccessibilityQuiescenceStreaming {
  func accessibility_quiescence(
    query: AccessibilityElementQuery,
    parameters: QuiescenceParameters,
    backend: UIAutomationBackend
  ) async throws -> AsyncThrowingStream<QuiescenceEvent, Error>

  func process_id(forBundleID bundleID: String) async throws -> pid_t
}

extension IDBCommandExecutor: AccessibilityQuiescenceStreaming {}

struct AccessibilityQuiescenceMethodHandler {

  let commandExecutor: IDBCommandExecutor

  func handle(request: Idb_AccessibilityQuiescenceRequest, responseStream: RPCWriter<Idb_AccessibilityQuiescenceResponse>, context: ServerContext) async throws {
    try await Self.stream(request, using: commandExecutor) { try await responseStream.send($0) }
  }

  /// Forwards every event until the stream ends. A client cancelling the call cancels this task, which
  /// closes the stream and the guest measuring it.
  static func stream(
    _ request: Idb_AccessibilityQuiescenceRequest,
    using commandExecutor: any AccessibilityQuiescenceStreaming,
    send: (Idb_AccessibilityQuiescenceResponse) async throws -> Void
  ) async throws {
    let query: AccessibilityElementQuery
    switch request.target {
    case let .pid(pid):
      guard let pid = pid_t(exactly: pid), pid > 0 else {
        throw RPCError(code: .invalidArgument, message: "\(pid) is not a pid")
      }
      query = .application(pid: pid)
    case let .bundleID(bundleID):
      query = .application(pid: try await commandExecutor.process_id(forBundleID: bundleID))
    case nil:
      query = .frontmost
    }
    // The companion owns its simulator for its whole run, so it holds its own bridge, as reads do.
    let events = try await commandExecutor.accessibility_quiescence(
      query: query, parameters: parameters(from: request), backend: UIAutomationBackend(resolvedName: .axBridgeExclusive))
    for try await event in events {
      try await send(response(for: event))
    }
  }

  static func parameters(from request: Idb_AccessibilityQuiescenceRequest) -> QuiescenceParameters {
    var parameters = QuiescenceParameters()
    if case let .busyThresholdMs(milliseconds) = request.busyThreshold {
      parameters.busyThreshold = TimeInterval(milliseconds) / 1000
    }
    if case let .quietWindowMs(milliseconds) = request.quietWindow {
      parameters.quietWindow = TimeInterval(milliseconds) / 1000
    }
    return parameters
  }

  static func response(for event: QuiescenceEvent) -> Idb_AccessibilityQuiescenceResponse {
    switch event {
    case let .state(state, pid):
      return .with {
        $0.pid = UInt64(pid)
        $0.state = .with {
          switch state {
          case let .busy(signals):
            $0.state = .busy
            $0.busySignals = signals.sorted { $0.rawValue < $1.rawValue }.map(signal)
          case .settling:
            $0.state = .settling
          case .quiet:
            $0.state = .quiet
          }
        }
      }
    case let .touchesCompleted(pid):
      return .with {
        $0.pid = UInt64(pid)
        $0.touchesCompleted = .init()
      }
    case let .targetChanged(pid):
      return .with {
        $0.pid = UInt64(pid)
        $0.targetChanged = .init()
      }
    case let .targetExited(pid):
      return .with {
        $0.pid = UInt64(pid)
        $0.targetExited = .init()
      }
    }
  }

  private static func signal(_ signal: QuiescenceSignal) -> Idb_AccessibilityQuiescenceResponse.Signal {
    switch signal {
    case .runLoopIdle: .runLoopIdle
    case .animationsInactive: .animationsInactive
    }
  }
}
