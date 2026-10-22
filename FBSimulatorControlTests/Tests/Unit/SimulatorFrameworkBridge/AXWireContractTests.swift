/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
import Foundation
import Testing

/// Byte-level pins for the host side of the axbridge wire contract: the `XC_kAXXC*` node-attribute
/// keys the read path fetches and the frontmost-method request selectors. These strings cross the guest↔host boundary with no shared header, so a rename here is a
/// silent protocol break; pinning them exactly keeps `AXWire` byte-identical to the wire. The
/// guest-side agreement is pinned against these same literals in the `SimulatorFrameworkBridge` tests.
@Suite
struct AXWireContractTests {

  // MARK: - Node-attribute keys (the `_XCTD_fetchAttributes:` request/echo keys)

  @Test
  func nodeAttributeWireKeys() {
    #expect(AXWire.Node.explainedBy.rawValue == "FBExplainedBy")
    #expect(AXWire.Node.isEnabled.rawValue == "FBIsEnabled")
    #expect(AXWire.Node.translatorRole.rawValue == "FBTranslatorRole")
    #expect(AXWire.Node.translatorSubrole.rawValue == "FBTranslatorSubrole")
    #expect(AXWire.Node.traits.rawValue == "FBTraits")
    #expect(AXWire.Node.elementIdentity.rawValue == "FBElementIdentity")
    #expect(AXWire.Node.elementType.rawValue == "XC_kAXXCAttributeElementType")
    #expect(AXWire.Node.elementBaseType.rawValue == "XC_kAXXCAttributeElementBaseType")
    #expect(AXWire.Node.label.rawValue == "XC_kAXXCAttributeLabel")
    #expect(AXWire.Node.value.rawValue == "XC_kAXXCAttributeValue")
    #expect(AXWire.Node.identifier.rawValue == "XC_kAXXCAttributeIdentifier")
    #expect(AXWire.Node.frame.rawValue == "XC_kAXXCAttributeFrame")
    #expect(AXWire.Node.automationType.rawValue == "XC_kAXXCAttributeAutomationType")
    #expect(AXWire.Node.xcTraits.rawValue == "XC_kAXXCAttributeTraits")
    #expect(AXWire.Node.children.rawValue == "XC_kAXXCAttributeChildren")
  }

  // A read that names no attributes gets exactly this ordered set — the guest fetches and echoes back
  // these keys, so both the membership and the order are part of the contract. A read that *does* name
  // attributes gets those instead; this is the fallback both sides must agree on for a default read to
  // stay byte-identical.
  @Test
  func defaultFetchListIsTheOrderedReadAttributeSet() {
    #expect(
      AXWire.Node.defaultFetchList == [
        "XC_kAXXCAttributeElementType",
        "XC_kAXXCAttributeElementBaseType",
        "XC_kAXXCAttributeLabel",
        "XC_kAXXCAttributeValue",
        "XC_kAXXCAttributeIdentifier",
        "XC_kAXXCAttributeFrame",
        "XC_kAXXCAttributeAutomationType",
        "XC_kAXXCAttributeTraits",
        "XC_kAXXCAttributeChildren",
      ]
    )
  }

  // MARK: - Failure kinds

  // `error_kind` is how the host decides what a failure *was* without matching on the guest's free-text
  // message, so each spelling is as much a part of the contract as a node key. Pinned over `allCases`, so
  // a kind added host-side without a guest that emits it fails here rather than silently never matching.
  @Test
  func failureKindWireValues() {
    let expected: [AXWire.ErrorKind: String] = [
      .applicationUnavailable: "application_unavailable",
      .applicationNotResponding: "application_not_responding",
      .frontmostUnresolved: "frontmost_unresolved",
      .readerUnavailable: "reader_unavailable",
      .badRequest: "bad_request",
      .assertionFailed: "assertion_failed",
      .runtimeFailed: "runtime_failed",
      .capabilityUnavailable: "capability_unavailable",
    ]
    #expect(Set(AXWire.ErrorKind.allCases) == Set(expected.keys), "every failure kind must have its wire value pinned")
    for (kind, wireValue) in expected {
      #expect(kind.rawValue == wireValue)
      #expect(AXWire.ErrorKind(rawValue: wireValue) == kind, "\(kind) must round-trip through its wire value")
    }
  }

  @Test
  func writeEffectWireValues() {
    let expected: [AXWire.Effect: String] = [.none: "none", .unknown: "unknown"]
    #expect(Set(AXWire.Effect.allCases) == Set(expected.keys), "every effect must have a pinned wire value")
    for (effect, wireValue) in expected {
      #expect(effect.rawValue == wireValue)
    }
  }

  // A kind this host has never heard of has to parse as "no kind" — an opaque reader failure — rather
  // than as anything the host would act on. A newer guest can then emit kinds an older host does not
  // know, degrading precision instead of breaking parsing.
  @Test
  func anUnknownFailureKindIsNotAKnownOne() {
    #expect(AXWire.ErrorKind(rawValue: "some_future_kind") == nil)
  }

  // MARK: - Verbs and actions

  // The verb is the first thing the guest reads off a request, and it is spelled the same as the
  // one-shot CLI subcommand — so a rename here breaks both transports at once. Pinned over `allCases`
  // so a verb added host-side without a guest that answers it fails here.
  @Test
  func verbWireValues() {
    let expected: [AXWire.Verb: String] = [
      .displays: "displays",
      .describe: "describe",
      .hitTest: "hittest",
      .perform: "perform",
      .setValue: "setvalue",
      .settingsGet: "settings-get",
      .settingsSet: "settings-set",
      .settingsObserve: "settings-observe",
      .quiet: "quiet",
    ]
    #expect(Set(AXWire.Verb.allCases) == Set(expected.keys), "every verb must have its wire value pinned")
    for (verb, wireValue) in expected {
      #expect(verb.rawValue == wireValue)
    }
  }

  // The action names a `perform` sends. The guest maps each back to a numeric AX identifier, so an
  // unrecognised spelling is refused outright rather than quietly becoming a press.
  @Test
  func actionWireValues() {
    let expected: [AXWire.Action: String] = [
      .press: "press",
      .scrollUp: "scroll-up",
      .scrollDown: "scroll-down",
      .scrollLeft: "scroll-left",
      .scrollRight: "scroll-right",
      .scrollToVisible: "scroll-to-visible",
    ]
    #expect(Set(AXWire.Action.allCases) == Set(expected.keys), "every action must have its wire value pinned")
    for (action, wireValue) in expected {
      #expect(action.rawValue == wireValue)
    }
  }

  @Test
  func settingsStreamWireValues() {
    #expect(AXWire.Settings.Key.allCases.map(\.rawValue) == ["event", "settings"])
    #expect(AXWire.Settings.Event.allCases.map(\.rawValue) == ["snapshot"])
  }

  // What a `quiet` stream writes. The host decodes each event as it arrives, so an event, state or signal
  // it does not recognise would end the stream it is consuming.
  @Test
  func quiescenceStreamWireValues() {
    #expect(AXWire.Quiescence.Key.allCases.map(\.rawValue) == ["event", "state", "signals"])
    #expect(AXWire.Quiescence.Event.allCases.map(\.rawValue) == ["state", "touches_completed", "target_changed", "target_exited"])
    #expect(AXWire.Quiescence.State.allCases.map(\.rawValue) == ["busy", "settling", "quiet"])
    #expect(AXWire.Quiescence.Signal.allCases.map(\.rawValue) == ["run_loop_idle", "animations_inactive"])
  }

  // MARK: - Request fields

  // The fields a request carries, in both spellings the guest accepts. Pinned over `allCases` and in one
  // table, so the JSON key and the argv flag for a field cannot drift apart — the two transports send the
  // same request, and a field that means one thing over the socket and another over argv is a request
  // whose behaviour depends on which transport the caller happens to hold.
  @Test
  func requestFieldWireSpellings() {
    let expected: [AXWire.Request: (key: String, flag: String?)] = [
      .verb: ("verb", nil),
      .pid: ("pid", "--pid"),
      .displayID: ("displayID", "--display-id"),
      .maxDepth: ("maxDepth", "--max-depth"),
      .maxNodes: ("maxNodes", "--max-nodes"),
      .automationMode: ("automationMode", "--automation-mode"),
      .attributes: ("attributes", "--attributes"),
      .traversal: ("traversal", "--traversal"),
      .clientType: ("clientType", "--client-type"),
      .explainUnreachable: ("explainUnreachable", "--explain-unreachable"),
      .x: ("x", "--x"),
      .y: ("y", "--y"),
      .method: ("method", "--method"),
      .action: ("action", "--action"),
      .value: ("value", "--value"),
      .setting: ("setting", "--setting"),
      .enabled: ("enabled", "--enabled"),
      .assertKey: ("assertKey", "--assert-key"),
      .assertValue: ("assertValue", "--assert-value"),
      .busyThresholdMs: ("busyThresholdMs", "--busy-threshold-ms"),
      .quietWindowMs: ("quietWindowMs", "--quiet-window-ms"),
    ]
    #expect(Set(AXWire.Request.allCases) == Set(expected.keys), "every request field must have its spellings pinned")
    for (field, spelling) in expected {
      #expect(field.key == spelling.key, "\(field) JSON key")
      #expect(field.flag == spelling.flag, "\(field) argv flag")
    }
  }

  // The verb is the CLI's subcommand rather than an option, so it contributes no argv pair at all — the
  // guest reads argv strictly two at a time, and a lone flag would shift every field after it.
  @Test
  func theVerbContributesNoArgvPair() {
    #expect(AXWire.Request.verb.argument("describe") == [])
    #expect(AXWire.Request.maxNodes.argument("5000") == ["--max-nodes", "5000"])
  }

  // MARK: - Write requests

  @Test
  func aWriteRendersTheSameFieldsForBothTransports() throws {
    let request = AXBridgeWriteRequest(
      kind: .perform(.press),
      x: 201,
      y: 406,
      pid: 4321,
      assertion: AXBridgeWriteAssertion(key: .label, value: "General")
    )
    let transportRequest = AXBridgeRequest.write(request)
    #expect(
      try wireAction(transportRequest)
        == #"{"write":{"request":{"assertion":{"key":"XC_kAXXCAttributeLabel","value":"General"},"kind":{"perform":{"action":"press"}},"pid":4321,"x":201,"y":406}}}"#
    )
  }

  @Test
  func displayRoutingIsIdenticalForBothTransports() throws {
    let options = AXBridgeReadRequest(
      maxDepth: 10, maxNodes: 100, attributes: nil, explainUnreachable: false,
      traversal: .viewHierarchy, automationMode: nil, clientType: .noClient)
    let requests: [AXBridgeRequest] = [
      .read(pid: 42, options: options, displayID: 82),
      .hitTest(x: 10, y: 20, attributes: nil, clientType: .noClient, displayID: 82),
      .readFrontmost(x: 10, y: 20, method: .windowServer, options: options, displayID: 82),
      .write(AXBridgeWriteRequest(kind: .perform(.press), x: 10, y: 20, pid: nil, assertion: nil, displayID: 82)),
    ]
    for request in requests {
      #expect(request.displayID == 82)
      #expect(try wireAction(request).contains(#""displayID":82"#))
    }
  }

  @Test
  func aSetValueRendersItsValueRatherThanAnAction() throws {
    let request = AXBridgeWriteRequest(kind: .setValue("hello"), x: 1, y: 2, pid: nil, assertion: nil)
    #expect(request.verb == .setValue)
    let transportRequest = AXBridgeRequest.write(request)
    #expect(try wireAction(transportRequest) == #"{"write":{"request":{"kind":{"setValue":{"value":"hello"}},"x":1,"y":2}}}"#)
  }

  @Test
  func absentOptionsAreOmittedRatherThanSentEmpty() throws {
    let request = AXBridgeWriteRequest(kind: .perform(.scrollDown), x: 10, y: 20, pid: nil, assertion: nil)
    let transportRequest = AXBridgeRequest.write(request)
    #expect(try wireAction(transportRequest) == #"{"write":{"request":{"kind":{"perform":{"action":"scroll-down"}},"x":10,"y":20}}}"#)
    #expect(try transportRequest.arguments.count == 2, "rpc takes one encoded request")
    #expect(!transportRequest.mayRetry, "writes must not be resent after a dropped response")
  }

  @Test
  func deviceSettingRequestsRenderTheSameFieldsForBothTransports() throws {
    let read = AXBridgeRequest.deviceSettingRead("button-shapes")
    #expect(try wireAction(read) == #"{"deviceSettingRead":{"setting":"button-shapes"}}"#)
    #expect(read.mayRetry)

    let write = AXBridgeRequest.deviceSettingWrite("reduce-motion", enabled: true)
    #expect(try wireAction(write) == #"{"deviceSettingWrite":{"enabled":true,"setting":"reduce-motion"}}"#)
    #expect(!write.mayRetry)
  }

  @Test
  func deviceSettingResponsePreservesTypedGuestFailures() throws {
    let success = Data(#"{"setting":{"response":{"enabled":true}}}"#.utf8)
    #expect(try AXDeviceSettingResponse(answer: AXBridgeReply(answer: success, for: .deviceSettingRead("button-shapes")).answer).enabled)

    let failure = Data(#"{"failure":{"reason":{"error":"Button Shapes is unavailable","error_kind":"reader_unavailable"}}}"#.utf8)
    let error = try #require(#expect(throws: (any Error).self) { try AXDeviceSettingResponse(answer: AXBridgeReply(answer: failure, for: .deviceSettingRead("button-shapes")).answer) })
    guard let bridgeError = error as? AXBridgeError,
      case let .readerUnavailable(message) = bridgeError
    else {
      Issue.record("Expected readerUnavailable, got \(error)")
      return
    }
    #expect(message == "Button Shapes is unavailable")
  }

  // MARK: - Frontmost-method request selectors

  // `AXBridgeFrontmostMethod`'s raw values are the selectors the host sends the guest to pick a
  // frontmost-resolution strategy; each must round-trip through its raw value, and the guest-reported
  // `method` decodes back into these same cases.
  @Test
  func frontmostMethodRequestSelectors() {
    let expected: [AXBridgeFrontmostMethod: String] = [
      .centerPoint: "center-point",
      .windowServer: "window-server",
      .runningBoard: "runningboard",
    ]
    #expect(
      Set(AXBridgeFrontmostMethod.allCases) == Set(expected.keys),
      "every frontmost method must have its selector pinned"
    )
    for (method, selector) in expected {
      #expect(method.rawValue == selector)
      #expect(AXBridgeFrontmostMethod(rawValue: selector) == method, "\(method) must round-trip through its selector")
    }
  }
}
