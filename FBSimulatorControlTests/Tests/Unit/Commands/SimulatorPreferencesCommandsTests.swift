/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite("Hardware keyboard setting")
struct SimulatorPreferencesCommandsTests {

  @Test("Enabling the hardware keyboard turns on automatic minimization before writing the attached state")
  func enable() {
    #expect(
      SimulatorPreferencesCommands.hardwareKeyboardSteps(enabled: true) == [
        .enableAutomaticMinimization, .write(enabled: true),
      ])
  }

  @Test("Disabling the hardware keyboard writes only the attached state")
  func disable() {
    #expect(SimulatorPreferencesCommands.hardwareKeyboardSteps(enabled: false) == [.write(enabled: false)])
  }
}

@Suite("Simulator settings stream")
struct SimulatorSettingsPublisherTests {

  @Test("The host requests the exclusive current-value-plus-changes source")
  func request() throws {
    let request = AXBridgeRequest.deviceSettingChanges("reduce-motion")
    #expect(request.payload as NSDictionary == ["verb": "settings-observe", "setting": "reduce-motion"])
    #expect(!request.mayRetry)
  }

  @Test("A combined snapshot preserves values and per-setting unavailability")
  func combinedSettings() throws {
    let frame = try JSONSerialization.data(withJSONObject: [
      "ok": true, "event": "snapshot", "setting": "state-settings", "enabled": false,
      "settings": [
        "button-shapes": ["ok": true, "enabled": true],
        "reduce-transparency": ["ok": false, "error": "missing getter", "error_kind": "capability_unavailable"],
        "increase-contrast": ["ok": true, "enabled": false],
      ],
    ])
    let event = try SimulatorSettingsPublisher.event(from: frame)
    #expect(
      event
        == .snapshot(
          SimulatorSettingsSnapshot(
            reduceMotionEnabled: false,
            reduceTransparency: .unavailable(.unsupported(reason: "missing getter")),
            buttonShapes: .available(true), increaseContrast: .available(false))))
  }

  @Test("A combined snapshot cannot silently omit an observed field")
  func incompleteCombinedSnapshot() throws {
    let frame = try JSONSerialization.data(withJSONObject: [
      "ok": true, "event": "snapshot", "setting": "state-settings", "enabled": false,
      "settings": [:],
    ])
    #expect(throws: (any Error).self) { try SimulatorSettingsPublisher.event(from: frame) }
  }

  @Test("Duplicate guest values are suppressed and clean source completion is explicit")
  func deduplicates() async throws {
    let (frames, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
    let publisher = SimulatorSettingsPublisher { frames }
    var iterator = publisher.events().makeAsyncIterator()

    continuation.yield(try snapshot(enabled: false))
    let first = await iterator.next()
    #expect(first == .snapshot(SimulatorSettingsSnapshot(reduceMotionEnabled: false)))

    continuation.yield(try snapshot(enabled: false))
    continuation.yield(try snapshot(enabled: true))
    let changed = await iterator.next()
    #expect(changed == .snapshot(SimulatorSettingsSnapshot(reduceMotionEnabled: true)))

    continuation.finish()
    let ended = await iterator.next()
    #expect(ended == .sourceEnded)
    #expect(await iterator.next() == nil)
  }

  @Test("An unknown setting before Reduce Motion does not terminate the stream")
  func unknownBeforeValid() async throws {
    let result = await events(frames: [
      try snapshot(setting: "future-setting", enabled: "future-payload"),
      try snapshot(enabled: false),
    ])

    #expect(
      result == [
        .snapshot(SimulatorSettingsSnapshot(reduceMotionEnabled: false)),
        .sourceEnded,
      ])
  }

  @Test("Repeated unknown settings remain non-terminal")
  func repeatedUnknownSettings() async throws {
    let result = await events(frames: [
      try snapshot(setting: "future-setting", enabled: 1),
      try snapshot(setting: "another-setting", enabled: ["value": true]),
      try snapshot(setting: "future-setting", enabled: NSNull()),
      try snapshot(enabled: true),
    ])

    #expect(
      result == [
        .snapshot(SimulatorSettingsSnapshot(reduceMotionEnabled: true)),
        .sourceEnded,
      ])
  }

  @Test("A malformed known setting is a typed terminal failure")
  func malformedKnownSetting() async throws {
    let result = await events(frames: [try snapshot(setting: "reduce-motion", enabled: "not-a-boolean")])
    guard case let .unavailable(.failed(reason)) = result.first else {
      Issue.record("expected a typed failed availability")
      return
    }
    #expect(reason.contains("not a Reduce Motion snapshot"))
    #expect(result.count == 1)
  }

  @Test("Unsupported and old guest responses are typed as unavailable")
  func unsupported() async throws {
    for kind in ["capability_unavailable", "bad_request"] {
      let result = await events(frames: [try failure(kind: kind, message: "no settings source")])
      #expect(result == [.unavailable(.unsupported(reason: "no settings source"))])
    }
  }

  @Test("Known guest readiness failures are typed as not ready")
  func guestNotReady() async throws {
    for kind in ["application_unavailable", "application_not_responding", "frontmost_unresolved"] {
      let result = await events(frames: [try failure(kind: kind, message: "guest is not ready")])
      #expect(result == [.unavailable(.notReady(reason: "guest is not ready"))])
    }
  }

  @Test("Unknown, missing, and malformed guest error kinds fail safely")
  func unknownErrorKinds() async throws {
    let kinds: [Any?] = ["future_error_kind", nil, 42]
    for kind in kinds {
      let result = await events(frames: [try failure(kind: kind, message: "guest failed")])
      #expect(result == [.unavailable(.failed(reason: "guest failed"))])
    }
  }

  @Test("A transient source startup failure is typed as not ready")
  func notReady() async {
    let publisher = SimulatorSettingsPublisher {
      throw SettingsSourceFailure.notReady
    }
    #expect(await collect(publisher.events()) == [.unavailable(.notReady(reason: "settings source is not ready"))])
  }

  @Test("Consumer cancellation emits no terminal event")
  func cancellation() async {
    let publisher = SimulatorSettingsPublisher {
      AsyncThrowingStream { _ in }
    }
    let consumer = Task { await collect(publisher.events()) }
    consumer.cancel()
    #expect(await consumer.value.isEmpty)
  }

  @Test("Malformed source output is a typed failure")
  func malformed() async {
    let result = await events(frames: [Data("[]".utf8)])
    guard case let .unavailable(.failed(reason)) = result.first else {
      Issue.record("expected a typed failed availability")
      return
    }
    #expect(reason.contains("not a JSON object"))
    #expect(result.count == 1)
  }

  private func events(frames: [Data]) async -> [SimulatorSettingsEvent] {
    let publisher = SimulatorSettingsPublisher {
      AsyncThrowingStream { continuation in
        for frame in frames {
          continuation.yield(frame)
        }
        continuation.finish()
      }
    }
    return await collect(publisher.events())
  }

  private func collect(_ stream: AsyncStream<SimulatorSettingsEvent>) async -> [SimulatorSettingsEvent] {
    var events: [SimulatorSettingsEvent] = []
    for await event in stream {
      events.append(event)
    }
    return events
  }

  private func snapshot(setting: String = "reduce-motion", enabled: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "ok": true,
      "event": "snapshot",
      "setting": setting,
      "enabled": enabled,
    ])
  }

  private func failure(kind: Any?, message: String) throws -> Data {
    var response: [String: Any] = ["ok": false, "error": message]
    if let kind {
      response["error_kind"] = kind
    }
    return try JSONSerialization.data(withJSONObject: response)
  }
}

private enum SettingsSourceFailure: LocalizedError, SimulatorFailureClassifying {
  case notReady

  var errorDescription: String? { "settings source is not ready" }
  var failureKind: SimulatorFailureKind { .notReady }
}
