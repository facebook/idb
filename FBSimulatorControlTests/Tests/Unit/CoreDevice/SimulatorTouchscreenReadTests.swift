/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing
import XPC

private func touchscreenValue(id: String = "display-a", serviceID: UInt64 = 0x127) -> xpc_object_t {
  SimulatorCoreDevice.dictionary([
    "displayUUID": xpc_string_create(id), "_ServiceID": xpc_uint64_create(serviceID),
    "PrimaryUsagePage": xpc_uint64_create(0x0D), "PrimaryUsage": xpc_uint64_create(0x04),
  ])
}

private func touchscreenReply(_ services: [xpc_object_t]) -> xpc_object_t {
  SimulatorCoreDevice.dictionary(["connectedServices": SimulatorCoreDevice.array(services)])
}

@Suite
struct SimulatorTouchscreenReadTests {
  @Test
  func requestUsesUniversalHIDEnvelope() throws {
    let request = try SimulatorTouchscreenProtocol.request()
    #expect(xpc_dictionary_get_count(request) == 2)
    let isBarrier = try #require(xpc_dictionary_get_value(request, "isBarrier"))
    #expect(xpc_get_type(isBarrier) == XPC_TYPE_BOOL)
    #expect(!xpc_dictionary_get_bool(request, "isBarrier"))
    let payload = try #require(xpc_dictionary_get_value(request, "payload"))
    #expect(xpc_get_type(payload) == XPC_TYPE_DICTIONARY)
    #expect(xpc_dictionary_get_count(payload) == 1)
    let connectedServices = try #require(xpc_dictionary_get_value(payload, "connectedServices"))
    #expect(xpc_get_type(connectedServices) == XPC_TYPE_DICTIONARY)
    #expect(xpc_dictionary_get_count(connectedServices) == 0)
  }

  @Test
  func runtimeIdentityMapsArbitraryTouchscreenTargets() throws {
    let services = [touchscreenValue(id: "display-z", serviceID: 0x1FF), touchscreenValue()]
    #expect(
      try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply(services)) == [
        SimulatorTouchscreen(displayUniqueID: "display-a", digitizerTarget: 39),
        SimulatorTouchscreen(displayUniqueID: "display-z", digitizerTarget: 255),
      ])
  }

  @Test
  func otherHIDServicesDoNotNeedDisplayIdentity() throws {
    let keyboard = SimulatorCoreDevice.dictionary([
      "_ServiceID": xpc_uint64_create(0x200),
      "PrimaryUsagePage": xpc_uint64_create(0), "PrimaryUsage": xpc_uint64_create(0),
    ])
    let trackpad = SimulatorCoreDevice.dictionary([
      "_ServiceID": xpc_uint64_create(0x501),
      "PrimaryUsagePage": xpc_uint64_create(1), "PrimaryUsage": xpc_uint64_create(2),
    ])
    #expect(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([keyboard, trackpad])) == [])
    #expect(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([])) == [])
  }

  @Test
  func legacyProviderWithoutIdentitiesReportsUnsupportedCapability() throws {
    let legacy = touchscreenValue()
    xpc_dictionary_set_value(legacy, "displayUUID", nil)
    let unidentified = try #require(#expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([legacy])) })
    if case SimulatorCoreDeviceError.unsupported = unidentified {
    } else {
      Issue.record("Expected unsupported identities: \(unidentified)")
    }
    let allUnidentified = try #require(#expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([legacy, legacy])) })
    if case SimulatorCoreDeviceError.unsupported = allUnidentified {
    } else {
      Issue.record("Expected unsupported identities: \(allUnidentified)")
    }
    let identified = touchscreenValue(id: "display-b", serviceID: 0x128)
    let partlyIdentified = try #require(#expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([legacy, identified])) })
    if case SimulatorCoreDeviceError.malformed = partlyIdentified {
    } else {
      Issue.record("Expected malformed: \(partlyIdentified)")
    }
    xpc_dictionary_set_int64(legacy, "_ServiceID", 0x127)
    let signedServiceID = try #require(#expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([legacy])) })
    guard case SimulatorCoreDeviceError.malformed = signedServiceID else {
      Issue.record("Expected malformed: \(signedServiceID)")
      return
    }
  }

  @Test
  func ambiguousIdentityOrTargetIsRejected() {
    for duplicate in [touchscreenValue(serviceID: 0x128), touchscreenValue(id: "display-b")] {
      #expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([touchscreenValue(), duplicate])) }
    }
  }

  @Test
  func invalidServiceNamespaceAndMainAliasAreRejected() {
    for serviceID: UInt64 in [0, 0xFF, 0x100, 0x200, 0x100000127, .max] {
      #expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([touchscreenValue(serviceID: serviceID)])) }
    }
  }

  @Test
  func malformedIdentityAndUnsignedFieldsAreRejected() {
    for id in ["", String(repeating: "x", count: 1025)] {
      #expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([touchscreenValue(id: id)])) }
    }
    for key in ["displayUUID", "_ServiceID"] {
      let service = touchscreenValue()
      xpc_dictionary_set_value(service, key, nil)
      #expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service])) }
      xpc_dictionary_set_int64(service, key, 0x127)
      #expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service])) }
    }
  }

  @Test
  func servicesWithoutRecognizedTouchscreenUsageAreIgnored() throws {
    for key in ["PrimaryUsagePage", "PrimaryUsage"] {
      for value: xpc_object_t? in [nil, xpc_int64_create(4), xpc_string_create("4"), xpc_null_create()] {
        let service = touchscreenValue()
        xpc_dictionary_set_value(service, key, value)
        #expect(try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service])) == [])
        #expect(
          try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service, touchscreenValue()])) == [SimulatorTouchscreen(displayUniqueID: "display-a", digitizerTarget: 39)])
      }
    }
  }

  @Test
  func invalidUTF8IdentityIsRejected() {
    let service = touchscreenValue()
    let invalidUTF8: [CChar] = [-1, 0]
    let identity = invalidUTF8.withUnsafeBufferPointer { xpc_string_create($0.baseAddress!) }
    xpc_dictionary_set_value(service, "displayUUID", identity)
    #expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(touchscreenReply([service])) }
  }

  @Test
  func missingMalformedAndOversizedRepliesFail() {
    let invalid = [
      XPC_ERROR_CONNECTION_INVALID, SimulatorCoreDevice.dictionary([:]),
      SimulatorCoreDevice.dictionary(["connectedServices": xpc_bool_create(false)]),
      touchscreenReply([xpc_null_create()]),
      touchscreenReply((0..<257).map { touchscreenValue(id: "display-\($0)") }),
    ]
    for reply in invalid {
      #expect(throws: (any Error).self) { try SimulatorTouchscreenProtocol.touchscreens(reply) }
    }
  }
}
