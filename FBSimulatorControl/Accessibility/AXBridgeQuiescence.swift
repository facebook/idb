/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

extension QuiescenceEvent {
  /// Decodes one frame of a `quiet` stream. An `ok: false` frame throws the guest's typed failure.
  init(axBridgeFrame frame: Data, pid requestedPid: pid_t?) throws {
    let response = try AXBridgeResponse.validated(frame, context: "quiescence", pid: requestedPid)
    guard let pid = (response[AXWire.Envelope.pid.rawValue] as? Int).flatMap(pid_t.init(exactly:)) else {
      throw AXBridgeError.guestFailure("quiescence event without a pid")
    }
    let rawEvent = response[AXWire.Quiescence.Key.event.rawValue] as? String
    switch rawEvent.flatMap(AXWire.Quiescence.Event.init(rawValue:)) {
    case .state:
      self = .state(try Self.state(of: response), pid: pid)
    case .touchesCompleted:
      self = .touchesCompleted(pid: pid)
    case .targetChanged:
      self = .targetChanged(pid: pid)
    case .targetExited:
      self = .targetExited(pid: pid)
    case .none:
      throw AXBridgeError.guestFailure("unknown quiescence event \(rawEvent ?? "(none)")")
    }
  }

  private static func state(of response: [String: Any]) throws -> QuiescenceState {
    let rawState = response[AXWire.Quiescence.Key.state.rawValue] as? String
    switch rawState.flatMap(AXWire.Quiescence.State.init(rawValue:)) {
    case .busy:
      let rawSignals = response[AXWire.Quiescence.Key.signals.rawValue] as? [String] ?? []
      return .busy(Set(rawSignals.compactMap(AXWire.Quiescence.Signal.init(rawValue:)).map(QuiescenceSignal.init)))
    case .settling:
      return .settling
    case .quiet:
      return .quiet
    case .none:
      throw AXBridgeError.guestFailure("unknown quiescence state \(rawState ?? "(none)")")
    }
  }
}

extension QuiescenceSignal {
  init(_ signal: AXWire.Quiescence.Signal) {
    switch signal {
    case .runLoopIdle: self = .runLoopIdle
    case .animationsInactive: self = .animationsInactive
    }
  }
}

extension QuiescenceParameters {
  var busyThresholdMs: Int? { busyThreshold.map(Self.milliseconds) }
  var quietWindowMs: Int? { quietWindow.map(Self.milliseconds) }

  private static func milliseconds(_ interval: TimeInterval) -> Int {
    Int((interval * 1000).rounded())
  }
}
