/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency internal import AccessibilityPlatformTranslation
import CoreSimulator
import FBSimulatorControl
import Foundation
@preconcurrency import XPC

/// Carries one translator request to the simulator's accessibility service and brings back its answer.
///
/// Synchronous because `AXPTranslator` asks its bridge delegate for an answer synchronously: the transport
/// is the one place that waits, and it never waits longer than `timeout`.
/// Which path carried a read's translator requests.
public enum AXTranslationTransportKind: String, Sendable {
  /// Straight to CoreSimulatorBridge's accessibility service.
  case bridge
  /// Through CoreSimulator's own client.
  case coreSimulator = "coresimulator"
}

protocol AXTranslationTransport: Sendable {
  var kind: AXTranslationTransportKind { get }

  /// The service's answer, or nil when none arrived within `timeout`. Must not be called on the main queue.
  func send(_ request: AXPTranslatorRequest, timeout: TimeInterval) -> AXPTranslatorResponse?
}

/// Sends translator requests through CoreSimulator's own client,
/// `-[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:]`.
final class CoreSimulatorAXTranslationTransport: AXTranslationTransport, @unchecked Sendable {
  let kind = AXTranslationTransportKind.coreSimulator

  // SAFETY: both are only read after init; `SimDevice` messages its service from any queue.
  private let device: SimDevice
  private let completionQueue: DispatchQueue

  init(device: SimDevice) {
    self.device = device
    self.completionQueue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.accessibility_translator.callback")
  }

  func send(_ request: AXPTranslatorRequest, timeout: TimeInterval) -> AXPTranslatorResponse? {
    let answered = DispatchSemaphore(value: 0)
    let box = ResponseBox()
    device.sendAccessibilityRequestAsync(request, completionQueue: completionQueue) { response in
      box.response = response
      answered.signal()
    }
    guard answered.wait(timeout: .now() + timeout) == .success else {
      return nil
    }
    return box.response
  }
}

/// Sends translator requests straight to the service CoreSimulator's client talks to,
/// `com.apple.CoreSimulator.accessibility`, which CoreSimulatorBridge vends inside the simulator.
///
/// The bridge answers one archived `AXPTranslatorRequest` per message, on a single serial queue, so this
/// holds one connection and sends one request at a time, as the translator asks for them. Unlike
/// CoreSimulator's client it hops through no queue of CoreSimulator's own, and it ignores the
/// notifications the bridge pushes to every peer: nothing here consumes them, and handing them to the
/// translator would touch it off the queue that serializes it.
final class CoreSimulatorBridgeAXTranslationTransport: AXTranslationTransport, @unchecked Sendable {
  static let serviceName = "com.apple.CoreSimulator.accessibility"

  let kind = AXTranslationTransportKind.bridge

  // SAFETY: `channel` is only read or replaced under `lock`; the rest is immutable.
  private let connector: SimulatorXPCConnector
  private let queue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.accessibility_translator.bridge")
  private let lock = NSLock()
  private var channel: SimulatorXPCChannel?

  init(connector: SimulatorXPCConnector) {
    self.connector = connector
  }

  /// Connects to the service now, so a caller can tell a simulator that does not vend it from one that
  /// does before choosing this transport.
  func connect() throws {
    _ = try connectedChannel()
  }

  func send(_ request: AXPTranslatorRequest, timeout: TimeInterval) -> AXPTranslatorResponse? {
    guard let message = AXTranslationWire.message(for: request), let channel = try? connectedChannel() else {
      return nil
    }
    let answered = DispatchSemaphore(value: 0)
    let box = ReplyBox()
    channel.request(message) { result in
      box.result = result
      answered.signal()
    }
    guard answered.wait(timeout: .now() + timeout) == .success, let result = box.result else {
      return nil
    }
    switch result {
    case let .success(reply):
      return AXTranslationWire.response(from: reply)
    case .failure:
      // XPC answered for a bridge that went away; the reply can beat the invalidation event, so the next
      // send must not wait for it to look the service up again.
      discard(channel)
      return nil
    }
  }

  /// The live channel, or a new one when there is none: on first use, and after the bridge went away
  /// (CoreSimulatorBridge is restarted to recover a stale SpringBoard).
  private func connectedChannel() throws -> SimulatorXPCChannel {
    lock.lock()
    defer { lock.unlock() }
    if let channel {
      return channel
    }
    let channel = SimulatorXPCChannel(connection: try connector.connect(Self.serviceName), queue: queue)
    channel.activate { [weak self, weak channel] event in
      guard case .invalidated = event, let self, let channel else { return }
      self.discard(channel)
    }
    self.channel = channel
    return channel
  }

  private func discard(_ invalidated: SimulatorXPCChannel) {
    lock.lock()
    defer { lock.unlock() }
    if channel === invalidated {
      channel = nil
    }
  }
}

/// The messages the accessibility service exchanges: a class name, and the archived object in a nested
/// payload dictionary.
enum AXTranslationWire {
  static let payloadClassNameKey = "SimAccessibility_PayloadClassName"
  static let payloadKey = "SimAccessibility_Payload"
  static let requestKey = "translatorRequest"
  static let responseKey = "translatorResponse"

  static func message(for request: AXPTranslatorRequest) -> xpc_object_t? {
    guard let data = try? NSKeyedArchiver.archivedData(withRootObject: request, requiringSecureCoding: true) else {
      return nil
    }
    return envelope(className: "AXPTranslatorRequest", key: requestKey, data: data)
  }

  /// Nil for anything but an archived `AXPTranslatorResponse`.
  static func response(from reply: xpc_object_t) -> AXPTranslatorResponse? {
    guard let data = payload(of: reply, className: "AXPTranslatorResponse", key: responseKey) else {
      return nil
    }
    return try? NSKeyedUnarchiver.unarchivedObject(ofClass: AXPTranslatorResponse.self, from: data)
  }

  static func envelope(className: String, key: String, data: Data) -> xpc_object_t {
    let payload = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_value(payload, key, data.withUnsafeBytes { xpc_data_create($0.baseAddress, $0.count) })
    let message = xpc_dictionary_create(nil, nil, 0)
    xpc_dictionary_set_string(message, payloadClassNameKey, className)
    xpc_dictionary_set_value(message, payloadKey, payload)
    return message
  }

  static func payload(of message: xpc_object_t, className: String, key: String) -> Data? {
    guard xpc_get_type(message) == XPC_TYPE_DICTIONARY,
      let name = xpc_dictionary_get_string(message, payloadClassNameKey), String(cString: name) == className,
      let payload = xpc_dictionary_get_value(message, payloadKey), xpc_get_type(payload) == XPC_TYPE_DICTIONARY
    else {
      return nil
    }
    var length = 0
    guard let bytes = xpc_dictionary_get_data(payload, key, &length) else {
      return nil
    }
    return Data(bytes: bytes, count: length)
  }
}

/// Mutable holder so the synchronous send can capture the response out of a `@Sendable` completion
/// handler. The semaphore wait establishes the happens-before needed before the value is read.
private final class ResponseBox: @unchecked Sendable {
  var response: AXPTranslatorResponse?
}

/// As `ResponseBox`, for the channel's reply.
private final class ReplyBox: @unchecked Sendable {
  var result: Result<xpc_object_t, SimulatorXPCError>?
}
