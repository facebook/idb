/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import XCTest

/// Byte-level pins for the host side of the axbridge wire contract: the `XC_kAXXC*` node-attribute
/// keys the read path fetches, the output-schema keys (`FBAXKeys`), and the frontmost-method request
/// selectors. These strings cross the guest↔host boundary with no shared header, so a rename here is a
/// silent protocol break; pinning them exactly keeps `FBAXWire` byte-identical to the wire. The
/// guest-side agreement is pinned against these same literals in the `SimulatorFrameworkBridge` tests.
final class FBAXWireContractTests: XCTestCase {

  // MARK: - Node-attribute keys (the `_XCTD_fetchAttributes:` request/echo keys)

  func testNodeAttributeWireKeys() {
    XCTAssertEqual(FBAXWire.Node.explainedBy.rawValue, "FBExplainedBy")
    XCTAssertEqual(FBAXWire.Node.isEnabled.rawValue, "FBIsEnabled")
    XCTAssertEqual(FBAXWire.Node.translatorRole.rawValue, "FBTranslatorRole")
    XCTAssertEqual(FBAXWire.Node.translatorSubrole.rawValue, "FBTranslatorSubrole")
    XCTAssertEqual(FBAXWire.Node.traits.rawValue, "FBTraits")
    XCTAssertEqual(FBAXWire.Node.elementIdentity.rawValue, "FBElementIdentity")
    XCTAssertEqual(FBAXWire.Node.elementType.rawValue, "XC_kAXXCAttributeElementType")
    XCTAssertEqual(FBAXWire.Node.elementBaseType.rawValue, "XC_kAXXCAttributeElementBaseType")
    XCTAssertEqual(FBAXWire.Node.label.rawValue, "XC_kAXXCAttributeLabel")
    XCTAssertEqual(FBAXWire.Node.value.rawValue, "XC_kAXXCAttributeValue")
    XCTAssertEqual(FBAXWire.Node.identifier.rawValue, "XC_kAXXCAttributeIdentifier")
    XCTAssertEqual(FBAXWire.Node.frame.rawValue, "XC_kAXXCAttributeFrame")
    XCTAssertEqual(FBAXWire.Node.automationType.rawValue, "XC_kAXXCAttributeAutomationType")
    XCTAssertEqual(FBAXWire.Node.children.rawValue, "XC_kAXXCAttributeChildren")
  }

  // A read that names no attributes gets exactly this ordered set — the guest fetches and echoes back
  // these keys, so both the membership and the order are part of the contract. A read that *does* name
  // attributes gets those instead; this is the fallback both sides must agree on for a default read to
  // stay byte-identical.
  func testDefaultFetchListIsTheOrderedReadAttributeSet() {
    XCTAssertEqual(
      FBAXWire.Node.defaultFetchList,
      [
        "XC_kAXXCAttributeElementType",
        "XC_kAXXCAttributeElementBaseType",
        "XC_kAXXCAttributeLabel",
        "XC_kAXXCAttributeValue",
        "XC_kAXXCAttributeIdentifier",
        "XC_kAXXCAttributeFrame",
        "XC_kAXXCAttributeAutomationType",
        "XC_kAXXCAttributeChildren",
      ]
    )
  }

  // MARK: - Output-schema keys (`FBAXKeys` raw values are the emitted JSON keys)

  func testAXKeyWireValues() {
    let expected: [FBAXKeys: String] = [
      .label: "AXLabel",
      .frame: "AXFrame",
      .value: "AXValue",
      .uniqueID: "AXUniqueId",
      .type: "type",
      .title: "title",
      .frameDict: "frame",
      .help: "help",
      .enabled: "enabled",
      .customActions: "custom_actions",
      .role: "role",
      .roleDescription: "role_description",
      .subrole: "subrole",
      .contentRequired: "content_required",
      .pid: "pid",
      .traits: "traits",
      .expanded: "expanded",
      .placeholder: "placeholder",
      .hidden: "hidden",
      .focused: "focused",
      .isRemote: "is_remote",
      .interactable: "interactable",
      .occludedBy: "occluded_by",
    ]
    // Pinned over `allCases` rather than against a count, so a case added without a pinned wire value
    // fails here instead of silently going unchecked.
    XCTAssertEqual(Set(FBAXKeys.allCases), Set(expected.keys), "every FBAXKeys case must have its wire value pinned")
    for (key, wireValue) in expected {
      XCTAssertEqual(key.rawValue, wireValue, "\(key) must serialize under its pinned wire key")
    }
  }

  // The default set is the schema emitted when no keys are requested; it must stay exactly these 16, so
  // that adding a key never changes the bytes of a read that did not ask for it.
  func testDefaultKeySetMembership() {
    XCTAssertEqual(
      FBAXKeys.defaultSet,
      [
        .label, .frame, .value, .uniqueID, .type, .title, .frameDict, .help,
        .enabled, .customActions, .role, .roleDescription, .subrole,
        .contentRequired, .pid, .traits,
      ]
    )
    XCTAssertEqual(FBAXKeys.defaultSet.count, 16)
    // Every case that is not in the default set is opt-in, derived rather than listed, so a new key is
    // covered by this the moment it exists.
    let optIn = Set(FBAXKeys.allCases).subtracting(FBAXKeys.defaultSet)
    XCTAssertEqual(optIn, [.expanded, .placeholder, .hidden, .focused, .isRemote, .interactable, .occludedBy])
    XCTAssertTrue(FBAXKeys.defaultSet.isDisjoint(with: optIn), "the opt-in keys must stay out of the default set")
  }

  // MARK: - Failure kinds

  // `error_kind` is how the host decides what a failure *was* without matching on the guest's free-text
  // message, so each spelling is as much a part of the contract as a node key. Pinned over `allCases`, so
  // a kind added host-side without a guest that emits it fails here rather than silently never matching.
  func testFailureKindWireValues() {
    let expected: [FBAXWire.ErrorKind: String] = [
      .applicationUnavailable: "application_unavailable",
      .applicationNotResponding: "application_not_responding",
      .frontmostUnresolved: "frontmost_unresolved",
      .readerUnavailable: "reader_unavailable",
      .badRequest: "bad_request",
      .assertionFailed: "assertion_failed",
    ]
    XCTAssertEqual(Set(FBAXWire.ErrorKind.allCases), Set(expected.keys), "every failure kind must have its wire value pinned")
    for (kind, wireValue) in expected {
      XCTAssertEqual(kind.rawValue, wireValue)
      XCTAssertEqual(FBAXWire.ErrorKind(rawValue: wireValue), kind, "\(kind) must round-trip through its wire value")
    }
  }

  // A kind this host has never heard of has to parse as "no kind" — an opaque reader failure — rather
  // than as anything the host would act on. A newer guest can then emit kinds an older host does not
  // know, degrading precision instead of breaking parsing.
  func testAnUnknownFailureKindIsNotAKnownOne() {
    XCTAssertNil(FBAXWire.ErrorKind(rawValue: "some_future_kind"))
  }

  // MARK: - Verbs and actions

  // The verb is the first thing the guest reads off a request, and it is spelled the same as the
  // one-shot CLI subcommand — so a rename here breaks both transports at once. Pinned over `allCases`
  // so a verb added host-side without a guest that answers it fails here.
  func testVerbWireValues() {
    let expected: [FBAXWire.Verb: String] = [
      .describe: "describe",
      .hitTest: "hittest",
      .perform: "perform",
      .setValue: "setvalue",
      .shutdown: "shutdown",
    ]
    XCTAssertEqual(Set(FBAXWire.Verb.allCases), Set(expected.keys), "every verb must have its wire value pinned")
    for (verb, wireValue) in expected {
      XCTAssertEqual(verb.rawValue, wireValue)
    }
  }

  // The action names a `perform` sends. The guest maps each back to a numeric AX identifier, so an
  // unrecognised spelling is refused outright rather than quietly becoming a press.
  func testActionWireValues() {
    let expected: [FBAXWire.Action: String] = [
      .press: "press",
      .scrollUp: "scroll-up",
      .scrollDown: "scroll-down",
      .scrollLeft: "scroll-left",
      .scrollRight: "scroll-right",
      .scrollToVisible: "scroll-to-visible",
    ]
    XCTAssertEqual(Set(FBAXWire.Action.allCases), Set(expected.keys), "every action must have its wire value pinned")
    for (action, wireValue) in expected {
      XCTAssertEqual(action.rawValue, wireValue)
    }
  }

  // MARK: - Request fields

  // The fields a request carries, in both spellings the guest accepts. Pinned over `allCases` and in one
  // table, so the JSON key and the argv flag for a field cannot drift apart — the two transports send the
  // same request, and a field that means one thing over the socket and another over argv is a request
  // whose behaviour depends on which transport the caller happens to hold.
  func testRequestFieldWireSpellings() {
    let expected: [FBAXWire.Request: (key: String, flag: String?)] = [
      .verb: ("verb", nil),
      .pid: ("pid", "--pid"),
      .maxDepth: ("maxDepth", "--max-depth"),
      .maxNodes: ("maxNodes", "--max-nodes"),
      .automationMode: ("automationMode", "--automation-mode"),
      .attributes: ("attributes", "--attributes"),
      .translatorVocabulary: ("translatorVocabulary", "--translator-vocabulary"),
      .snapshotTree: ("snapshotTree", "--snapshot-tree"),
      .explainUnreachable: ("explainUnreachable", "--explain-unreachable"),
      .x: ("x", "--x"),
      .y: ("y", "--y"),
      .method: ("method", "--method"),
      .action: ("action", "--action"),
      .value: ("value", "--value"),
      .assertKey: ("assertKey", "--assert-key"),
      .assertValue: ("assertValue", "--assert-value"),
    ]
    XCTAssertEqual(Set(FBAXWire.Request.allCases), Set(expected.keys), "every request field must have its spellings pinned")
    for (field, spelling) in expected {
      XCTAssertEqual(field.key, spelling.key, "\(field) JSON key")
      XCTAssertEqual(field.flag, spelling.flag, "\(field) argv flag")
    }
  }

  // The verb is the CLI's subcommand rather than an option, so it contributes no argv pair at all — the
  // guest reads argv strictly two at a time, and a lone flag would shift every field after it.
  func testTheVerbContributesNoArgvPair() {
    XCTAssertEqual(FBAXWire.Request.verb.argument("describe"), [])
    XCTAssertEqual(FBAXWire.Request.maxNodes.argument("5000"), ["--max-nodes", "5000"])
  }

  // MARK: - Write requests

  // The two transports send the same write in different shapes, so the shapes are pinned together: a
  // field added to one rendering and forgotten in the other is a write that behaves differently
  // depending on which transport the caller happens to hold.
  func testAWriteRendersTheSameFieldsForBothTransports() {
    let request = FBAXBridgeWriteRequest(
      kind: .perform(.press),
      x: 201,
      y: 406,
      pid: 4321,
      assertion: FBAXBridgeWriteAssertion(key: .label, value: "General")
    )
    XCTAssertEqual(
      request.arguments,
      [
        "accessibility", "perform", "--x", "201.0", "--y", "406.0", "--pid", "4321",
        "--action", "press", "--assert-key", "XC_kAXXCAttributeLabel", "--assert-value", "General",
      ]
    )
    XCTAssertEqual(
      request.payload as NSDictionary,
      [
        "verb": "perform", "x": 201.0, "y": 406.0, "pid": 4321,
        "action": "press", "assertKey": "XC_kAXXCAttributeLabel", "assertValue": "General",
      ] as NSDictionary
    )
  }

  func testASetValueRendersItsValueRatherThanAnAction() {
    let request = FBAXBridgeWriteRequest(kind: .setValue("hello"), x: 1, y: 2, pid: nil, assertion: nil)
    XCTAssertEqual(request.verb, .setValue)
    XCTAssertEqual(request.arguments, ["accessibility", "setvalue", "--x", "1.0", "--y", "2.0", "--value", "hello"])
    XCTAssertEqual(
      request.payload as NSDictionary,
      ["verb": "setvalue", "x": 1.0, "y": 2.0, "value": "hello"] as NSDictionary
    )
  }

  // An absent pid and an absent assertion contribute nothing at all. The guest reads argv in flag/value
  // pairs and rejects a pid that is present and non-positive, so an option rendered as an empty string
  // or a zero would be read as a request the caller never made.
  func testAbsentOptionsAreOmittedRatherThanSentEmpty() {
    let request = FBAXBridgeWriteRequest(kind: .perform(.scrollDown), x: 10, y: 20, pid: nil, assertion: nil)
    XCTAssertEqual(request.arguments, ["accessibility", "perform", "--x", "10.0", "--y", "20.0", "--action", "scroll-down"])
    XCTAssertFalse(request.arguments.contains("--pid"))
    XCTAssertFalse(request.arguments.contains("--assert-key"))
    XCTAssertNil(request.payload["pid"])
    XCTAssertNil(request.payload["assertKey"])
    XCTAssertNil(request.payload["assertValue"])
    XCTAssertEqual(request.arguments.count % 2, 0, "the guest reads argv in pairs, so a flag must never be left without a value")
  }

  // MARK: - Frontmost-method request selectors

  // `FBAXBridgeFrontmostMethod`'s raw values are the selectors the host sends the guest to pick a
  // frontmost-resolution strategy; each must round-trip through its raw value, and the guest-reported
  // `method` decodes back into these same cases.
  func testFrontmostMethodRequestSelectors() {
    let expected: [FBAXBridgeFrontmostMethod: String] = [
      .centerPoint: "center-point",
      .windowServer: "window-server",
      .runningBoard: "runningboard",
    ]
    XCTAssertEqual(
      Set(FBAXBridgeFrontmostMethod.allCases), Set(expected.keys),
      "every frontmost method must have its selector pinned"
    )
    for (method, selector) in expected {
      XCTAssertEqual(method.rawValue, selector)
      XCTAssertEqual(FBAXBridgeFrontmostMethod(rawValue: selector), method, "\(method) must round-trip through its selector")
    }
  }
}
