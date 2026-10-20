/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
@testable import FBSimulatorServices
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
    #expect(try requestJSON(request) == #"{"deviceSettingChanges":{"setting":"reduce-motion"}}"#)
    #expect(!request.mayRetry)
  }

  @Test("A combined snapshot preserves values and per-setting unavailability")
  func combinedSettings() throws {
    let frame = try JSONEncoder().encode(
      BridgeAXAnswer.settingSnapshot(
        BridgeAXSettingSnapshot(
          setting: "state-settings", enabled: false,
          otherSettings: [
            "button-shapes": .success(BridgeAXSettingResponse(enabled: true)),
            "reduce-transparency": .failure(BridgeAXFailure(message: "missing getter", kind: .capabilityUnavailable)),
            "increase-contrast": .success(BridgeAXSettingResponse(enabled: false)),
          ])))
    let event = try SimulatorSettingsPublisher.event(from: answer(frame))
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
    let frame = try JSONEncoder().encode(BridgeAXAnswer.settingSnapshot(BridgeAXSettingSnapshot(setting: "state-settings", enabled: false)))
    #expect(throws: (any Error).self) { try SimulatorSettingsPublisher.event(from: answer(frame)) }
  }

  @Test("Duplicate guest values are suppressed and clean source completion is explicit")
  func deduplicates() async throws {
    let (frames, continuation) = AsyncThrowingStream<BridgeAXAnswer, Error>.makeStream()
    let publisher = SimulatorSettingsPublisher { frames }
    var iterator = publisher.events().makeAsyncIterator()

    continuation.yield(try answer(snapshot(enabled: false)))
    let first = await iterator.next()
    #expect(first == .snapshot(SimulatorSettingsSnapshot(reduceMotionEnabled: false)))

    continuation.yield(try answer(snapshot(enabled: false)))
    continuation.yield(try answer(snapshot(enabled: true)))
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
      try snapshot(setting: "future-setting", enabled: nil),
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
      try snapshot(setting: "future-setting", enabled: true),
      try snapshot(setting: "another-setting", enabled: nil),
      try snapshot(setting: "future-setting", enabled: nil),
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
    let result = await events(frames: [try snapshot(setting: "reduce-motion", enabled: nil)])
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

  @Test("A failure without a kind fails safely")
  func missingErrorKind() async throws {
    let result = await events(frames: [try failure(kind: nil, message: "guest failed")])
    #expect(result == [.unavailable(.failed(reason: "guest failed"))])
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
    #expect(reason.contains("unparseable guest response"))
    #expect(result.count == 1)
  }

  /// A settings frame as the transport hands it on: decoded as the answer to a settings stream.
  private func answer(_ frame: Data) throws -> BridgeAXAnswer {
    try AXBridgeReply(answer: frame, for: .deviceSettingChanges("state-settings")).answer
  }

  private func events(frames: [Data]) async -> [SimulatorSettingsEvent] {
    let publisher = SimulatorSettingsPublisher {
      AsyncThrowingStream { continuation in
        for frame in frames {
          do {
            continuation.yield(try answer(frame))
          } catch {
            continuation.finish(throwing: error)
            return
          }
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

  private func snapshot(setting: String = "reduce-motion", enabled: Bool?) throws -> Data {
    try JSONEncoder().encode(BridgeAXAnswer.settingSnapshot(BridgeAXSettingSnapshot(setting: setting, enabled: enabled)))
  }

  private func failure(kind: String?, message: String) throws -> Data {
    try JSONEncoder().encode(BridgeAXAnswer.failure(BridgeAXFailure(message: message, kind: kind.flatMap(BridgeAXWire.ErrorKind.init(rawValue:)))))
  }
}

private enum SettingsSourceFailure: LocalizedError, SimulatorFailureClassifying {
  case notReady

  var errorDescription: String? { "settings source is not ready" }
  var failureKind: SimulatorFailureKind { .notReady }
}

/// The request as JSON text with sorted keys, as a frame carries it.
private func requestJSON(_ request: AXBridgeRequest) throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  return String(decoding: try encoder.encode(request), as: UTF8.self)
}
