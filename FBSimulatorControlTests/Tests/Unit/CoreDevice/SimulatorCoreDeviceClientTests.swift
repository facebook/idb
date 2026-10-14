/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing
@preconcurrency import XPC

/// A simulator whose CoreDevice services are synthetic peers answering with `reply`.
// SAFETY: `reply` and `versionReads` are written by the test between awaited requests, and read by the
// peers and the version source while one is in flight.
// patternlint-disable-next-line unchecked-sendable
private final class Recorder: @unchecked Sendable {
  let services = SyntheticXPCServices()
  var versionReads = 0
  var reply = SimulatorCoreDevice.dictionary([
    "CoreDevice.output": SimulatorCoreDevice.dictionary(["answer": xpc_int64_create(42)])
  ])

  lazy var client = SimulatorCoreDeviceClient(
    deviceID: "0000-DEVICE",
    connector: services.connector,
    version: {
      self.versionReads += 1
      return try CoreDeviceVersion("651.13.4")
    })

  @discardableResult
  func register(_ service: String) -> SyntheticXPCPeer {
    services.register(service) { [weak self] request in
      guard let self else { return }
      request.reply(self.reply)
    }
  }
}

@Suite
struct SimulatorCoreDeviceClientTests {

  private struct Answer: Decodable, Equatable {
    let answer: Int64
  }

  @Test
  func performWrapsTheInputInTheActionEnvelopeForTheDevice() async throws {
    let recorder = Recorder()
    let peer = recorder.register("com.example.service")
    struct Input: Encodable {
      let flag = true
    }
    let answer = try await recorder.client.perform(
      action: "com.example.action", service: "com.example.service", input: Input(), as: Answer.self)
    #expect(answer == Answer(answer: 42))

    #expect(recorder.services.lookups == ["com.example.service"])
    let request = try #require(peer.received.first)
    #expect(String(cString: xpc_dictionary_get_string(request, "CoreDevice.actionIdentifier")!) == "com.example.action")
    #expect(String(cString: xpc_dictionary_get_string(request, "CoreDevice.deviceIdentifier")!) == "0000-DEVICE")
    let version = try #require(xpc_dictionary_get_dictionary(request, "CoreDevice.coreDeviceVersion"))
    #expect(String(cString: xpc_dictionary_get_string(version, "stringValue")!) == "651.13.4")
    let input = try #require(xpc_dictionary_get_dictionary(request, "CoreDevice.input"))
    #expect(xpc_dictionary_get_bool(input, "flag"))
  }

  @Test
  func theVersionIsReadOnceAcrossRequests() async throws {
    let recorder = Recorder()
    let peer = recorder.register("com.example.service")
    for _ in 0..<3 {
      _ = try await recorder.client.perform(
        action: "com.example.action", service: "com.example.service", input: CoreDeviceEmptyInput(), as: Answer.self)
    }
    #expect(recorder.versionReads == 1)
    #expect(peer.connections == 3)
  }

  @Test
  func aVersionFailureIsNotCached() async {
    // SAFETY: Read after the awaited requests complete.
    // patternlint-disable-next-line unchecked-sendable
    final class Attempts: @unchecked Sendable {
      var count = 0
    }
    let attempts = Attempts()
    let services = SyntheticXPCServices()
    services.register("s", respond: SyntheticXPCPeer.silent)
    let client = SimulatorCoreDeviceClient(
      deviceID: "0000-DEVICE",
      connector: services.connector,
      version: {
        attempts.count += 1
        throw SimulatorCoreDeviceError.unsupported("CoreDevice version metadata")
      })
    for _ in 0..<2 {
      do {
        _ = try await client.perform(action: "a", service: "s", input: CoreDeviceEmptyInput(), as: Answer.self)
        Issue.record("Expected the version failure")
      } catch {
        guard case SimulatorCoreDeviceError.unsupported = error else {
          Issue.record("\(error)")
          return
        }
      }
    }
    #expect(attempts.count == 2)
    #expect(services.lookups == [], "No connection should be made without a version")
  }

  @Test
  func performSurfacesAProviderErrorAndAMalformedOutput() async {
    let recorder = Recorder()
    recorder.register("s")
    recorder.reply = SimulatorCoreDevice.dictionary([
      "CoreDevice.error": SimulatorCoreDevice.dictionary(["domain": xpc_string_create("com.example"), "code": xpc_int64_create(3)])
    ])
    do {
      _ = try await recorder.client.perform(action: "a", service: "s", input: CoreDeviceEmptyInput(), as: Answer.self)
      Issue.record("Expected the provider error")
    } catch {
      guard case let SimulatorCoreDeviceError.unavailable(detail) = error else {
        Issue.record("\(error)")
        return
      }
      #expect(detail == "com.example (3)")
    }

    recorder.reply = SimulatorCoreDevice.dictionary([
      "CoreDevice.output": SimulatorCoreDevice.dictionary(["answer": xpc_string_create("42")])
    ])
    do {
      _ = try await recorder.client.perform(action: "a", service: "s", input: CoreDeviceEmptyInput(), as: Answer.self)
      Issue.record("Expected the malformed output")
    } catch {
      guard case let SimulatorCoreDeviceError.malformed(detail) = error else {
        Issue.record("\(error)")
        return
      }
      #expect(detail.hasPrefix("CoreDevice.output.answer:"), "\(detail)")
    }
  }

  // MARK: - Motion capabilities

  private static let advertised = SimulatorCoreDevice.dictionary([
    "CoreDevice.output": SimulatorCoreDevice.dictionary(["hingeAngle": xpc_bool_create(true), "deviceMotionState": xpc_bool_create(true)])
  ])

  @Test
  func anAnsweredCapabilityQueryIsKeptForTheSimulator() async throws {
    let recorder = Recorder()
    let peer = recorder.register(MotionCapabilities.service)
    recorder.reply = Self.advertised
    for _ in 0..<3 {
      let capabilities = try await recorder.client.motionCapabilities()
      #expect(capabilities == MotionCapabilities(hingeAngle: true, deviceMotionState: true))
    }
    #expect(peer.connections == 1)
    let request = try #require(peer.received.first)
    #expect(String(cString: xpc_dictionary_get_string(request, "CoreDevice.actionIdentifier")!) == MotionCapabilities.action)
  }

  @Test
  func anUnansweredCapabilityQueryIsAskedAgain() async {
    let recorder = Recorder()
    let peer = recorder.register(MotionCapabilities.service)
    recorder.reply = SimulatorCoreDevice.dictionary([
      "CoreDevice.error": SimulatorCoreDevice.dictionary(["domain": xpc_string_create("com.example"), "code": xpc_int64_create(1)])
    ])
    for _ in 0..<2 {
      do {
        _ = try await recorder.client.motionCapabilities()
        Issue.record("Expected the provider error")
      } catch {
        guard case SimulatorCoreDeviceError.unavailable = error else {
          Issue.record("\(error)")
          return
        }
      }
    }
    #expect(peer.connections == 2)

    recorder.reply = Self.advertised
    _ = try? await recorder.client.motionCapabilities()
    _ = try? await recorder.client.motionCapabilities()
    #expect(peer.connections == 3)
  }

  @Test
  func sendPassesAPlainMessageThroughUnchanged() async throws {
    let recorder = Recorder()
    let peer = recorder.register("com.example.plain")
    recorder.reply = SimulatorCoreDevice.dictionary(["currentDeviceOrientation": xpc_string_create("portrait")])
    let message = SimulatorCoreDevice.dictionary(["messageType": xpc_string_create("OrientationRequest")])
    let orientation = try await recorder.client.send(service: "com.example.plain", message: message) { reply in
      String(cString: xpc_dictionary_get_string(reply, "currentDeviceOrientation")!)
    }
    #expect(orientation == "portrait")
    #expect(recorder.services.lookups == ["com.example.plain"])
    let received = try #require(peer.received.first)
    #expect(xpc_equal(received, message))
    #expect(recorder.versionReads == 0)
  }
}
