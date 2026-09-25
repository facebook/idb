/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import CoreSimulator
import Darwin
@preconcurrency import FBControlCore
import Foundation

/**
 Input for a Simulator: `SimulatorHIDEvent`s (touch, two-finger touch, button, remote button, keyboard,
 trackpad, delays and composites of them), delivered through a pluggable `SimulatorHIDTransport`
 (negotiated between `dtuhidd` and the legacy Indigo client).

 Device actions — rotation, the hinge, lock, shake, the in-call status bar — are not input and are
 commands on the `Simulator` (`orientation`, `hinge`, `hardware`, `statusBar`).

 See `Indigo.h` for wire format documentation.
 */
public final class SimulatorHID: CustomStringConvertible, Sendable {

  // MARK: - Properties

  /// The transport for the touch / button / keyboard primitives.
  private let transport: SimulatorHIDTransport

  // MARK: - Initializers

  /// `transport` forces a HID path; `nil` negotiates one (see `SimulatorHIDTransport.negotiate(for:requested:)`). Throws if the
  /// transport cannot be established (registration may need to occur prior to booting).
  convenience init(
    for simulator: Simulator, transport transportType: SimulatorHIDTransportType? = nil
  ) async throws {
    self.init(transport: try await SimulatorHIDTransport.negotiate(for: simulator, requested: transportType))
  }

  init(transport: SimulatorHIDTransport) {
    self.transport = transport
  }

  /// Drains pending events before disconnecting, even when the caller is cancelled.
  /// Drain errors do not prevent disconnection.
  func close() async {
    let drain = Task { try await flush() }
    try? await drain.value
    transport.disconnect()
  }

  // MARK: - Input transport

  /// Drains the transport so `dtuhidd` consumes a gesture before the connection is torn down.
  func flush() async throws {
    try await transport.flush()
  }

  // MARK: - Dispatch

  /// Sends a (possibly composite) event, logging each sub-event. With `.perEvent` it then drains once —
  /// so a tap or typed string settles once, not per primitive. The transport skips the drain when
  /// nothing reached it.
  public func send(
    event: SimulatorHIDEvent, logger: ControlCoreLogger, drain: SimulatorHIDDrain = .perEvent
  ) async throws {
    for subEvent in event.subEvents ?? [event] {
      switch subEvent {
      case let .delay(duration):
        logger.log("Delay \(duration)s")
      case .touch, .button, .remoteButton, .keyboard, .twoFingerTouch, .trackpad, .composite:
        logger.log("Sending \(subEvent)")
      }
      try await deliver(subEvent)
    }
    if case .perEvent = drain {
      try await flush()
    }
  }

  /// Routes one event to its transport.
  func deliver(_ event: SimulatorHIDEvent) async throws {
    switch event {
    case let .touch(direction, x, y, edge):
      try await transport.primitives.sendTouch(direction: direction, x: x, y: y, edge: edge)
    case let .button(direction, button):
      try await transport.primitives.sendButton(direction: direction, button: button)
    case let .remoteButton(direction, button):
      try await transport.primitives.sendRemoteButton(direction: direction, button: button)
    case let .keyboard(direction, keyCode):
      try await transport.primitives.sendKeyboard(direction: direction, keyCode: keyCode)
    case let .twoFingerTouch(direction, finger1, finger2):
      try await transport.primitives.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2)
    case let .trackpad(phase, point):
      try await transport.sendTrackpad(point: point, phase: phase)
    case let .delay(duration):
      try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
    case let .composite(events):
      for event in events {
        try await deliver(event)
      }
    }
  }

  public var description: String {
    "SimulatorKit HID"
  }
}

/// When `SimulatorHID.send(event:logger:drain:)` waits for `dtuhidd` to consume what it sent.
public enum SimulatorHIDDrain: Sendable {
  /// Before returning, so the guest has acted on the event by the time the caller observes it.
  case perEvent
  /// Only when the HID is closed, which always drains. For a stream of events the caller does not
  /// observe between, where a per-event drain is pure latency.
  case onClose
}
