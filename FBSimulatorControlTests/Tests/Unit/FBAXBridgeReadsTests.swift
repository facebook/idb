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

/// Coverage for the axbridge read path that does not require a live simulator: the guest response
/// envelope parsing (`FBAXTreeRead`) and the tree -> shared-serializer integration that makes
/// the axbridge output identical to the testmanagerd backend (both feed `describeAllElements`).
final class FBAXBridgeReadsTests: XCTestCase {

  private func envelope(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }

  // MARK: - FBAXTreeRead envelope parsing

  func testParsesTreeFromOkEnvelope() throws {
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "General",
      FBAXWire.Node.identifier.rawValue: "com.apple.settings.general",
    ]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 42)
    XCTAssertEqual(parsed.tree[FBAXWire.Node.label.rawValue] as? String, "General")
    XCTAssertEqual(parsed.tree[FBAXWire.Node.identifier.rawValue] as? String, "com.apple.settings.general")
    XCTAssertFalse(parsed.truncated, "a whole-tree read with no truncated flag is a complete tree")
  }

  func testParsesTruncatedFlagWhenGuestReportsAPartialTree() throws {
    // A guest walk cut short by the depth or node bound tags its envelope `truncated: true`, so the
    // conformer can warn the tree is incomplete rather than pass it off as whole.
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "root"]
    let data = try envelope(["ok": true, "tree": tree, "truncated": true])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 42)
    XCTAssertTrue(parsed.truncated, "the guest's truncation flag must be surfaced to the caller")
  }

  func testSurfacesGuestErrorMessage() throws {
    // An untagged failure (no `error_kind`) is an opaque `guestFailure` carrying the guest's own
    // message, so callers see the real cause.
    let data = try envelope(["ok": false, "error": "the accessibility server is not responding"])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 7)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("an untagged failure should be a guestFailure, got: \(error)")
      }
      XCTAssertTrue("\(error)".contains("the accessibility server is not responding"), "unexpected error: \(error)")
    }
  }

  func testApplicationUnavailableErrorKindThrowsTypedCase() throws {
    // A failure tagged `application_unavailable` becomes the typed `FBAXBridgeError.applicationUnavailable`
    // (carrying the pid), which the conformer re-raises as the backend-neutral
    // `FBUIAutomationError.applicationUnavailable` — matching what the remote backend throws for a dead pid.
    let data = try envelope(["ok": false, "error": "no application element for pid 7", "error_kind": "application_unavailable"])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 7)) { error in
      guard case let FBAXBridgeError.applicationUnavailable(pid) = error else {
        return XCTFail("a tagged failure should be applicationUnavailable, got: \(error)")
      }
      XCTAssertEqual(pid, 7)
    }
  }

  // MARK: - What the parser does with the guest's failure kind and reason

  // The guest names what went wrong and why; these cover how much of that reaches a caller.

  func testFusedFrontmostRaisesTheGuestsKindAndCarriesItsReason() throws {
    // A reader that could not bind names the missing class and every drifted signature beside it — the
    // most actionable text the guest produces. It reaches the caller intact and as its own case, rather
    // than being replaced by a fixed sentence about resolving the frontmost app.
    let data = try envelope([
      "ok": false,
      "error": "XCTAccessibilityFramework unavailable — is XCTAutomationSupport loaded?",
      "error_kind": "reader_unavailable",
    ])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data, method: .centerPoint)) { error in
      guard case let FBAXBridgeError.readerUnavailable(reason) = error else {
        return XCTFail("expected readerUnavailable, got: \(error)")
      }
      XCTAssertEqual(reason, "XCTAccessibilityFramework unavailable — is XCTAutomationSupport loaded?")
      XCTAssertTrue("\(error)".contains("XCTAccessibilityFramework"), "the reason must reach the message: \(error)")
    }
  }

  func testFusedFrontmostReportsAnUnreadableApplicationAsSuchAndNotAsAFrontmostFailure() throws {
    // The guest tagged this `application_unavailable`, and it means the same thing here as it does on a
    // `--pid` read: nothing frontmost has an accessibility server. Reporting it as a frontmost-strategy
    // failure sent the caller after the wrong thing. There is no pid because nothing resolved.
    let data = try envelope([
      "ok": false,
      "error": "no accessibility server answered the system-wide hit-test at (201.0, 437.0)",
      "error_kind": "application_unavailable",
    ])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data, method: .centerPoint)) { error in
      guard case let FBAXBridgeError.applicationUnavailable(pid) = error else {
        return XCTFail("expected applicationUnavailable, got: \(error)")
      }
      XCTAssertNil(pid, "a frontmost read that resolved nothing has no pid to name")
    }
  }

  // A strategy that could not answer is the case that keeps `frontmostUnresolved`, and it names the
  // strategy the caller selected — the other two may well answer, so which one was asked for is the
  // actionable half.
  func testFusedFrontmostNamesTheStrategyThatCouldNotAnswer() throws {
    let data = try envelope([
      "ok": false,
      "error": "AXPTranslator unavailable — is AccessibilityPlatformTranslation loaded?",
      "error_kind": "frontmost_unresolved",
    ])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data, method: .windowServer)) { error in
      guard case let FBAXBridgeError.frontmostUnresolved(method, reason) = error else {
        return XCTFail("expected frontmostUnresolved, got: \(error)")
      }
      XCTAssertEqual(method, .windowServer)
      XCTAssertEqual(reason, "AXPTranslator unavailable — is AccessibilityPlatformTranslation loaded?")
      XCTAssertTrue("\(error)".contains("window-server"), "the message must name the strategy: \(error)")
    }
  }

  func testHitTestRaisesTheGuestsFailureKind() throws {
    // All three parsers classify alike now: a tagged hit-test failure is the typed case, not an opaque
    // one, and the pid the guest reported rides with it.
    let data = try envelope([
      "ok": false,
      "error": "pid 8865 has no accessibility server to hit-test",
      "error_kind": "application_unavailable",
      "pid": 8865,
    ])
    XCTAssertThrowsError(try FBAXTreeRead(hitTestResponse: data)) { error in
      guard case let FBAXBridgeError.applicationUnavailable(pid) = error else {
        return XCTFail("expected applicationUnavailable, got: \(error)")
      }
      XCTAssertEqual(pid, 8865, "the guest's reported pid must ride out on the error")
    }
  }

  func testAnApplicationThatDidNotAnswerIsItsOwnCase() throws {
    // A live app that did not answer is distinct from one that is gone — the reason the guest classifies
    // the AX timeout at all — so it must not land in the same bucket as a reader bug.
    let data = try envelope([
      "ok": false,
      "error": "pid 8865 did not answer the read of its element tree in time",
      "error_kind": "application_not_responding",
      "pid": 8865,
    ])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 8865)) { error in
      guard case let FBAXBridgeError.applicationNotResponding(pid) = error else {
        return XCTFail("expected applicationNotResponding, got: \(error)")
      }
      XCTAssertEqual(pid, 8865)
    }
  }

  // The reported pid is JSON off the wire, so a value too large for a `pid_t` has to degrade like any
  // other malformed field. The non-failable conversion traps, which would make a bad response crash the
  // host at parse time — the opposite of what this classifier promises.
  func testAnOutOfRangeReportedPidDegradesRatherThanTrapping() throws {
    let data = try envelope([
      "ok": false,
      "error": "pid 8865 has no accessibility server",
      "error_kind": "application_unavailable",
      "pid": 99_999_999_999,
    ])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 42)) { error in
      guard case let FBAXBridgeError.applicationUnavailable(pid) = error else {
        return XCTFail("expected applicationUnavailable, got: \(error)")
      }
      XCTAssertEqual(pid, 42, "an unusable reported pid falls back to the one the caller named")
    }
  }

  // A kind this host has never heard of has to degrade to what an untagged failure already does, so a
  // guest running ahead of its host costs precision and nothing else.
  func testAnUnknownFailureKindDegradesToAnOpaqueFailureCarryingTheMessage() throws {
    let data = try envelope(["ok": false, "error": "something new went wrong", "error_kind": "application_on_fire"])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data, method: .centerPoint)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("expected guestFailure, got: \(error)")
      }
      XCTAssertTrue("\(error)".contains("something new went wrong"), "the message must survive: \(error)")
    }
  }

  func testThrowsOnMalformedResponse() {
    let data = Data("this is not json".utf8)
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 1))
  }

  func testThrowsWhenOkButNoTree() throws {
    let data = try envelope(["ok": true])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 1))
  }

  func testThrowsWhenNotOk() throws {
    // `ok` missing/false with no `error` still fails rather than yielding an empty tree.
    let data = try envelope(["tree": [FBAXWire.Node.label.rawValue: "x"]])
    XCTAssertThrowsError(try FBAXTreeRead(wholeTreeResponse: data, pid: 1))
  }

  // MARK: - One error type across backends

  // The point of the unified error: a caller holding `any FBUIAutomation` does not statically know
  // its backend, so "not found" has to be catchable without knowing. One catch clause must handle
  // every backend, and the message must still say which one spoke.
  func testOneCatchClauseHandlesEveryBackend() {
    let backends: [FBUIAutomationBackend] = [.accessibility, .remoteAutomation, .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint), .axBridge(persistence: .persistent, frontmostMethod: .centerPoint)]
    for backend in backends {
      let thrown: Error = FBUIAutomationError.elementNotFound(backend: backend, key: "AXLabel", value: "General")
      guard case let FBUIAutomationError.elementNotFound(caught, key, value) = thrown else {
        return XCTFail("\(backend) did not match the shared case")
      }
      XCTAssertEqual(caught, backend)
      XCTAssertEqual(key, "AXLabel")
      XCTAssertEqual(value, "General")
      let description = (thrown as? LocalizedError)?.errorDescription ?? ""
      XCTAssertTrue(description.contains(backend.displayName), "message should name the backend: \(description)")
      XCTAssertTrue(description.contains("General"), "message should name the marker: \(description)")
    }
  }

  // MARK: - Where the accessibility-server remediation is offered

  private static let axBridge = FBUIAutomationBackend.axBridge(persistence: .oneShot, frontmostMethod: .centerPoint)

  // An application with no accessibility server is the one condition the flag addresses, and the only
  // neutral case that offers it. The other two are not accessibility-configuration problems at all: an
  // empty point is a successful read of blank space, and a marker that never appeared is about the app's
  // state, so each states its own cause and points somewhere that can help.
  func testOnlyAnUnreadableApplicationOffersTheAccessibilityServerGuidance() {
    let unavailable = FBUIAutomationError.applicationUnavailable(backend: Self.axBridge, pid: 8865)
    XCTAssertTrue(unavailable.description.contains("ApplicationAccessibilityEnabled"), "got: \(unavailable.description)")
    XCTAssertTrue(unavailable.description.contains("pid 8865"), "the message must name the process: \(unavailable.description)")

    let empty = FBUIAutomationError.noElementAtPoint(backend: Self.axBridge, x: 2000, y: 2000)
    XCTAssertFalse(empty.description.contains("ApplicationAccessibilityEnabled"), "got: \(empty.description)")
    XCTAssertTrue(empty.description.contains("the point is empty"), "an empty point must say so: \(empty.description)")

    let timedOut = FBUIAutomationError.timedOut(backend: Self.axBridge, key: "AXLabel", value: "General", timeout: 5)
    XCTAssertFalse(timedOut.description.contains("ApplicationAccessibilityEnabled"), "got: \(timedOut.description)")
    XCTAssertTrue(timedOut.description.contains("never appeared"), "a timeout must say what did not happen: \(timedOut.description)")
  }

  // A display-wide read that resolved nothing has no pid, so the message says where it looked instead of
  // printing a zero — and still offers the guidance, the condition being the same one.
  func testAnUnreadableApplicationWithNoResolvedPidSaysWhereItLooked() {
    let error = FBUIAutomationError.applicationUnavailable(backend: Self.axBridge, pid: nil)
    XCTAssertTrue(error.description.contains("at that point"), "got: \(error.description)")
    XCTAssertFalse(error.description.contains("pid 0"), "a missing pid must not print as zero: \(error.description)")
    XCTAssertTrue(error.description.contains("ApplicationAccessibilityEnabled"), "got: \(error.description)")
  }

  // Each of these states a different cause, so a reader can tell them apart without the backend having
  // to be asked. This is the whole point of the stack: one message per condition.
  func testEachFailureModeStatesItsOwnCause() {
    let cases: [(any LocalizedError, String)] = [
      (FBAXBridgeError.readerUnavailable("XCTAccessibilityFramework unavailable"), "could not bind"),
      (FBAXBridgeError.frontmostUnresolved(method: .runningBoard, reason: "Client not entitled"), "runningboard strategy"),
      (FBUIAutomationError.applicationNotResponding(backend: Self.axBridge, pid: 8865), "did not answer in time"),
      (FBUIAutomationError.applicationUnavailable(backend: Self.axBridge, pid: 8865), "accessibility server has not started"),
      (FBUIAutomationError.noElementAtPoint(backend: Self.axBridge, x: 1, y: 2), "the point is empty"),
    ]
    var descriptions: Set<String> = []
    for (error, expected) in cases {
      let description = error.errorDescription ?? ""
      XCTAssertTrue(description.contains(expected), "expected \"\(expected)\" in: \(description)")
      descriptions.insert(description)
    }
    XCTAssertEqual(descriptions.count, cases.count, "no two failure modes may share a message")
  }

  // The remote backend's read failure genuinely is about the flag — that session documents
  // `ApplicationAccessibilityEnabled=1` as a precondition — so its guidance stays put throughout.
  func testTheRemoteBackendTreeFailureCarriesTheAccessibilityServerGuidance() {
    let error = FBRemoteAutomationError.treeUnavailable(x: 201, y: 437)
    XCTAssertTrue(error.description.contains("ApplicationAccessibilityEnabled"), "got: \(error.description)")
  }

  // The failures that were never about the flag, and must stay that way. `frontmostUnresolved` is among
  // them because it replaced the case that *did* carry the guidance: it now states the guest's own reason
  // instead, and the sub-case that really is a missing accessibility server no longer reaches it — the
  // guest tags that `application_unavailable`, so it arrives as the case below that does carry guidance.
  func testTheFailuresThatAreNotAboutTheFlagOfferNoAccessibilityGuidance() {
    let errors: [String: any LocalizedError] = [
      "readerUnavailable": FBAXBridgeError.readerUnavailable("XCTAccessibilityFramework unavailable"),
      "frontmostUnresolved": FBAXBridgeError.frontmostUnresolved(method: .windowServer, reason: "AXPTranslator unavailable"),
      "applicationNotResponding": FBUIAutomationError.applicationNotResponding(backend: Self.axBridge, pid: 8865),
    ]
    for (name, error) in errors {
      XCTAssertFalse(
        (error.errorDescription ?? "").contains("ApplicationAccessibilityEnabled"),
        "\(name) must not offer a remedy that cannot apply to it: \(error.errorDescription ?? "")"
      )
    }
  }

  func testValueMismatchIsSeamCatchableAndNamesTheMismatch() {
    // A `tap` value assertion is a fact about the query, not the transport, so it is the neutral
    // `FBUIAutomationError` — catchable by a caller holding `any FBUIAutomation` — and its message
    // names the backend, the key, and both values.
    let thrown: Error = FBUIAutomationError.valueMismatch(
      backend: .accessibility, key: FBAXSearchableKey.value.rawValue, expected: "On", actual: "Off"
    )
    guard case let FBUIAutomationError.valueMismatch(backend, key, expected, actual) = thrown else {
      return XCTFail("value mismatch should match the shared case, got: \(thrown)")
    }
    XCTAssertEqual(backend, .accessibility)
    XCTAssertEqual(key, "AXValue")
    XCTAssertEqual(expected, "On")
    XCTAssertEqual(actual, "Off")
    let description = (thrown as? LocalizedError)?.errorDescription ?? ""
    XCTAssertTrue(description.contains("The accessibility backend"), "message should name the backend: \(description)")
    XCTAssertTrue(description.contains("AXValue"), "message should name the key: \(description)")
    XCTAssertTrue(description.contains("On") && description.contains("Off"), "message should name both values: \(description)")
  }

  // MARK: - Which read failures a marker wait polls through

  // An app still launching has no frontmost, no readable tree and no accessibility server, and acquires
  // all three shortly, so a wait is right to keep polling through those.
  func testAWaitPollsThroughTheFailuresAnAppStillLaunchingProduces() {
    let transient: [String: FBAXBridgeError] = [
      "frontmostUnresolved": .frontmostUnresolved(method: .centerPoint, reason: "found no element"),
      "applicationUnavailable": .applicationUnavailable(pid: 8865),
      "applicationNotResponding": .applicationNotResponding(pid: 8865),
      "guestFailure": .guestFailure("something transient"),
    ]
    for (name, error) in transient {
      XCTAssertTrue(error.isTransientWhileWaitingForAMarker, "\(name) must not end the wait")
    }
  }

  // Neither of these changes by being asked again, so both end the wait with what they already know
  // rather than being replaced by a timeout once the deadline passes.
  func testAWaitEndsAtOnceOnAFailureThatCannotResolveItself() {
    XCTAssertFalse(
      FBAXBridgeError.readerUnavailable("XCTAccessibilityFramework unavailable").isTransientWhileWaitingForAMarker,
      "a reader that cannot bind will not bind by being polled"
    )
    XCTAssertFalse(FBAXBridgeError.bridgeUnavailable.isTransientWhileWaitingForAMarker)
  }

  // MARK: - Marker matching agrees with the accessibility backend

  // The accessibility backend walks the live tree and matches a marker by substring, so the
  // serialized-tree matcher the XCUI-grade backends use must do the same: a marker has to resolve to
  // the same element whichever backend serves the read, or `--api` silently changes what `tap General`
  // hits. This pins the substring contract stated on FBAccessibilityElementQuery.marker.
  func testMarkerMatchesBySubstring() throws {
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: [
        FBAXWire.Node.label.rawValue: "root",
        FBAXWire.Node.children.rawValue: [
          [FBAXWire.Node.label.rawValue: "General Settings", FBAXWire.Node.children.rawValue: [[String: Any]]()] as [String: Any]
        ],
      ],
      keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 1
    )
    let match = FBAXTreeWalk.matchingElement(inElements: elements, markerValue: "General", key: .label)
    guard let label = match?.label ?? nil else {
      return XCTFail("a substring marker must match, got: \(String(describing: match))")
    }
    XCTAssertEqual(label, "General Settings")
  }

  func testMarkerFrameCentreMatchesBySubstring() throws {
    // `tap`/`wait`/`set-value` resolve through frameCenter, so it must use the same predicate as the
    // describe matcher — otherwise a marker could be describable but not tappable.
    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: [
        FBAXWire.Node.label.rawValue: "General Settings",
        FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(CGRect(x: 10, y: 20, width: 100, height: 50)) as NSDictionary,
        FBAXWire.Node.children.rawValue: [[String: Any]](),
      ],
      keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 1
    )
    let centre = FBAXTreeWalk.frameCenter(inElements: elements, markerValue: "General", key: .label)
    XCTAssertEqual(centre?.x, 60)
    XCTAssertEqual(centre?.y, 45)
  }

  // MARK: - A marker matches by its searched key regardless of the requested key set

  // A marker is matched over the *serialized* element, so the searched key's field has to be among the
  // keys a tree was serialized with. Every marker call site therefore unions the searched key's
  // serialization key into the read set — a mapping that is only sound because each searchable key
  // serializes into the field named by its own raw value.
  func testSearchableKeyMapsToItsOwnSerializedField() {
    let searchable: [FBAXSearchableKey] = [.label, .uniqueID, .value, .title, .role, .roleDescription, .subrole, .help, .placeholder]
    for key in searchable {
      XCTAssertEqual(key.serializationKey.rawValue, key.rawValue, "\(key) must serialize into the field its marker match reads")
    }
  }

  func testMarkerMatchesWhenSearchedKeyIsOutsideTheRequestedKeySet() {
    // describe serialized with the caller's requested keys and the marker verbs with the default set,
    // so a searched key outside that set — a restricted key request, or `.placeholder`, which the
    // default set omits — was silently unmatchable even when a matching element was present.
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "General Settings",
      FBAXWire.Node.children.rawValue: [[String: Any]](),
    ]
    let requested: Set<FBAXKeys> = [.value]
    let withoutSearchedKey = FBAXTreeWalk.describeAllElements(fromTree: tree, keys: requested, nestedFormat: false, pid: 1)
    XCTAssertNil(
      FBAXTreeWalk.matchingElement(inElements: withoutSearchedKey, markerValue: "General", key: .label),
      "a key absent from the serialized set must not resolve a marker"
    )
    let withSearchedKey = FBAXTreeWalk.describeAllElements(
      fromTree: tree, keys: requested.union([FBAXSearchableKey.label.serializationKey]), nestedFormat: false, pid: 1
    )
    guard let label = FBAXTreeWalk.matchingElement(inElements: withSearchedKey, markerValue: "General", key: .label)?.label ?? nil
    else {
      return XCTFail("unioning the searched key must make the marker resolve regardless of the requested keys")
    }
    XCTAssertEqual(label, "General Settings")
  }

  // MARK: - FBAXTreeRead system-wide hit-test parsing

  func testHitTestParsesHitNodeAndOwningPid() throws {
    // A system-wide hit-test resolves which app owns the point, so the response carries the owning pid
    // the host tags the element with.
    let node: [String: Any] = [FBAXWire.Node.identifier.rawValue: "com.apple.settings.general"]
    let data = try envelope(["ok": true, "tree": node, "pid": 8865])
    let parsed = try FBAXTreeRead(hitTestResponse: data)
    XCTAssertEqual(parsed?.tree[FBAXWire.Node.identifier.rawValue] as? String, "com.apple.settings.general")
    XCTAssertEqual(parsed?.pid, 8865)
  }

  func testHitTestReturnsNilForEmptyResult() throws {
    // `{ok:true, empty:true}` is "no element at the point" — a valid empty result, returned as nil,
    // not conflated with a reader failure.
    let data = try envelope(["ok": true, "empty": true])
    XCTAssertNil(try FBAXTreeRead(hitTestResponse: data))
  }

  func testHitTestThrowsOnFailure() throws {
    // A failure (`ok:false`) is distinct from an empty result and is surfaced with the guest message.
    let data = try envelope(["ok": false, "error": "AXUIElementCopyElementAtPosition unavailable"])
    XCTAssertThrowsError(try FBAXTreeRead(hitTestResponse: data)) { error in
      XCTAssertTrue("\(error)".contains("AXUIElementCopyElementAtPosition unavailable"), "unexpected error: \(error)")
    }
  }

  func testHitTestThrowsWhenOkButNoTreeOrEmpty() throws {
    let data = try envelope(["ok": true])
    XCTAssertThrowsError(try FBAXTreeRead(hitTestResponse: data))
  }

  func testHitTestThrowsWhenOwningPidMissing() throws {
    // A hit node with no owning pid is a protocol violation — the host cannot tag the element.
    let data = try envelope(["ok": true, "tree": [FBAXWire.Node.identifier.rawValue: "x"]])
    XCTAssertThrowsError(try FBAXTreeRead(hitTestResponse: data)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("a hit-test without an owning pid should be guestFailure, got: \(error)")
      }
    }
  }

  // MARK: - FBAXTreeRead fused frontmost tree parsing

  func testFrontmostTreeParsesTreeAndResolvedPid() throws {
    // The fused read resolves the frontmost app AND reads its tree in one call, so the response carries
    // the resolved pid the host tags elements with — it did not know the pid in advance.
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "Settings"]
    let data = try envelope(["ok": true, "tree": tree, "pid": 8865, "method": "center-point", "truncated": false])
    let parsed = try FBAXTreeRead(frontmostResponse: data, method: .centerPoint)
    XCTAssertEqual(parsed.pid, 8865)
    XCTAssertEqual(parsed.tree[FBAXWire.Node.label.rawValue] as? String, "Settings")
    XCTAssertFalse(parsed.truncated)
  }

  func testFrontmostTreeSurfacesTruncation() throws {
    let data = try envelope(["ok": true, "tree": [FBAXWire.Node.label.rawValue: "root"], "pid": 1, "truncated": true])
    XCTAssertTrue(try FBAXTreeRead(frontmostResponse: data, method: .centerPoint).truncated)
  }

  func testFrontmostTreeThrowsFrontmostUnresolvedOnAnEmptyAnchor() throws {
    // Nothing at the anchor — an app mid-launch, or genuinely empty space. The strategy ran and named
    // nothing, so it is `frontmostUnresolved`, which the read poll retries.
    let data = try envelope([
      "ok": false,
      "error": "system-wide hit-test at (201.0, 437.0) found no element",
      "error_kind": "frontmost_unresolved",
    ])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data, method: .centerPoint)) { error in
      guard case let FBAXBridgeError.frontmostUnresolved(method, reason) = error else {
        return XCTFail("a strategy that named nothing should be frontmostUnresolved, got: \(error)")
      }
      XCTAssertEqual(method, .centerPoint)
      XCTAssertEqual(reason, "system-wide hit-test at (201.0, 437.0) found no element")
    }
  }

  // Both success paths admitted any positive `Int` and then converted it, so a pid above `Int32.max`
  // trapped the host at parse time. Uncommented here, alongside the guard that makes it pass: against the
  // previous commit it would have aborted the runner rather than failed, which is why it was pinned
  // commented out.
  func testAnOutOfRangeResolvedPidIsRejectedRatherThanTrapping() throws {
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "root"]
    let frontmost = try envelope(["ok": true, "tree": tree, "pid": 99_999_999_999])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: frontmost, method: .centerPoint)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("expected guestFailure, got: \(error)")
      }
    }

    let hit = try envelope(["ok": true, "tree": tree, "pid": 99_999_999_999])
    XCTAssertThrowsError(try FBAXTreeRead(hitTestResponse: hit)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("expected guestFailure, got: \(error)")
      }
    }
  }

  func testFrontmostTreeThrowsWhenResolvedPidMissing() throws {
    // An ok response with a tree but no pid is a protocol violation — the host cannot tag the elements.
    let data = try envelope(["ok": true, "tree": [FBAXWire.Node.label.rawValue: "x"]])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data, method: .centerPoint)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("a fused response without a pid should be guestFailure, got: \(error)")
      }
    }
  }

  func testFrontmostTreeThrowsWhenTreeMissing() throws {
    let data = try envelope(["ok": true, "pid": 8865])
    XCTAssertThrowsError(try FBAXTreeRead(frontmostResponse: data, method: .centerPoint)) { error in
      guard case FBAXBridgeError.guestFailure = error else {
        return XCTFail("a fused response without a tree should be guestFailure, got: \(error)")
      }
    }
  }

  // MARK: - Fullscreen-modal descriptor parsing + non-serialization

  func testModalParsesSystemAlert() {
    let response: [String: Any] = ["ok": true, "modal": ["kind": "system", "elementType": "SBAlertItemWindow", "label": "Allow \u{201c}Maps\u{201d} to use your location?"]]
    let modal = FBAXTreeRead.modal(fromResponse: response)
    XCTAssertEqual(modal?.kind, .system)
    XCTAssertEqual(modal?.elementType, "SBAlertItemWindow")
    XCTAssertEqual(modal?.label, "Allow \u{201c}Maps\u{201d} to use your location?")
  }

  func testModalParsesAppAlertWithoutLabel() {
    let response: [String: Any] = ["ok": true, "modal": ["kind": "app", "elementType": "_UIAlertControllerView"]]
    let modal = FBAXTreeRead.modal(fromResponse: response)
    XCTAssertEqual(modal?.kind, .app)
    XCTAssertEqual(modal?.elementType, "_UIAlertControllerView")
    XCTAssertNil(modal?.label)
  }

  func testModalAbsentOrMalformedIsNil() {
    XCTAssertNil(FBAXTreeRead.modal(fromResponse: ["ok": true]), "no modal key -> nil")
    XCTAssertNil(FBAXTreeRead.modal(fromResponse: ["ok": true, "modal": ["elementType": "X"]]), "missing kind -> nil")
    XCTAssertNil(FBAXTreeRead.modal(fromResponse: ["ok": true, "modal": ["kind": "bogus", "elementType": "X"]]), "unknown kind -> nil")
  }

  func testFrontmostTreeCarriesModalDescriptor() throws {
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "root"]
    let data = try envelope(["ok": true, "tree": tree, "pid": 20475, "modal": ["kind": "system", "elementType": "SBAlertItemWindow", "label": "Allow"]])
    let parsed = try FBAXTreeRead(frontmostResponse: data, method: .centerPoint)
    XCTAssertEqual(parsed.pid, 20475)
    XCTAssertEqual(parsed.modal?.kind, .system)
    XCTAssertEqual(parsed.modal?.elementType, "SBAlertItemWindow")
  }

  func testModalIsNeverSerializedInTheCLIOutput() throws {
    // The modal field enriches the host view but MUST NOT change the emitted CLI/gRPC JSON — a response
    // with a modal must serialize byte-identically to one without.
    let modal = FBAccessibilityModalInfo(kind: .system, elementType: "SBAlertItemWindow", label: "Allow")
    let withModal = FBAccessibilityElementsResponse(elements: .tree([]), modal: modal)
    let without = FBAccessibilityElementsResponse(elements: .tree([]))
    let a = try withModal.legacyJSONData()
    let b = try without.legacyJSONData()
    XCTAssertEqual(a, b, "the modal descriptor must not appear in the serialized output")
  }

  // MARK: - Tree -> shared serializer integration

  func testGuestTreeFeedsSharedSerializerSchema() throws {
    // A guest envelope carrying a small XC_kAXXC* tree round-trips through the same path the
    // testmanagerd backend uses (`FBAXTreeRead(wholeTreeResponse:)` -> `describeAllElements`), producing the
    // shared schema: the child is a Button (automationType 9) with its identifier, proving the
    // axbridge output is byte-compatible with the shared serializer rather than a bespoke shape.
    let tree: [String: Any] = [
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.label.rawValue: "General",
          FBAXWire.Node.identifier.rawValue: "com.apple.settings.general",
          FBAXWire.Node.automationType.rawValue: 9,
          FBAXWire.Node.children.rawValue: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 99)

    let elements = FBAXTreeWalk.describeAllElements(
      fromTree: parsed.tree, keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 99
    )
    XCTAssertEqual(elements.count, 2, "expected the root plus its one child, flattened")

    let response = FBAccessibilityElementsResponse(
      elements: .tree(elements)
    )
    let json = try response.legacyJSONData()
    let serialized = String(data: json, encoding: .utf8) ?? ""
    XCTAssertTrue(serialized.contains("com.apple.settings.general"), "missing identifier in \(serialized)")
    // automationType 9 maps to the readable XCUIElementType name via the shared serializer.
    XCTAssertTrue(serialized.contains("\"role\":\"Button\""), "role not mapped in \(serialized)")
  }

  // MARK: - Shared `describeTree` composition

  // `describeTree` is the `FBAXTreeReader` extension both XCUI-grade backends (axbridge and
  // testmanagerd) inherit as their `describe`, so what it composes — which query shape yields an array
  // versus a bare object, how the modal rides out, when the truncation warning fires, and which keys a
  // marker is serialized with — is backend-agnostic behaviour that neither backend's own tests cover.
  // A stub conformer supplies a canned read so the composition is observable without a simulator.

  private static func twoNodeTree() -> [String: Any] {
    [
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.label.rawValue: "General Settings",
          FBAXWire.Node.children.rawValue: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
  }

  private static func stubRead(truncated: Bool = false, modal: FBAccessibilityModalInfo? = nil) -> FBAXTreeRead {
    FBAXTreeRead(tree: twoNodeTree(), pid: 99, truncated: truncated, modal: modal)
  }

  func testDescribeTreeReturnsAnArrayForWholeTreeQueries() async throws {
    for query in [FBAccessibilityElementQuery.frontmost, .application(pid: 99)] {
      let reader = StubTreeReader(read: Self.stubRead())
      let response = try await reader.describeTree(query, options: FBAccessibilityRequestOptions())
      guard case let .tree(elements) = response.elements else {
        return XCTFail("\(query) must serialize to an array, got \(response.elements)")
      }
      XCTAssertEqual(elements.count, 2, "the whole tree is flattened to root plus child")
    }
  }

  // A marker resolves to one element, so the response carries a bare object — the same shape the
  // accessibility backend now returns, so a consumer no longer branches on `--api` here.
  func testDescribeTreeReturnsABareObjectForAMarkerQuery() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    let response = try await reader.describeTree(
      .marker(value: "General", key: .label, depth: 10), options: FBAccessibilityRequestOptions()
    )
    guard case let .single(element) = response.elements else {
      return XCTFail("a marker must serialize to a single object, got \(response.elements)")
    }
    XCTAssertEqual(element.label, .some("General Settings"))
  }

  func testDescribeTreeCarriesTheModalDescriptorOutOfTheRead() async throws {
    let modal = FBAccessibilityModalInfo(kind: .system, elementType: "SBAlertItemWindow", label: "Allow")
    for query in [FBAccessibilityElementQuery.frontmost, .marker(value: "General", key: .label, depth: 10)] {
      let reader = StubTreeReader(read: Self.stubRead(modal: modal))
      let response = try await reader.describeTree(query, options: FBAccessibilityRequestOptions())
      XCTAssertEqual(response.modal, modal, "\(query) must surface the read's modal to the host")
    }
  }

  // The truncation warning belongs to a describe, not to a raw read: it fires exactly once per
  // describe so a `.marker` wait poll (which reads without describing) stays silent.
  func testDescribeTreeWarnsOnceWithTheReadsTruncationFlag() async throws {
    let reader = StubTreeReader(read: Self.stubRead(truncated: true))
    _ = try await reader.describeTree(.frontmost, options: FBAccessibilityRequestOptions())
    XCTAssertEqual(reader.truncationWarnings, [true], "one warning carrying the read's flag")
  }

  // A marker is matched over the *serialized* element, so the searched key is unioned into the read key
  // set — otherwise a marker on a key the caller did not request could never resolve.
  func testDescribeTreeUnionsTheSearchedKeyForAMarker() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    let options = FBAccessibilityRequestOptions(keys: [.value])
    let response = try await reader.describeTree(
      .marker(value: "General", key: .label, depth: 10), options: options
    )
    guard case let .single(element) = response.elements else {
      return XCTFail("expected a single object, got \(response.elements)")
    }
    XCTAssertNotNil(element.label, "the searched key must be serialized even when unrequested")
  }

  // A marker's match runs over a flattened tree regardless of the caller's format, so a nested request
  // still resolves the element rather than searching only the root — and the match it returns reports
  // children like any other single-element read of that format, empty because none were walked.
  func testDescribeTreeMatchesAMarkerFlatEvenWhenNestedIsRequested() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    let options = FBAccessibilityRequestOptions(format: .nested)
    let response = try await reader.describeTree(
      .marker(value: "General", key: .label, depth: 10), options: options
    )
    guard case let .single(element) = response.elements else {
      return XCTFail("expected a single object, got \(response.elements)")
    }
    XCTAssertEqual(element.label, .some("General Settings"))
    XCTAssertEqual(element.children, [], "the match reports children, empty because the search walk was flat")
  }

  func testDescribeTreeHonoursTheRequestedNestedFormatForWholeTreeQueries() async throws {
    let response = try await StubTreeReader(read: Self.stubRead())
      .describeTree(.frontmost, options: FBAccessibilityRequestOptions(format: .nested))
    guard case let .tree(elements) = response.elements, let root = elements.first else {
      return XCTFail("expected a nested root, got \(response.elements)")
    }
    XCTAssertEqual(elements.count, 1, "nested output carries the child inside the root, not beside it")
    guard let children = root.children, let child = children.first else {
      return XCTFail("expected the child nested under the root, got \(String(describing: root.children))")
    }
    XCTAssertEqual(child.label, .some("General Settings"))
  }

  func testDescribeTreeHonoursTheRequestedFilterForWholeTreeQueries() async throws {
    // The unlabeled root of this tree is dropped by `.interactable`, leaving only the labeled child.
    let tree: [String: Any] = [
      FBAXWire.Node.children.rawValue: [
        [FBAXWire.Node.label.rawValue: "General Settings", FBAXWire.Node.children.rawValue: [[String: Any]]()] as [String: Any]
      ]
    ]
    let reader = StubTreeReader(read: FBAXTreeRead(tree: tree, pid: 99, truncated: false, modal: nil))
    let response = try await reader.describeTree(.frontmost, options: FBAccessibilityRequestOptions(filter: .interactable))
    guard case let .tree(elements) = response.elements else {
      return XCTFail("expected an array, got \(response.elements)")
    }
    XCTAssertEqual(elements.count, 1, "the unlabeled container is filtered out, its labeled child kept")
  }

  // MARK: - Frame coverage

  /// A root spanning a 390x844 screen with one child covering its lower half — enough for a coverage
  /// calculation to have both a screen to measure against and an element to measure. The element types
  /// are `XCUIElementType` raw values, which is how the guest reports a role: 2 is Application, 9 is
  /// Button.
  private static func sizedTree() -> [String: Any] {
    [
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.elementType.rawValue: NSNumber(value: 2),
      FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 0, width: 390, height: 844)) as NSDictionary,
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.label.rawValue: "Lower Half",
          FBAXWire.Node.elementType.rawValue: NSNumber(value: 9),
          FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 422, width: 390, height: 422)) as NSDictionary,
          FBAXWire.Node.children.rawValue: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
  }

  // `describeTree` is the read path every backend but `ax` funnels through. It used to ignore
  // `collectFrameCoverage` entirely — the option was accepted, carried the whole way down, and dropped,
  // so those backends reported `coverage: null` however it was asked for.
  func testDescribeTreeReportsTheRequestedFrameCoverage() async throws {
    let reader = StubTreeReader(read: FBAXTreeRead(tree: Self.sizedTree(), pid: 99, truncated: false, modal: nil))
    var options = FBAccessibilityRequestOptions(format: .complete)
    options.collectFrameCoverage = true
    let response = try await reader.describeTree(.frontmost, options: options)

    XCTAssertEqual(
      response.screen, FBAccessibilityScreenInfo(width: 390, height: 844),
      "the bounds a coverage calculation would measure against are known"
    )
    guard case let .tree(elements) = response.elements, let root = elements.first else {
      return XCTFail("expected a nested root, got \(response.elements)")
    }
    // `complete` is a nested format, so the child rides inside the root rather than beside it.
    let heights = ([root] + (root.children ?? [])).compactMap { element -> Double? in
      guard let frame = element.frame ?? nil else { return nil }
      return frame.height
    }
    XCTAssertEqual(heights, [844, 422], "and every element carries the frame it would be measured by")

    let coverage = try XCTUnwrap(response.coverage, "the guest backends collect coverage too")
    // The child covers the screen's lower half; the application root is excluded.
    XCTAssertEqual(coverage.frame, 0.5, accuracy: 0.01)
    XCTAssertEqual(coverage.walked, 0.5, accuracy: 0.01, "nothing was filtered, so the two ratios agree")
    XCTAssertNil(coverage.additional, "remote-content discovery is accessibility-only")
    XCTAssertEqual(response.document.coverage, coverage, "and the complete document reports it")
  }

  // Coverage stays opt-in: a read that did not ask for it reports none rather than a zero.
  func testDescribeTreeReportsNoCoverageUnlessAsked() async throws {
    let reader = StubTreeReader(read: FBAXTreeRead(tree: Self.sizedTree(), pid: 99, truncated: false, modal: nil))
    let response = try await reader.describeTree(.frontmost, options: FBAccessibilityRequestOptions(format: .complete))
    XCTAssertNil(response.coverage)
    XCTAssertNil(response.document.coverage)
  }

  // A read whose root reports no usable frame has no screen to measure against, so it reports no
  // coverage rather than measuring against a zero-sized grid.
  func testDescribeTreeReportsNoCoverageWithoutUsableScreenBounds() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    var options = FBAccessibilityRequestOptions(format: .complete)
    options.collectFrameCoverage = true
    let response = try await reader.describeTree(.frontmost, options: options)
    XCTAssertNil(response.screen, "the stub tree's root reports no frame")
    XCTAssertNil(response.coverage, "so there is nothing to measure against")
  }

  /// `sizedTree()` with the lower half's label removed, so `.interactable` drops it: element type 1 is
  /// Other, which is not an actionable role.
  private static func sizedTreeWithUnlabeledLowerHalf() -> [String: Any] {
    [
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.elementType.rawValue: NSNumber(value: 2),
      FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 0, width: 390, height: 844)) as NSDictionary,
      FBAXWire.Node.children.rawValue: [
        [
          FBAXWire.Node.elementType.rawValue: NSNumber(value: 1),
          FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 422, width: 390, height: 422)) as NSDictionary,
          FBAXWire.Node.children.rawValue: [[String: Any]](),
        ] as [String: Any]
      ],
    ]
  }

  // MARK: - What `content` has to get right

  // These are synthetic trees standing for the tree *shapes* real apps produce, not captured traces.
  // Each states what a content measure must say about it, and together they are why `content` counts a
  // labelled leaf rather than anything looser: every weaker predicate gets at least one of them wrong.
  //
  // The shape that breaks the loose predicates is the container chain. A guest backend wraps its content
  // in a named window, an application element, a scroll view carrying an identifier, and a run of
  // anonymous layout nodes — every one of them full-screen. Coverage is a union of areas, so a single
  // full-screen element that passes the predicate saturates the whole measure at `1.0`.

  private static let syntheticScreen = CGRect(x: 0, y: 0, width: 400, height: 800)

  private static func node(
    _ type: Int, _ frame: CGRect, label: String? = nil, identifier: String? = nil,
    children: [[String: Any]] = []
  ) -> [String: Any] {
    var node: [String: Any] = [
      FBAXWire.Node.elementType.rawValue: NSNumber(value: type),
      FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(frame) as NSDictionary,
      FBAXWire.Node.children.rawValue: children,
    ]
    if let label { node[FBAXWire.Node.label.rawValue] = label }
    if let identifier { node[FBAXWire.Node.identifier.rawValue] = identifier }
    return node
  }

  /// The guest shape: a named window over an application element over an identified scroll view over a
  /// run of anonymous full-screen layout nodes, with `content` at the bottom. Element types are
  /// `XCUIElementType` raw values — 1 Other, 2 Application, 9 Button, 48 StaticText.
  private static func containerChain(wrapping content: [[String: Any]]) -> [String: Any] {
    let full = syntheticScreen
    var innermost = node(1, full, children: content)
    for _ in 0..<4 {
      innermost = node(1, full, children: [innermost])
    }
    let scrollView = node(1, full, identifier: "scroll-view", children: [innermost])
    let application = node(2, full, identifier: "app-window", children: [scrollView])
    return node(1, full, label: "App Title", children: [application])
  }

  private func contentCoverage(of tree: [String: Any]) async throws -> Double? {
    let reader = StubTreeReader(read: FBAXTreeRead(tree: tree, pid: 99, truncated: false, modal: nil))
    var options = FBAccessibilityRequestOptions(format: .complete)
    options.collectFrameCoverage = true
    return try await reader.describeTree(.frontmost, options: options).coverage?.content
  }

  // Text filling most of the screen is content, whether or not containers are wrapped around it. The
  // chain must not change the answer — that is the whole point of measuring leaves.
  func testContentCoverageIsHighForDenseTextWithAndWithoutAContainerChain() async throws {
    let text = [Self.node(48, CGRect(x: 0, y: 80, width: 400, height: 640), label: "lots of text")]
    let bare = Self.node(2, Self.syntheticScreen, label: "App", children: text)

    let bareMeasured = try await contentCoverage(of: bare)
    let chainedMeasured = try await contentCoverage(of: Self.containerChain(wrapping: text))
    let bareCoverage = try XCTUnwrap(bareMeasured)
    let chainedCoverage = try XCTUnwrap(chainedMeasured)
    XCTAssertEqual(bareCoverage, 0.8, accuracy: 0.02, "the text covers four fifths of the screen")
    XCTAssertEqual(chainedCoverage, bareCoverage, accuracy: 0.001, "wrapping it in containers changes nothing")
  }

  // The case coverage exists to detect: a full-screen region the app draws but does not describe, with
  // only a nav bar exposed above it. It must read as low however deeply it is wrapped.
  //
  // This is what rules out counting an identifier. The unexposed region carries one — a developer handle
  // for automation — and every predicate that accepts an identifier calls this screen fully covered.
  func testContentCoverageIsLowForAnUndescribedRegion() async throws {
    let sparse = [
      Self.node(9, CGRect(x: 0, y: 0, width: 400, height: 60), label: "Nav"),
      Self.node(1, CGRect(x: 0, y: 60, width: 400, height: 740), identifier: "webview"),
    ]
    let bare = Self.node(2, Self.syntheticScreen, label: "App", children: sparse)

    let bareMeasured = try await contentCoverage(of: bare)
    let chainedMeasured = try await contentCoverage(of: Self.containerChain(wrapping: sparse))
    let bareCoverage = try XCTUnwrap(bareMeasured)
    let chainedCoverage = try XCTUnwrap(chainedMeasured)
    XCTAssertLessThan(bareCoverage, 0.1, "only the nav bar is described")
    XCTAssertEqual(chainedCoverage, bareCoverage, accuracy: 0.001, "and the chain does not describe it either")
  }

  // An app icon is a labelled button wrapping an unlabelled image, and a user plainly perceives all of
  // it. This is what rules out requiring childlessness: under that rule the button is skipped for having
  // a child and the image for having no label, so a screen full of icons measures zero.
  //
  // What disowns a label is a *labelled* descendant — the element the label decorates rather than
  // describes — so the button counts and its image does not, and the region is counted once.
  func testContentCoverageCountsALabelledElementWrappingUnlabelledDecoration() async throws {
    let icons = [
      Self.node(
        9, CGRect(x: 0, y: 0, width: 100, height: 100), label: "Maps",
        children: [Self.node(1, CGRect(x: 0, y: 0, width: 100, height: 100))]
      ),
      Self.node(
        9, CGRect(x: 100, y: 0, width: 100, height: 100), label: "Photos",
        children: [Self.node(1, CGRect(x: 100, y: 0, width: 100, height: 100))]
      ),
    ]
    let measured = try await contentCoverage(of: Self.containerChain(wrapping: icons))
    let coverage = try XCTUnwrap(measured)
    XCTAssertEqual(coverage, 0.07, accuracy: 0.02, "the two icons, counted once each rather than not at all")
  }

  // A handful of small labelled widgets on an otherwise empty screen is low coverage, not the `1.0` the
  // enclosing named window would report on its own.
  func testContentCoverageIsLowForSparseWidgetsInAContainerChain() async throws {
    let widgets = [
      Self.node(9, CGRect(x: 0, y: 0, width: 200, height: 100), label: "A"),
      Self.node(9, CGRect(x: 0, y: 700, width: 400, height: 100), label: "B"),
    ]
    let measured = try await contentCoverage(of: Self.containerChain(wrapping: widgets))
    let coverage = try XCTUnwrap(measured)
    XCTAssertEqual(coverage, 0.19, accuracy: 0.02, "the two widgets, and none of the containers holding them")
  }

  // The two ratios diverge on the guest backends the same way they do on the accessibility one — the
  // calculation is shared, so the gap cannot come to mean different things per backend.
  func testDescribeTreeReportsWalkedCoverageAboveReportedWhenFiltering() async throws {
    let reader = StubTreeReader(
      read: FBAXTreeRead(tree: Self.sizedTreeWithUnlabeledLowerHalf(), pid: 99, truncated: false, modal: nil)
    )
    var options = FBAccessibilityRequestOptions(format: .complete)
    options.collectFrameCoverage = true
    options.filter = .interactable
    let response = try await reader.describeTree(.frontmost, options: options)

    let coverage = try XCTUnwrap(response.coverage)
    XCTAssertEqual(coverage.walked, 0.5, accuracy: 0.01, "the walk saw the unlabeled element covering the lower half")
    XCTAssertEqual(coverage.frame, 0, accuracy: 0.01, "the filter dropped it, so the report covers nothing")
  }
  func testDescribeTreeThrowsWhenNoElementMatchesTheMarker() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    do {
      _ = try await reader.describeTree(
        .marker(value: "Nothing", key: .label, depth: 10), options: FBAccessibilityRequestOptions()
      )
      XCTFail("an unmatched marker must throw")
    } catch let error as FBUIAutomationError {
      guard case .elementNotFound = error else {
        return XCTFail("expected elementNotFound, got \(error)")
      }
    }
  }

  // A point never reads a tree: it delegates to the backend's targeted hit-test, and turns that verb's
  // "no element" (nil) into a throw, which is what makes `describe(.point:)` throwing while `hitTest`
  // stays optional.
  func testDescribeTreeDelegatesAPointToHitTestWithoutReadingATree() async throws {
    let hit = FBAccessibilityElementsResponse(
      elements: .single(
        {
          var e = FBAccessibilityDocumentElement()
          e.label = .some("hit")
          return e
        }()))
    let reader = StubTreeReader(read: Self.stubRead(), hitTestResult: hit)
    let response = try await reader.describeTree(.point(CGPoint(x: 3, y: 4)), options: FBAccessibilityRequestOptions())
    XCTAssertEqual(reader.hitTestPoints, [CGPoint(x: 3, y: 4)])
    XCTAssertEqual(reader.readCount, 0, "a point must not read a whole tree")
    XCTAssertTrue(reader.truncationWarnings.isEmpty, "a point read has no tree to warn about")
    guard case let .single(element) = response.elements else {
      return XCTFail("expected the hit-test's element, got \(response.elements)")
    }
    XCTAssertEqual(element.label, .some("hit"))
  }

  // MARK: - Provenance stamping

  // The backend and the query are known here, not by the front-end that asked for a format, so
  // `describeTree` stamps them on the way out. These fields feed the `complete` document only.
  func testDescribeTreeStampsBackendAndTargetForEveryQueryKind() async throws {
    let hit = FBAccessibilityElementsResponse(elements: .single(FBAccessibilityDocumentElement()))
    let cases: [(FBAccessibilityElementQuery, FBAccessibilityTargetDescriptor.Kind)] = [
      (.frontmost, .frontmost),
      (.application(pid: 99), .application),
      (.marker(value: "General", key: .label, depth: 10), .marker),
      (.point(CGPoint(x: 3, y: 4)), .point),
    ]
    for (query, kind) in cases {
      let reader = StubTreeReader(read: Self.stubRead(), hitTestResult: hit)
      let response = try await reader.describeTree(query, options: FBAccessibilityRequestOptions())
      XCTAssertEqual(response.backend, .axBridge, "\(query) must record which backend answered")
      XCTAssertEqual(response.target?.kind, kind, "\(query) must record what was asked for")
    }
  }

  func testDescribeTreeStampsTruncationAndScreenForTreeReads() async throws {
    // The stub tree's root reports no frame, so the screen is unknown rather than zero-sized.
    let reader = StubTreeReader(read: Self.stubRead(truncated: true))
    let response = try await reader.describeTree(.frontmost, options: FBAccessibilityRequestOptions())
    XCTAssertTrue(response.truncated, "a partial walk must be reported as partial")
    XCTAssertNil(response.screen, "a root with no frame yields no screen bounds")

    let sized: [String: Any] = [
      FBAXWire.Node.label.rawValue: "root",
      FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(CGRect(x: 0, y: 0, width: 390, height: 844)) as NSDictionary,
      FBAXWire.Node.children.rawValue: [[String: Any]](),
    ]
    let sizedReader = StubTreeReader(read: FBAXTreeRead(tree: sized, pid: 99, truncated: false, modal: nil))
    let sizedResponse = try await sizedReader.describeTree(.frontmost, options: FBAccessibilityRequestOptions())
    XCTAssertEqual(sizedResponse.screen, FBAccessibilityScreenInfo(width: 390, height: 844))
    XCTAssertFalse(sizedResponse.truncated)
  }

  // A hit-test resolves one element with no tree behind it, so there is nothing to say about the
  // screen or truncation — but which backend answered and what was asked for are still known.
  func testDescribeTreeStampsAPointWithoutScreenOrTruncation() async throws {
    let hit = FBAccessibilityElementsResponse(elements: .single(FBAccessibilityDocumentElement()))
    let reader = StubTreeReader(read: Self.stubRead(truncated: true), hitTestResult: hit)
    let response = try await reader.describeTree(.point(CGPoint(x: 3, y: 4)), options: FBAccessibilityRequestOptions())
    XCTAssertEqual(response.target, .point(CGPoint(x: 3, y: 4)))
    XCTAssertNil(response.screen)
    XCTAssertFalse(response.truncated, "the unread tree's truncation must not leak onto a hit-test")
  }

  // Stamping is provenance only: it must not disturb the elements or the legacy envelope's bytes.
  func testProvenanceDoesNotChangeTheLegacyEnvelope() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    let response = try await reader.describeTree(.frontmost, options: FBAccessibilityRequestOptions())
    let stamped = try response.legacyJSONData()
    let bare = try FBAccessibilityElementsResponse(elements: response.elements).legacyJSONData()
    XCTAssertEqual(stamped, bare, "provenance must stay out of the legacy envelope")
  }

  // The serializer takes a read's screen bounds from the element it is handed, so a single-element read
  // arrives carrying the element's own frame as the screen. That is worse than reporting nothing, and
  // `withProvenance` cannot withdraw a field — hence a dedicated way to clear it.
  func testWithoutScreenClearsBoundsAndKeepsEverythingElse() throws {
    let hit = FBAccessibilityElementsResponse(
      elements: .single(FBAccessibilityDocumentElement()),
      truncated: true,
      screen: FBAccessibilityScreenInfo(width: 370, height: 52),
      backend: .ax,
      target: .marker(value: "General", matchKey: "AXLabel")
    )
    XCTAssertNotNil(hit.screen, "the fixture starts with the misleading element-sized bounds")

    let stripped = hit.withoutScreen()
    XCTAssertNil(stripped.screen, "the element's own frame is not the screen")
    XCTAssertEqual(stripped.elements, hit.elements)
    XCTAssertEqual(stripped.truncated, hit.truncated)
    XCTAssertEqual(stripped.backend, hit.backend)
    XCTAssertEqual(stripped.target, hit.target)
  }

  // A marker read descends from the application root, so unlike a point read it *can* say what its
  // frames are relative to. Clear-then-stamp is the sequence the `ax` backend performs; the clear is
  // what makes it safe when the root's frame turns out not to describe a screen, since `withProvenance`
  // falls back to whatever the response already carries — which is the match's frame.
  func testMarkerReportsTheRootBoundsAndNeverTheMatchs() throws {
    let root = try XCTUnwrap(FBAccessibilityScreenInfo(width: 402, height: 874))
    let matchSized = FBAccessibilityElementsResponse(
      elements: .single(FBAccessibilityDocumentElement()),
      screen: FBAccessibilityScreenInfo(width: 370, height: 52),
      backend: .ax
    )

    let restamped = matchSized.withoutScreen().withProvenance(screen: root)
    XCTAssertEqual(restamped.screen, root, "a marker read reports the root's bounds, not the match's")
    XCTAssertEqual(restamped.backend, .ax, "clearing the screen does not disturb the rest of the provenance")

    XCTAssertNil(
      matchSized.withoutScreen().withProvenance(screen: nil).screen,
      "with no usable root bounds a marker reports none, rather than falling back to the match's frame"
    )
    XCTAssertEqual(
      matchSized.withProvenance(screen: nil).screen,
      matchSized.screen,
      "stamping alone cannot withdraw the match's frame — which is why the ax path clears first"
    )
  }

  func testBackendNameIsATotalBijection() {
    // Total over allCases: a backend added without teaching both directions fails here, not at a
    // consumer that silently cannot name (or select) it.
    for name in FBUIAutomationBackendName.allCases {
      XCTAssertEqual(
        FBUIAutomationBackend(name).name, name,
        "\(name.rawValue) must round-trip through the backend it selects"
      )
    }
    XCTAssertEqual(
      FBUIAutomationBackend.axBridge(persistence: .persistent, frontmostMethod: .centerPoint).name,
      .axBridgePersistent,
      "the persistent transport is a distinct backend to a consumer reading timings"
    )
    XCTAssertEqual(
      FBUIAutomationBackend(.axBridgePersistent, frontmostMethod: .windowServer).name,
      .axBridgePersistent,
      "the frontmost method rides the axbridge case without disturbing its name"
    )
  }

  func testDescribeTreeThrowsForAnEmptyPoint() async throws {
    let reader = StubTreeReader(read: Self.stubRead(), hitTestResult: nil)
    do {
      _ = try await reader.describeTree(.point(CGPoint(x: 1, y: 2)), options: FBAccessibilityRequestOptions())
      XCTFail("an empty point must throw from describe")
    } catch let error as FBUIAutomationError {
      guard case .noElementAtPoint = error else {
        return XCTFail("expected noElementAtPoint, got \(error)")
      }
    }
  }
}

/// A minimal `FBAXTreeReader` serving a canned read, so the shared `describeTree` composition can be
/// observed without a simulator. `readRawTree`, `warnIfTruncated` and `hitTest` are the three seams
/// `describeTree` drives; every other `FBUIAutomation` verb is an unused conformance stub.
private final class StubTreeReader: FBAXTreeReader, @unchecked Sendable {

  let backend: FBUIAutomationBackend = .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint)

  private let read: FBAXTreeRead
  private let hitTestResult: FBAccessibilityElementsResponse?

  private(set) var readCount = 0
  private(set) var truncationWarnings: [Bool] = []
  private(set) var hitTestPoints: [CGPoint] = []

  init(read: FBAXTreeRead, hitTestResult: FBAccessibilityElementsResponse? = nil) {
    self.read = read
    self.hitTestResult = hitTestResult
  }

  func readRawTree(for query: FBAccessibilityElementQuery) async throws -> FBAXTreeRead {
    readCount += 1
    return read
  }

  func warnIfTruncated(_ truncated: Bool) async {
    truncationWarnings.append(truncated)
  }

  func hitTest(at point: CGPoint, options: FBAccessibilityRequestOptions) async throws -> FBAccessibilityElementsResponse? {
    hitTestPoints.append(point)
    return hitTestResult
  }

  func describe(_ query: FBAccessibilityElementQuery, options: FBAccessibilityRequestOptions) async throws -> FBAccessibilityElementsResponse {
    try await describeTree(query, options: options)
  }

  func tap(_ query: FBAccessibilityElementQuery, options: FBTapOptions) async throws {}

  func setValue(_ value: String, for query: FBAccessibilityElementQuery) async throws {}

  func wait(_ query: FBAccessibilityElementQuery, timeout: TimeInterval, pollInterval: TimeInterval) async throws {}

  func scroll(_ query: FBAccessibilityElementQuery, direction: FBAccessibilityScrollDirection) async throws {}

  func frame(_ query: FBAccessibilityElementQuery) async throws -> CGRect { .zero }
}
