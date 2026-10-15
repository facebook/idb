/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation

/// The settings whose current values are published by a simulator settings source.
public struct SimulatorSettingsSnapshot: Equatable, Sendable {
  public let reduceMotionEnabled: Bool

  public init(reduceMotionEnabled: Bool) {
    self.reduceMotionEnabled = reduceMotionEnabled
  }
}

/// Why a simulator settings source could not publish values.
public enum SimulatorSettingsAvailability: Equatable, Sendable {
  /// The runtime, guest, or protocol does not provide the source.
  case unsupported(reason: String)
  /// The simulator may provide the source once its services are ready.
  case notReady(reason: String)
  /// The source failed without saying it can become ready or is permanently absent.
  case failed(reason: String)
}

/// Current simulator settings and the lifecycle of the source that publishes them.
///
/// This is latest-event transport, not history: a terminal event can replace a buffered snapshot.
/// A consumer can retain only the values it observed, and none is authoritative after unavailability.
public enum SimulatorSettingsEvent: Equatable, Sendable {
  case snapshot(SimulatorSettingsSnapshot)
  case unavailable(SimulatorSettingsAvailability)
  /// The guest ended a source that had not already reported unavailability.
  case sourceEnded
}

struct SimulatorSettingsPublisher: Sendable {
  typealias Source = @Sendable () async throws -> AsyncThrowingStream<Data, Error>

  private let source: Source

  init(source: @escaping Source) {
    self.source = source
  }

  func events() -> AsyncStream<SimulatorSettingsEvent> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let task = Task {
        var lastSnapshot: SimulatorSettingsSnapshot?
        var reportedTerminalState = false
        do {
          let frames = try await source()
          for try await frame in frames {
            guard !Task.isCancelled else { break }
            guard let event = try Self.event(from: frame) else { continue }
            switch event {
            case let .snapshot(snapshot):
              guard snapshot != lastSnapshot else { continue }
              lastSnapshot = snapshot
              continuation.yield(event)
            case .unavailable:
              reportedTerminalState = true
              continuation.yield(event)
            case .sourceEnded:
              continue
            }
            if reportedTerminalState { break }
          }
          if !Task.isCancelled && !reportedTerminalState {
            continuation.yield(.sourceEnded)
          }
        } catch {
          if !Task.isCancelled {
            continuation.yield(.unavailable(Self.availability(for: error)))
          }
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  static func event(from data: Data) throws -> SimulatorSettingsEvent? {
    guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw AXBridgeError.guestFailure("simulator settings response was not a JSON object")
    }
    let message = response[BridgeAXWire.Envelope.error.rawValue] as? String ?? "the guest reported no detail"
    guard response[BridgeAXWire.Envelope.ok.rawValue] as? Bool == true else {
      let errorKind = response[BridgeAXWire.Envelope.errorKind.rawValue] as? String
      return .unavailable(Self.availability(errorKind: errorKind, message: message))
    }
    guard response[BridgeAXWire.Settings.Key.event.rawValue] as? String == BridgeAXWire.Settings.Event.snapshot.rawValue,
      let setting = response[BridgeAXWire.Request.setting.rawValue] as? String,
      !setting.isEmpty
    else {
      throw AXBridgeError.guestFailure("simulator settings response was not a settings snapshot")
    }
    guard setting == "reduce-motion" else { return nil }
    guard let enabled = response[BridgeAXWire.Envelope.enabled.rawValue] as? Bool else {
      throw AXBridgeError.guestFailure("simulator settings response was not a Reduce Motion snapshot")
    }
    return .snapshot(SimulatorSettingsSnapshot(reduceMotionEnabled: enabled))
  }

  static func availability(errorKind: String?, message: String) -> SimulatorSettingsAvailability {
    guard let errorKind else { return .failed(reason: message) }
    switch errorKind {
    case BridgeAXWire.ErrorKind.capabilityUnavailable.rawValue, BridgeAXWire.ErrorKind.badRequest.rawValue:
      return .unsupported(reason: message)
    case BridgeAXWire.ErrorKind.applicationUnavailable.rawValue,
      BridgeAXWire.ErrorKind.applicationNotResponding.rawValue,
      BridgeAXWire.ErrorKind.frontmostUnresolved.rawValue:
      return .notReady(reason: message)
    case BridgeAXWire.ErrorKind.readerUnavailable.rawValue,
      BridgeAXWire.ErrorKind.assertionFailed.rawValue,
      BridgeAXWire.ErrorKind.runtimeFailed.rawValue:
      return .failed(reason: message)
    default:
      return .failed(reason: message)
    }
  }

  static func availability(for error: any Error) -> SimulatorSettingsAvailability {
    let reason = error.localizedDescription
    switch SimulatorFailureKind(error) {
    case let .unsupported(capability):
      return .unsupported(reason: capability)
    case .notReady:
      return .notReady(reason: reason)
    case .failed:
      if case AXBridgeError.bridgeUnavailable = error {
        return .unsupported(reason: reason)
      }
      return .failed(reason: reason)
    }
  }
}
