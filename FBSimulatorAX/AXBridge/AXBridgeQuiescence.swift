/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import FBSimulatorBridgeProtocol
import FBSimulatorControl
import Foundation

extension QuiescenceEvent {
  /// Decodes one frame of a `quiet` stream. A failure throws the guest's typed failure.
  init(axBridgeFrame frame: BridgeAXAnswer, pid requestedPid: pid_t?) throws {
    switch try AXBridgeResponse.decode(frame, as: BridgeAXQuiescenceEvent.self, context: "quiescence", pid: requestedPid) {
    case let .state(state, signals, pid):
      self = .state(Self.state(state, busySignals: signals), pid: pid)
    case let .touchesCompleted(pid):
      self = .touchesCompleted(pid: pid)
    case let .targetChanged(pid):
      self = .targetChanged(pid: pid)
    case let .targetExited(pid):
      self = .targetExited(pid: pid)
    }
  }

  private static func state(_ state: AXWire.Quiescence.State, busySignals: [AXWire.Quiescence.Signal]) -> QuiescenceState {
    switch state {
    case .busy: .busy(Set(busySignals.map(QuiescenceSignal.init)))
    case .settling: .settling
    case .quiet: .quiet
    }
  }
}

extension QuiescenceEvent {
  var pid: pid_t {
    switch self {
    case let .state(_, pid), let .touchesCompleted(pid), let .targetChanged(pid), let .targetExited(pid): pid
    }
  }

  /// Whether the event comes from an application still being followed, rather than announcing a new target
  /// or the end of one.
  var reportsLiveTarget: Bool {
    switch self {
    case .state, .touchesCompleted: true
    case .targetChanged, .targetExited: false
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
