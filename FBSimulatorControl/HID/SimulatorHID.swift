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
 (`dtuhidd` or the legacy Indigo client, whichever the toolchain supports).

 Device actions — rotation, the hinge, lock, shake, the in-call status bar — are not input and are
 commands on the `Simulator` (`orientation`, `hinge`, `hardware`, `statusBar`).

 See `Indigo.h` for wire format documentation.
 */
public final class SimulatorHID: CustomStringConvertible, Sendable {

  // MARK: - Properties

  /// The transport for the touch / button / keyboard primitives.
  private let transport: SimulatorHIDTransport
  private let operationLease: SimulatorHIDOperationLease
  private let displays: (any DisplayCommands)?
  private let logging: SimulatorHIDEventLogging

  // MARK: - Initializers

  /// `transport` forces a HID path; `nil` negotiates one (see `SimulatorHIDTransport.negotiate(for:requested:)`). Throws if the
  /// transport cannot be established (registration may need to occur prior to booting).
  convenience init(
    for simulator: Simulator, transport transportType: SimulatorHIDTransportType? = nil
  ) async throws {
    self.init(
      transport: try await SimulatorHIDTransport.negotiate(for: simulator, requested: transportType),
      operationLease: simulator.commandCache.resolve { SimulatorHIDOperationLease() },
      displays: simulator.displays,
      logging: simulator.set?.configuration.hidEventLogging ?? .redacted)
  }

  /// Instances sharing `operationLease` never interleave operations.
  init(
    transport: SimulatorHIDTransport,
    operationLease: SimulatorHIDOperationLease = SimulatorHIDOperationLease(),
    displays: (any DisplayCommands)? = nil,
    logging: SimulatorHIDEventLogging = .redacted
  ) {
    self.transport = transport
    self.operationLease = operationLease
    self.displays = displays
    self.logging = logging
  }

  /// Drains pending events before disconnecting, even when the caller is cancelled.
  /// Drain errors do not prevent disconnection.
  func close() async {
    let close = Task {
      try? await operationLease.withLease {
        try? await flush()
        transport.disconnect()
      }
    }
    await close.value
  }

  // MARK: - Input transport

  /// Drains the transport so `dtuhidd` consumes a gesture before the connection is torn down.
  func flush() async throws {
    try await transport.flush()
  }

  // MARK: - Dispatch

  /// Sends one complete gesture whose touches land on `binding`. With `.perEvent` it then drains once —
  /// so a tap or typed string settles once, not per primitive. The transport skips the drain when
  /// nothing reached it.
  public func send(
    event: SimulatorHIDEvent,
    logger: ControlCoreLogger,
    drain: SimulatorHIDDrain = .perEvent,
    on binding: SimulatorHIDDisplayBinding = .active
  ) async throws {
    let events = AsyncStream<SimulatorHIDEvent> { continuation in
      continuation.yield(event)
      continuation.finish()
    }
    try await send(events: events, logger: logger, flushing: drain == .perEvent, binding: binding)
  }

  /// Sends a stream as one operation whose touches land on `binding`. Touch coordinates use the display resolved
  /// at the first touch. An observed display change fails the operation; cancellation releases contacts on the
  /// original display.
  public func send<S: AsyncSequence>(
    events: S, logger: ControlCoreLogger, on binding: SimulatorHIDDisplayBinding = .active
  ) async throws where S.Element == SimulatorHIDEvent {
    try await send(events: events, logger: logger, flushing: true, binding: binding)
  }

  private func send<S: AsyncSequence>(
    events: S, logger: ControlCoreLogger, flushing: Bool, binding: SimulatorHIDDisplayBinding
  ) async throws where S.Element == SimulatorHIDEvent {
    try await operationLease.withLease {
      var operation = SimulatorHIDOperation(
        displays: displays,
        binding: binding,
        sink: LoggingSink(hid: self, logger: logger, logging: logging))
      do {
        for try await event in events {
          for delivery in try await operation.send(event) {
            if case .clamped = delivery { logger.log(delivery.logDescription(logging)) }
          }
        }
        try await operation.finish(flushing: flushing)
      } catch {
        for failure in await operation.cleanup() { logger.log("HID cleanup failed: \(failure)") }
        throw error
      }
    }
  }

  /// Routes one event to its transport.
  func deliver(_ event: SimulatorHIDEvent, display: SimulatorHIDDisplay? = nil) async throws {
    switch event {
    case let .touch(direction, x, y, edge):
      try await transport.primitives.sendTouch(direction: direction, x: x, y: y, edge: edge, display: display)
    case let .button(direction, button):
      try await transport.primitives.sendButton(direction: direction, button: button)
    case let .remoteButton(direction, button):
      try await transport.primitives.sendRemoteButton(direction: direction, button: button)
    case let .keyboard(direction, keyCode):
      try await transport.primitives.sendKeyboard(direction: direction, keyCode: keyCode)
    case let .twoFingerTouch(direction, finger1, finger2):
      try await transport.primitives.sendTwoFingerTouch(direction: direction, finger1: finger1, finger2: finger2, display: display)
    case let .trackpad(phase, point):
      try await transport.sendTrackpad(point: point, phase: phase)
    case let .delay(duration):
      try await Task.sleep(nanoseconds: UInt64(max(0, duration) * 1_000_000_000))
    case let .composite(events):
      for event in events {
        try await deliver(event, display: display)
      }
    }
  }

  public var description: String {
    "SimulatorKit HID"
  }
}

/// One operation's view of the HID, logging each event before it is delivered.
private struct LoggingSink: SimulatorHIDOperationSink {
  let hid: SimulatorHID
  let logger: ControlCoreLogger
  let logging: SimulatorHIDEventLogging

  func deliver(_ event: SimulatorHIDEvent, display: SimulatorHIDDisplay?) async throws {
    if case let .delay(duration) = event {
      logger.log("Delay \(duration)s")
    } else {
      logger.log("Sending \(event.logDescription(logging))")
    }
    try await hid.deliver(event, display: display)
  }

  func flush() async throws {
    try await hid.flush()
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
