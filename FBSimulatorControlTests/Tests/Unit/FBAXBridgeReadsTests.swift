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

  func testParsesTheAutomationStateFromTheEnvelope() throws {
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "root"]
    let data = try envelope([
      "ok": true, "tree": tree, "automation": ["enabled": true, "asserted": false],
    ])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 42)
    XCTAssertEqual(parsed.automation?.enabled, true)
    XCTAssertEqual(parsed.automation?.asserted, false)
  }

  // Nil, not `enabled: false`. A guest predating the field did not say what mode the device was in, and
  // that is a different fact from saying it was off — collapsing them would report every older guest's
  // reads as definitely-not-in-automation-mode.
  func testAnEnvelopeWithoutAutomationReportsNothingRatherThanOff() throws {
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "root"]
    let data = try envelope(["ok": true, "tree": tree])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 42)
    XCTAssertNil(parsed.automation, "an absent automation object must not read as automation mode being off")
  }

  // `asserted` absent is the state before anything asserts, and false is the truthful answer for it.
  func testAutomationAssertedDefaultsToFalseWhenOmitted() throws {
    let tree: [String: Any] = [FBAXWire.Node.label.rawValue: "root"]
    let data = try envelope(["ok": true, "tree": tree, "automation": ["enabled": true]])
    let parsed = try FBAXTreeRead(wholeTreeResponse: data, pid: 42)
    XCTAssertEqual(parsed.automation?.enabled, true)
    XCTAssertEqual(parsed.automation?.asserted, false)
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

  func testFusedFrontmostApplicationUnavailableKindThrowsApplicationUnavailable() throws {
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
    // All three parsers classify alike: a tagged hit-test failure is the typed case, not an opaque
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
    let data = try envelope(["ok": false, "error": "something new went wrong", "error_kind": "some_future_kind"])
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
    let backends: [FBUIAutomationBackend] = [.accessibility, .remoteAutomation, .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint, automationMode: true), .axBridge(persistence: .shared, frontmostMethod: .centerPoint, automationMode: true)]
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

  // MARK: - What a read costs is decided by its key set

  // Requesting the reachability attributes makes the application hit-test every node, so the default set
  // must not contain them. This checks that, rather than relying on the comment that says so.
  func testTheDefaultKeySetAsksForNoReachabilityAttribute() {
    for expensive: FBAXKeys in [.interactable, .occludedBy] {
      XCTAssertFalse(
        FBAXKeys.defaultSet.contains(expensive),
        "\(expensive.rawValue) costs a hit-test per node and must stay out of the default set"
      )
    }
  }

  // A default read sends no attribute list at all, so the guest uses its own default. That keeps the
  // request identical to one from a host that predates the field, and guarantees nothing extra is
  // fetched.
  func testADefaultReadNamesNoAttributesOnTheWire() {
    XCTAssertNil(
      FBAXWire.Node.fetchList(for: FBAXKeys.defaultSet),
      "a default read must leave the attribute list off the wire entirely"
    )
  }

  // A filter chooses which elements to report, not what the read fetches, so `--filter interactable`
  // does not make the application hit-test every node.
  func testTheInteractableFilterDoesNotWidenTheRead() {
    var options = FBAccessibilityRequestOptions()
    options.filter = .interactable
    XCTAssertFalse(
      options.serializationKeys.contains(.interactable),
      "a filter must not pull the verdict into a key set the caller did not ask for"
    )
    XCTAssertNil(
      FBAXWire.Node.fetchList(for: options.serializationKeys),
      "so a filtered read still names no attributes on the wire, exactly like an unfiltered one"
    )
  }

  // Asking for the verdict still fetches the attributes it is derived from.
  func testAskingForTheVerdictStillFetchesWhatDerivesIt() {
    var options = FBAccessibilityRequestOptions()
    options.filter = .interactable
    options.keys = FBAXKeys.defaultSet.union([.interactable])
    let fetchList = FBAXWire.Node.fetchList(for: options.serializationKeys)
    for reachability in FBAXWire.Node.interactableAttributes {
      XCTAssertTrue(
        fetchList?.contains(reachability.rawValue) ?? false,
        "\(reachability.rawValue) is fetched because the caller asked for the verdict, not because a filter did"
      )
    }
  }

  // MARK: - Where the accessibility-server remediation is offered

  private static let axBridge = FBUIAutomationBackend.axBridge(persistence: .oneShot, frontmostMethod: .centerPoint, automationMode: true)

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

  // One message per condition, so a reader can tell the causes apart without asking the backend.
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
  // `ApplicationAccessibilityEnabled=1` as a precondition — so it carries the guidance.
  func testTheRemoteBackendTreeFailureCarriesTheAccessibilityServerGuidance() {
    let error = FBRemoteAutomationError.treeUnavailable(x: 201, y: 437)
    XCTAssertTrue(error.description.contains("ApplicationAccessibilityEnabled"), "got: \(error.description)")
  }

  // The failures that are not about the flag must not carry its guidance. `frontmostUnresolved` states
  // the guest's own reason; a genuinely missing accessibility server is tagged `application_unavailable`
  // by the guest and arrives as the case that does carry guidance.
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

  // MARK: - The lane's automation-mode default

  // Pinned because selecting the lane by name is how almost every caller reaches it, so this is the
  // value that decides what a device does in practice. It is a payload rather than a constant, so this
  // test keeps a change to the default deliberate.
  func testSelectingTheAxbridgeLaneByNameAssertsAutomationMode() {
    for name in [FBUIAutomationBackendName.axBridge, .axBridgePersistent] {
      guard case let .axBridge(_, _, automationMode) = FBUIAutomationBackend(resolvedName: name) else {
        return XCTFail("\(name) did not select an axbridge backend")
      }
      XCTAssertEqual(automationMode, true, "selecting \(name) by name asserts automation mode")
    }
  }

  // The tri-state has to survive the enum, not just the wire. `false` is what reproduces the child-cache
  // fault and what measures the mode's cost, and it must not collapse into "did not ask".
  func testTheAxbridgeBackendCarriesAnExplicitlyDisabledAutomationMode() {
    guard case let .axBridge(_, _, off) = FBUIAutomationBackend(resolvedName: .axBridge, automationMode: false),
      case let .axBridge(_, _, unset) = FBUIAutomationBackend(resolvedName: .axBridge, automationMode: nil)
    else {
      return XCTFail("expected axbridge backends")
    }
    XCTAssertEqual(off, false, "explicitly off is carried, not dropped")
    XCTAssertNil(unset, "and is distinct from observing without asking")
  }

  // MARK: - Profile shape per backend

  private func timings(
    roundTrip: CFAbsoluteTime, decode: CFAbsoluteTime, traverse: CFAbsoluteTime?, machRoundTrips: Int64?,
    responseBytes: Int64 = 1024
  ) -> FBAXReadTimings {
    FBAXReadTimings(
      roundTrip: roundTrip, decode: decode, traverse: traverse, machRoundTrips: machRoundTrips,
      responseBytes: responseBytes)
  }

  // The whole point of the residual: on a one-shot read most of the round trip is not the walk, and the
  // profile has to attribute it somewhere honest rather than losing it.
  func testTheResidualIsTheRoundTripLessTheWalk() {
    let t = timings(roundTrip: 0.387, decode: 0.004, traverse: 0.023, machRoundTrips: 134)
    XCTAssertEqual(t.residual, 0.364, accuracy: 0.0001, "387ms round trip less a 23ms walk")
  }

  // A guest that does not report its walk must not make the residual look like the whole read *plus* a
  // phantom walk, nor go negative.
  func testTheResidualDegradesToTheRoundTripWhenTheGuestDidNotReportAWalk() {
    let t = timings(roundTrip: 0.2, decode: 0.001, traverse: nil, machRoundTrips: nil)
    XCTAssertEqual(t.residual, 0.2, accuracy: 0.0001)
  }

  // Clocks are not monotonic across processes, and a guest reporting a walk longer than the host's round
  // trip is possible. A negative duration is worse than a clamped one: it would poison any aggregate.
  func testTheResidualNeverGoesNegative() {
    let t = timings(roundTrip: 0.010, decode: 0.001, traverse: 0.050, machRoundTrips: 10)
    XCTAssertEqual(t.residual, 0, "a walk longer than the round trip clamps rather than going negative")
  }

  // MARK: - Suspect-geometry guidance

  private func summary(total: Int, zeroFrame: Int) -> FBAccessibilityFrameSummary {
    FBAccessibilityFrameSummary(total: total, framed: total - zeroFrame, zeroFrame: zeroFrame)
  }

  // The signature the advice exists for: a read that is well-formed, untruncated and error-free, whose
  // elements have simply lost their geometry. Nothing else in the response distinguishes it, which is why
  // this is the one place in the read path allowed a threshold.
  func testMostlyUnframedReadsAreAdvisedAboutAutomationMode() {
    let advice = FBAccessibilityGuidance.zeroFrameAdvice(summary(total: 190, zeroFrame: 167))
    XCTAssertNotNil(advice)
    XCTAssertTrue(advice?.contains("AutomationEnabled") == true, "got: \(advice ?? "nil")")
  }

  func testFullyFramedReadsAreNotAdvised() {
    XCTAssertNil(FBAccessibilityGuidance.zeroFrameAdvice(summary(total: 176, zeroFrame: 0)))
  }

  // A handful of unframed elements is ordinary. The advice is about a whole screen having lost its
  // geometry, not about any element that reports none.
  func testASmallReadIsNotJudged() {
    XCTAssertNil(
      FBAccessibilityGuidance.zeroFrameAdvice(summary(total: 4, zeroFrame: 4)),
      "reads below the size threshold produce no advice, whatever their ratio"
    )
  }

  // Nil rather than zeroes means the read carried no frames at all, which is a caller's choice via
  // `--key`. Advising on it would be answering a question they did not ask.
  func testAReadCarryingNoFramesIsNotAdvised() {
    XCTAssertNil(FBAccessibilityGuidance.zeroFrameAdvice(nil))
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
      XCTAssertTrue(error.isTransientDuringMarkerWait, "\(name) must not end the wait")
    }
  }

  // Neither of these changes by being asked again, so both end the wait with what they already know
  // rather than being replaced by a timeout once the deadline passes.
  func testAWaitEndsAtOnceOnAFailureThatCannotResolveItself() {
    XCTAssertFalse(
      FBAXBridgeError.readerUnavailable("XCTAccessibilityFramework unavailable").isTransientDuringMarkerWait,
      "readerUnavailable is not transient; the wait must end immediately"
    )
    XCTAssertFalse(FBAXBridgeError.bridgeUnavailable.isTransientDuringMarkerWait)
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

  // MARK: - Marker case sensitivity is opt-in, and reads only

  private func settingsElements() -> [FBAccessibilityDocumentElement] {
    FBAXTreeWalk.describeAllElements(
      fromTree: [
        FBAXWire.Node.label.rawValue: "General Settings",
        FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(CGRect(x: 10, y: 20, width: 100, height: 50)) as NSDictionary,
        FBAXWire.Node.children.rawValue: [[String: Any]](),
      ],
      keys: FBAXKeys.defaultSet, nestedFormat: false, pid: 1
    )
  }

  func testMarkerIsCaseSensitiveUnlessAsked() throws {
    let elements = settingsElements()
    XCTAssertNil(
      FBAXTreeWalk.matchingElement(inElements: elements, markerValue: "general", key: .label),
      "the default must stay the historical case-sensitive match"
    )
    guard
      let label = FBAXTreeWalk.matchingElement(
        inElements: elements, markerValue: "general", key: .label, ignoresCase: true
      )?.label ?? nil
    else {
      return XCTFail("--ignore-case must resolve a marker that differs only in case")
    }
    XCTAssertEqual(label, "General Settings")
  }

  func testMarkerWritesStayCaseSensitive() {
    // `tap`/`scroll`/`set-value`/`wait` resolve through resolveMarker, which takes no case option: a
    // write that resolved "ok" to a *Cancel* button labelled "OK" would act on an element the caller
    // did not name, and unlike a read it cannot be undone by reading again.
    let elements = settingsElements()
    XCTAssertEqual(
      FBAXTreeWalk.resolveMarker(inElements: elements, markerValue: "general", key: .label),
      .notFound
    )
    XCTAssertNil(FBAXTreeWalk.frameCenter(inElements: elements, markerValue: "general", key: .label))
  }

  func testEmptyMarkerKeepsMatchingTheFirstElementCarryingTheKey() {
    // Every value contains the empty string, so an empty marker has always resolved to the first
    // element with the searched key at all. `FBAccessibilityMatch` refuses to represent that, and the
    // matcher must not let the refusal turn into a silent "no match".
    let label = FBAXTreeWalk.matchingElement(inElements: settingsElements(), markerValue: "", key: .label)?.label ?? nil
    XCTAssertEqual(label, "General Settings")
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
    // The marker union below is what makes a searched key outside the requested set — a restricted key
    // request, or `.placeholder`, which the default set omits — matchable at all.
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

  // A pid above `Int32.max` must be rejected as a guest failure rather than trapping in the
  // non-failable `Int32` conversion.
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
  // accessibility backend returns, so a consumer never branches on `--api` here.
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

  // The choice is only worth having if it reaches the wire, on every query that reads a tree.
  func testDescribeTreeCarriesTheChosenTraversalToTheRead() async throws {
    for query in [FBAccessibilityElementQuery.frontmost, .marker(value: "General", key: .label, depth: 10)] {
      let reader = StubTreeReader(read: Self.stubRead())
      _ = try? await reader.describeTree(query, options: FBAccessibilityRequestOptions(traversalStrategy: .semantic))
      XCTAssertEqual(reader.traversals, [.semantic], "\(query) must carry the caller's choice to the read")
    }
  }

  // The single fetch is a traversal choice, so it has to reach the read like the other two do.
  func testDescribeTreeCarriesTheSingleFetchToTheRead() async throws {
    for query in [FBAccessibilityElementQuery.frontmost, .marker(value: "General", key: .label, depth: 10)] {
      let reader = StubTreeReader(read: Self.stubRead())
      _ = try? await reader.describeTree(query, options: FBAccessibilityRequestOptions(traversalStrategy: .singleFetch))
      XCTAssertEqual(reader.traversals, [.singleFetch], "\(query) must carry the caller's choice to the read")
    }
  }

  // The profile must report the traversal that actually ran — inferring it from `mach_round_trips`
  // breaks as soon as two traversals produce the same count.
  func testDescribeTreeReportsTheTraversalItReadWith() async throws {
    for strategy in FBAXTraversalStrategy.allCases {
      let reader = StubTreeReader(read: Self.stubRead())
      var options = FBAccessibilityRequestOptions(traversalStrategy: strategy)
      options.enableProfiling = true
      let response = try await reader.describeTree(.frontmost, options: options)
      guard case let .guestBridge(profile)? = response.profilingData else {
        return XCTFail("expected a guest profile, got \(String(describing: response.profilingData))")
      }
      // Against what the read resolved to rather than what was asked for, which is the point of the
      // field: `auto` names no traversal and the profile must still report the one that ran.
      XCTAssertEqual(profile.traversal, StubTreeReader.resolvedTraversal(for: options))
      XCTAssertEqual(reader.traversals, reader.profiledTraversals, "the read and its profile must agree")
    }
  }

  // The field rides on the profile, so a read that did not ask for profiling reports no traversal.
  func testTheTraversalIsOnlyReportedWhenProfilingWasAskedFor() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    let response = try await reader.describeTree(
      .frontmost, options: FBAccessibilityRequestOptions(traversalStrategy: .singleFetch)
    )
    XCTAssertNil(response.profilingData)
    XCTAssertEqual(reader.profiledTraversals, [], "an unprofiled read must not build a profile at all")
  }

  // The walk done in one call, so per-element answers match — reachability is a whole-read refusal in
  // `describeTree`, not a per-element gap, which is why it does not appear here.
  func testTheSingleFetchAnswersEveryKeyTheDefaultWalkDoes() {
    XCTAssertEqual(FBAXTraversal.singleFetch.unsatisfiableKeys, [])
    XCTAssertEqual(
      FBAXTraversal.singleFetch.unsatisfiableKeys,
      FBAXTraversal.viewHierarchy.unsatisfiableKeys
    )
  }

  // An explicit single fetch asking for reachability is refused before any read is attempted: the guest
  // would time out rather than answer, so the combination fails fast with the keys it cannot serve.
  func testAnExplicitSingleFetchAskingForReachabilityIsRefused() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    do {
      _ = try await reader.describeTree(
        .frontmost, options: FBAccessibilityRequestOptions(keys: [.interactable], traversalStrategy: .singleFetch)
      )
      XCTFail("expected the read to be refused")
    } catch let FBUIAutomationError.traversalCannotAnswer(_, traversal, keys) {
      XCTAssertEqual(traversal, "single-fetch")
      XCTAssertEqual(keys, ["interactable"])
    }
    XCTAssertEqual(reader.traversals, [], "the refusal must happen before any read is attempted")
  }

  // The warning is what makes an absent field readable as "this traversal could not ask", so it belongs
  // on the describe that actually reports fields — not only on the marker branch.
  func testDescribeTreeWarnsAboutUnsatisfiableKeys() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    _ = try? await reader.describeTree(
      .frontmost, options: FBAccessibilityRequestOptions(keys: [.type, .label], traversalStrategy: .semantic)
    )
    XCTAssertEqual(reader.unsatisfiableWarnings, [[.type]], "a frontmost describe must warn it cannot type")
  }

  // A view-hierarchy read answers everything, so the warning must carry an empty set rather than be
  // skipped — an absent warning and a warning about nothing are the same thing to a caller.
  func testDescribeTreeWarnsAboutNothingOnASatisfiableTraversal() async throws {
    let reader = StubTreeReader(read: Self.stubRead())
    _ = try? await reader.describeTree(
      .frontmost, options: FBAccessibilityRequestOptions(keys: [.type, .label], traversalStrategy: .viewHierarchy)
    )
    XCTAssertEqual(reader.unsatisfiableWarnings, [[]], "nothing is unsatisfiable on the view hierarchy")
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
    XCTAssertNotNil(element.label as Any?, "the searched key must be serialized even when unrequested")
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

  // `describeTree` is the read path every backend but `ax` funnels through, so it must honour
  // `collectFrameCoverage` for all of them.
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
        FBUIAutomationBackend(resolvedName: name).name, name,
        "\(name.rawValue) must round-trip through the backend it selects"
      )
    }
    XCTAssertEqual(
      FBUIAutomationBackend.axBridge(persistence: .shared, frontmostMethod: .centerPoint, automationMode: true).name,
      .axBridgePersistent,
      "the persistent transport is a distinct backend to a consumer reading timings"
    )
    XCTAssertEqual(
      FBUIAutomationBackend(resolvedName: .axBridgePersistent, frontmostMethod: .windowServer).name,
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

  // MARK: - Shared `frameFromTree` composition

  // `frame` over a tree-reading backend is `describeTree` narrowed to the geometry key, so what it has
  // to get right is which element of the response answers each query shape, and what happens when that
  // element reports no rectangle.

  private static let rootRect = CGRect(x: 0, y: 0, width: 390, height: 844)
  private static let childRect = CGRect(x: 16, y: 100, width: 358, height: 44)

  private static func framedReader(child: CGRect? = childRect) -> StubTreeReader {
    func node(_ label: String, _ rect: CGRect?, children: [[String: Any]]) -> [String: Any] {
      var node: [String: Any] = [
        FBAXWire.Node.label.rawValue: label,
        FBAXWire.Node.children.rawValue: children,
      ]
      if let rect {
        node[FBAXWire.Node.frame.rawValue] = CGRectCreateDictionaryRepresentation(rect) as NSDictionary
      }
      return node
    }
    let tree = node("root", rootRect, children: [node("General Settings", child, children: [])])
    return StubTreeReader(read: FBAXTreeRead(tree: tree, pid: 99, truncated: false, modal: nil))
  }

  // A whole-tree query has no element in mind, so it answers with the root's — the application's own
  // rectangle, which is what the accessibility backend reports for the same query.
  func testFrameFromTreeAnswersWithTheRootRectangleForWholeTreeQueries() async throws {
    for query in [FBAccessibilityElementQuery.frontmost, .application(pid: 99)] {
      let frame = try await Self.framedReader().frameFromTree(query)
      XCTAssertEqual(frame, Self.rootRect, "\(query) must answer with the application root's frame")
    }
  }

  // The narrowed key set is the part most likely to break a marker: the searched key is unioned in by
  // `describeTree`, so asking for geometry alone still resolves the element rather than matching nothing.
  func testFrameFromTreeAnswersWithTheMatchedElementsRectangleForAMarker() async throws {
    let frame = try await Self.framedReader().frameFromTree(.marker(value: "General", key: .label, depth: 10))
    XCTAssertEqual(frame, Self.childRect, "a marker must answer with the matched element's frame, not the root's")
  }

  func testFrameFromTreeAnswersWithTheHitElementsRectangleForAPoint() async throws {
    var hit = FBAccessibilityDocumentElement()
    hit.frame = .some(FBAccessibilityFrame(Self.childRect))
    let reader = StubTreeReader(read: Self.stubRead(), hitTestResult: FBAccessibilityElementsResponse(elements: .single(hit)))
    let frame = try await reader.frameFromTree(.point(CGPoint(x: 20, y: 110)))
    XCTAssertEqual(frame, Self.childRect)
    XCTAssertEqual(reader.readCount, 0, "a point reads no tree to answer about its own frame")
  }

  // An element with no frame on the wire reports a zero rectangle, not an error — JSON carries no
  // infinity, so the guest emits nulls for a non-finite edge and `axFrame` normalizes the whole thing to
  // zero on the way in. `frame` therefore answers exactly what a describe of the same element reports;
  // the two must not disagree about geometry the read already resolved.
  func testFrameFromTreeReportsAZeroRectangleForAnElementWithNoFrameOnTheWire() async throws {
    let frame = try await Self.framedReader(child: nil).frameFromTree(.marker(value: "General", key: .label, depth: 10))
    XCTAssertEqual(frame, .zero)
  }

  // The guard on the total mapping from an optional-bearing response to a rectangle. A backend cannot
  // reach it — `frameFromTree` requests the frame key, so the read always carries one — but the response
  // type permits it, and a zero rect is not an answer a caller could tell apart from the origin.
  func testFrameFromTreeThrowsWhenTheReadCarriesNoFrame() async throws {
    let query = FBAccessibilityElementQuery.point(CGPoint(x: 20, y: 110))
    let frameless = FBAccessibilityElementsResponse(elements: .single(FBAccessibilityDocumentElement()))
    do {
      _ = try await StubTreeReader(read: Self.stubRead(), hitTestResult: frameless).frameFromTree(query)
      XCTFail("a read carrying no frame must throw rather than answer with the origin")
    } catch let error as FBUIAutomationError {
      guard case let .frameUnavailable(backend, thrownQuery) = error else {
        return XCTFail("expected frameUnavailable, got \(error)")
      }
      XCTAssertEqual(backend, .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint, automationMode: true))
      XCTAssertEqual(thrownQuery, query, "the error must name the target that was asked about")
    }
  }

  // Every query shape can be asked for a frame, so the error names whichever was asked — unlike
  // `elementNotOnScreen`, which can only speak about a marker.
  func testFrameUnavailableNamesEveryTargetShape() {
    let backend = FBUIAutomationBackend.axBridge(persistence: .oneShot, frontmostMethod: .centerPoint, automationMode: true)
    let expectations: [(FBAccessibilityElementQuery, String)] = [
      (.frontmost, "the frontmost application"),
      (.application(pid: 99), "pid 99"),
      (.marker(value: "General", key: .label, depth: 10), "AXLabel"),
      (.point(CGPoint(x: 3, y: 4)), "(3.0, 4.0)"),
    ]
    for (query, expected) in expectations {
      let description = FBUIAutomationError.frameUnavailable(backend: backend, query: query).description
      XCTAssertTrue(description.contains(expected), "\(query) should be named by \"\(expected)\": \(description)")
      XCTAssertTrue(description.contains(backend.displayName), "message should name the backend: \(description)")
    }
  }

  // MARK: - Shared `writeTarget` resolution

  // A write is point-addressed, so everything that decides *which* point — and what the guest must still
  // find there — happens before the request is built. That resolution is what these cover; the request
  // it turns into is pinned in `FBAXWireContractTests`.

  private static let marker = FBAccessibilityElementQuery.marker(value: "General", key: .label, depth: 10)

  // A coordinate names no element, so it is sent exactly as given: nothing to look up, nothing to assert
  // about, and no tree read to pay for.
  func testAPointWriteTargetsTheCoordinateItself() async throws {
    let reader = Self.framedReader()
    let target = try await reader.writeTarget(for: .point(CGPoint(x: 12, y: 34)), operation: "A tap")
    XCTAssertEqual(target, FBAXWriteTarget(point: CGPoint(x: 12, y: 34), pid: nil, assertion: nil))
    XCTAssertEqual(reader.readCount, 0, "a point write must not read a tree to find a point it was given")
  }

  // A marker resolves to the centre of the element it matched, scoped to the application the read
  // resolved so the guest hit-tests inside it rather than display-wide.
  func testAMarkerWriteTargetsTheMatchedElementsCentre() async throws {
    let target = try await Self.framedReader().writeTarget(for: Self.marker, operation: "A tap")
    XCTAssertEqual(target.point, CGPoint(x: Self.childRect.midX, y: Self.childRect.midY))
    XCTAssertEqual(target.pid, 99)
  }

  // The assertion carries what the element *actually* reports, not what the caller searched for. Markers
  // match by substring, so sending the marker text would refuse every marker that is a prefix of the
  // label it matched — "General" would never equal "General Settings".
  func testAMarkerAssertionCarriesTheMatchedValueRatherThanTheMarkerText() async throws {
    let target = try await Self.framedReader().writeTarget(for: Self.marker, operation: "A tap")
    XCTAssertEqual(target.assertion, FBAXBridgeWriteAssertion(key: .label, value: "General Settings"))
  }

  // Only the attributes this wire carries can be asserted on; a marker searched on a host-side
  // derivation still writes, unasserted, rather than not at all.
  func testAMarkerOnANonAssertableKeyStillResolvesWithoutAnAssertion() async throws {
    let tree: [String: Any] = [
      FBAXWire.Node.elementType.rawValue: "Button",
      FBAXWire.Node.frame.rawValue: CGRectCreateDictionaryRepresentation(Self.childRect) as NSDictionary,
      FBAXWire.Node.children.rawValue: [[String: Any]](),
    ]
    let reader = StubTreeReader(read: FBAXTreeRead(tree: tree, pid: 99, truncated: false, modal: nil))
    let target = try await reader.writeTarget(
      for: .marker(value: "Button", key: .role, depth: 10), operation: "A tap"
    )
    XCTAssertEqual(target.point, CGPoint(x: Self.childRect.midX, y: Self.childRect.midY))
    XCTAssertNil(target.assertion, "a key this wire does not carry must not become an assertion the guest cannot check")
  }

  // The mapping the assertion rests on, over every searchable key. The three that map are the ones whose
  // value comes straight off the wire; the rest are host-side derivations (`role` normalizes an element
  // type to a readable name, and the others are answered nil over this wire), so asserting on them would
  // compare the host's rendering against the guest's raw attribute and never match.
  func testOnlyWireBackedSearchKeysAreAssertable() {
    let expected: [FBAXSearchableKey: FBAXWire.Node?] = [
      .label: .label,
      .value: .value,
      .uniqueID: .identifier,
      .title: nil,
      .role: nil,
      .roleDescription: nil,
      .subrole: nil,
      .help: nil,
      .placeholder: nil,
    ]
    for (key, node) in expected {
      XCTAssertEqual(FBAXWire.Node(assertableSearchKey: key), node, "\(key)")
    }
  }

  // A point-addressed write acts on the deepest element under the point, so a whole-tree query would
  // silently become "whatever is in the middle of the screen" rather than the thing the caller named.
  func testWholeTreeQueriesAreRefusedForWrites() async throws {
    for query in [FBAccessibilityElementQuery.frontmost, .application(pid: 99)] {
      do {
        _ = try await Self.framedReader().writeTarget(for: query, operation: "A tap")
        XCTFail("\(query) must not resolve to a point to write to")
      } catch let error as FBUIAutomationError {
        guard case let .pointOrMarkerRequired(_, operation) = error else {
          return XCTFail("expected pointOrMarkerRequired, got \(error)")
        }
        XCTAssertEqual(operation, "A tap", "the error must name the verb that was refused")
      }
    }
  }

  func testAMarkerThatMatchesNothingIsNotFound() async throws {
    do {
      _ = try await Self.framedReader().writeTarget(
        for: .marker(value: "Wi-Fi", key: .label, depth: 10), operation: "A tap"
      )
      XCTFail("a marker matching nothing must not resolve a point")
    } catch let error as FBUIAutomationError {
      guard case let .elementNotFound(_, key, value) = error else {
        return XCTFail("expected elementNotFound, got \(error)")
      }
      XCTAssertEqual(key, "AXLabel")
      XCTAssertEqual(value, "Wi-Fi")
    }
  }

  // An element carrying no frame on the wire is normalized to a zero rectangle on the way in, which is a
  // rectangle with no area rather than an absent one. A write refuses it instead of resolving it to the
  // centre of nothing, which is the origin — a point the caller never named and something is usually
  // drawn at.
  func testAMarkerWithNoFrameIsRefusedRatherThanResolvedToTheOrigin() async throws {
    do {
      _ = try await Self.framedReader(child: nil).writeTarget(for: Self.marker, operation: "A tap")
      XCTFail("an element with no usable frame must not resolve a point to write to")
    } catch let error as FBUIAutomationError {
      guard case let .elementNotOnScreen(_, key, value) = error else {
        return XCTFail("expected elementNotOnScreen, got \(error)")
      }
      XCTAssertEqual(key, "AXLabel")
      XCTAssertEqual(value, "General")
    }
  }

  // MARK: - The caller's own pre-write assertion

  func testACallerAssertionThatMatchesLetsAMarkerWriteThrough() async throws {
    let target = try await Self.framedReader().writeTarget(
      for: Self.marker,
      operation: "A tap",
      callerAssertion: FBTapOptions.Assertion(key: .label, value: "General Settings")
    )
    XCTAssertEqual(target.point, CGPoint(x: Self.childRect.midX, y: Self.childRect.midY))
  }

  // The caller's assertion is an equality check on the value they named, and it is reported with both
  // sides — unlike the derived one, the host holds the actual value here and can say what it found.
  func testACallerAssertionThatDoesNotMatchRefusesTheWrite() async throws {
    do {
      _ = try await Self.framedReader().writeTarget(
        for: Self.marker,
        operation: "A tap",
        callerAssertion: FBTapOptions.Assertion(key: .label, value: "General")
      )
      XCTFail("a caller assertion that does not match must refuse the write")
    } catch let error as FBUIAutomationError {
      guard case let .valueMismatch(_, key, expected, actual) = error else {
        return XCTFail("expected valueMismatch, got \(error)")
      }
      XCTAssertEqual(key, "AXLabel")
      XCTAssertEqual(expected, "General")
      XCTAssertEqual(actual, "General Settings", "a substring is not a match for an equality assertion")
    }
  }

  // A coordinate carries no value, so honouring a caller's assertion on one costs the read a bare point
  // write does not do — and it must actually be done rather than skipped for being inconvenient.
  func testACallerAssertionOnAPointReadsTheElementFirst() async throws {
    var hit = FBAccessibilityDocumentElement()
    hit.label = .some("Wi-Fi")
    let reader = StubTreeReader(
      read: Self.stubRead(), hitTestResult: FBAccessibilityElementsResponse(elements: .single(hit))
    )
    do {
      _ = try await reader.writeTarget(
        for: .point(CGPoint(x: 5, y: 6)),
        operation: "A tap",
        callerAssertion: FBTapOptions.Assertion(key: .label, value: "General")
      )
      XCTFail("a caller assertion on a point must be checked against the element there")
    } catch let error as FBUIAutomationError {
      guard case let .valueMismatch(_, _, expected, actual) = error else {
        return XCTFail("expected valueMismatch, got \(error)")
      }
      XCTAssertEqual(expected, "General")
      XCTAssertEqual(actual, "Wi-Fi")
    }
    XCTAssertEqual(reader.hitTestPoints, [CGPoint(x: 5, y: 6)], "the assertion must be read at the point being written to")
  }

  func testACallerAssertionOnAnEmptyPointReportsTheEmptyPoint() async throws {
    let reader = StubTreeReader(read: Self.stubRead(), hitTestResult: nil)
    do {
      _ = try await reader.writeTarget(
        for: .point(CGPoint(x: 5, y: 6)),
        operation: "A tap",
        callerAssertion: FBTapOptions.Assertion(key: .label, value: "General")
      )
      XCTFail("expected noElementAtPoint to be thrown")
    } catch let error as FBUIAutomationError {
      guard case .noElementAtPoint = error else {
        return XCTFail("expected noElementAtPoint, got \(error)")
      }
    }
  }

  // MARK: - An unoccupied write target

  // The guest answers an unoccupied point the same way whichever query sent the write there, so the
  // error has to be chosen from what the caller named rather than from what the guest was sent.

  // A marker write reports its element as moved — the same condition, and the same error, as the guest
  // finding a *different* element under the point. Both are the screen changing between the read that
  // resolved the marker and the write that acted on it.
  func testAnEmptyTargetIsReportedAsAMovedElementForAMarker() {
    let error = Self.framedReader().emptyWriteTargetError(for: Self.marker, at: CGPoint(x: 195, y: 122))
    guard case let .elementMoved(_, key, value) = error else {
      return XCTFail("expected elementMoved, got \(error)")
    }
    XCTAssertEqual(key, "AXLabel")
    XCTAssertEqual(value, "General")
    XCTAssertFalse(error.description.contains("195"), "a marker caller never chose a coordinate: \(error.description)")
  }

  // Only a caller who named a coordinate is told about a coordinate.
  func testAnEmptyTargetIsReportedAsAnEmptyPointForAPoint() {
    let error = Self.framedReader().emptyWriteTargetError(
      for: .point(CGPoint(x: 12, y: 34)), at: CGPoint(x: 12, y: 34)
    )
    guard case let .noElementAtPoint(_, x, y) = error else {
      return XCTFail("expected noElementAtPoint, got \(error)")
    }
    XCTAssertEqual(x, 12)
    XCTAssertEqual(y, 34)
  }

  // MARK: - Write envelope parsing

  func testAWriteEnvelopeReportsWhetherItLanded() throws {
    XCTAssertTrue(try FBAXTreeRead.writeLanded(fromResponse: Self.json(["ok": true, "pid": 4321])))
    XCTAssertFalse(
      try FBAXTreeRead.writeLanded(fromResponse: Self.json(["ok": true, "empty": true])),
      "writeLanded is false for an ok response carrying empty"
    )
  }

  // A refused assertion is its own condition all the way up: the guest knows what it found under the
  // point, and only the host knows which marker sent the write there, so the two are joined at the
  // backend rather than collapsing into an opaque failure here.
  func testARefusedAssertionParsesAsItsOwnFailure() throws {
    do {
      _ = try FBAXTreeRead.writeLanded(
        fromResponse: Self.json([
          "ok": false, "error": "the element at (1.0, 2.0) has XC_kAXXCAttributeLabel Wi-Fi, expected General",
          "error_kind": "assertion_failed",
        ])
      )
      XCTFail("a refused write must throw")
    } catch let error as FBAXBridgeError {
      guard case let .assertionFailed(message) = error else {
        return XCTFail("expected assertionFailed, got \(error)")
      }
      XCTAssertTrue(message.contains("expected General"), message)
    }
  }

  // A write meets the same application conditions a read does, and classifies them the same way — that
  // is the whole reason the write envelope is parsed beside the read envelopes.
  func testAWriteClassifiesApplicationFailuresLikeARead() throws {
    let cases: [(String, (FBAXBridgeError) -> Bool)] = [
      ("application_unavailable", { if case .applicationUnavailable = $0 { true } else { false } }),
      ("application_not_responding", { if case .applicationNotResponding = $0 { true } else { false } }),
      ("bad_request", { if case .guestFailure = $0 { true } else { false } }),
      ("reader_unavailable", { if case .readerUnavailable = $0 { true } else { false } }),
    ]
    for (kind, matches) in cases {
      do {
        _ = try FBAXTreeRead.writeLanded(
          fromResponse: Self.json(["ok": false, "error": "no", "error_kind": kind, "pid": 4321])
        )
        XCTFail("\(kind) must throw")
      } catch let error as FBAXBridgeError {
        XCTAssertTrue(matches(error), "\(kind) classified as \(error)")
      }
    }
  }

  func testAnUnparseableWriteEnvelopeIsAGuestFailure() throws {
    XCTAssertThrowsError(try FBAXTreeRead.writeLanded(fromResponse: Data("not json".utf8)))
  }

  // Every other message opens with the backend's name, so `displayName` is capitalised and ends in
  // "backend"; this one names it part-way through a sentence, where both of those read as a stutter.
  func testAnUnsupportedOperationNamesTheBackendOnceAndInLowerCase() {
    let backends: [FBUIAutomationBackend] = [
      .accessibility, .remoteAutomation, .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint, automationMode: true),
    ]
    for backend in backends {
      let description = FBUIAutomationError.operationUnsupported(backend: backend, operation: "Scroll").description
      XCTAssertFalse(description.contains("the The"), description)
      XCTAssertFalse(description.contains("backend backend"), description)
      XCTAssertTrue(description.hasSuffix(backend.inlineName), description)
    }
    XCTAssertEqual(
      FBUIAutomationError.operationUnsupported(
        backend: .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint, automationMode: true), operation: "Scroll"
      ).description,
      "Scroll is not supported over the axbridge backend"
    )
  }

  private static func json(_ object: [String: Any]) throws -> Data {
    try JSONSerialization.data(withJSONObject: object)
  }
}

/// Choosing a traversal per read.
final class FBAXTraversalStrategyTests: XCTestCase {

  // A caller who names no traversal is asking the backend to choose, so `auto` must name no traversal
  // of its own. What each backend chooses is asserted in `FBAXAutoTraversalTests`.
  func testARequestThatNamesNoTraversalLeavesTheChoiceToTheBackend() {
    XCTAssertEqual(FBAccessibilityRequestOptions().traversalStrategy, .auto)
    XCTAssertNil(FBAXTraversalStrategy.auto.traversal, "`auto` must name no traversal of its own")
  }

  // The other three name a traversal outright, and the resolution has to hand back the one named rather
  // than a backend's preference — otherwise `--traversal` would be advisory.
  func testANamedStrategyResolvesToItself() {
    for traversal in FBAXTraversal.allCases {
      XCTAssertEqual(FBAXTraversalStrategy(rawValue: traversal.rawValue)?.traversal, traversal)
    }
  }

  // The structural traversal answers everything; nothing a caller asks for is unsatisfiable on its
  // account, so it must never produce a warning.
  func testTheViewHierarchyCanAnswerEveryKey() {
    XCTAssertTrue(FBAXTraversal.viewHierarchy.unsatisfiableKeys.isEmpty)
    let options = FBAccessibilityRequestOptions(keys: Set(FBAXKeys.allCases), traversalStrategy: .viewHierarchy)
    XCTAssertTrue(options.unsatisfiableKeys(for: .viewHierarchy).isEmpty)
  }

  // The semantic traversal answers `type` from the translator's own role numbering, and only the roles
  // identified so far map onto a name — so it answers for most elements and not for all. The key stays
  // listed because the contract is about what a traversal can answer for *every* element: a caller
  // holding a node with no type has to be able to tell "the app set none" from "this read could not ask".
  func testSemanticCannotTypeEveryElement() {
    XCTAssertEqual(FBAXTraversal.semantic.unsatisfiableKeys, [.type])
  }

  // Only keys the read actually asked for are reported. A caller that never wanted the type should not
  // be warned about it.
  func testOnlyRequestedKeysAreReportedUnsatisfiable() {
    let asking = FBAccessibilityRequestOptions(keys: [.type, .label], traversalStrategy: .semantic)
    XCTAssertEqual(asking.unsatisfiableKeys(for: .semantic), [.type])

    let notAsking = FBAccessibilityRequestOptions(keys: [.label], traversalStrategy: .semantic)
    XCTAssertTrue(
      notAsking.unsatisfiableKeys(for: .semantic).isEmpty,
      "a caller that did not ask for the type must not be warned about it, "
        + "got \(notAsking.unsatisfiableKeys(for: .semantic))"
    )
  }

}

/// What each backend reads when the caller named no traversal.
///
/// Asserted against the real backends rather than `StubTreeReader`: these pins exist to catch a change
/// to a backend's own default, and a stub agreeing with itself proves nothing about either backend. Both
/// are reachable without a simulator: the resolution is static precisely so a backend can be asked what
/// it reads without standing up something to read from.
final class FBAXAutoTraversalTests: XCTestCase {

  // FBAXBridgeUIAutomation takes the whole tree in one fetch for a read that named nothing, and falls
  // back to the per-node walk for one asking about reachability — the only key set the application has
  // to hit-test.
  func testAxbridgeReadsInOneFetchWhenTheCallerNamesNothing() {
    XCTAssertEqual(FBAXBridgeUIAutomation.autoTraversal(for: FBAccessibilityRequestOptions()), .singleFetch)
    XCTAssertEqual(
      FBAXBridgeUIAutomation.autoTraversal(for: FBAccessibilityRequestOptions(keys: [.interactable, .occludedBy])),
      .viewHierarchy
    )
  }

  // A default read asks the guest for a snapshot over either transport — the guest reads one request
  // whichever one carried it, and a default that snapshots over argv but walks over the socket would be
  // a read whose cost depends on how the host happened to connect.
  func testADefaultGuestReadAsksTheGuestForASnapshot() {
    let traversal = FBAXBridgeUIAutomation.autoTraversal(for: FBAccessibilityRequestOptions())
    XCTAssertEqual(FBAXBridgeOneshotTransport.traversalArgument(traversal), ["--snapshot-tree", "1"])
    XCTAssertEqual(
      FBAXBridgePersistentTransport.adding(
        attributes: nil, explainUnreachable: false, traversal: traversal, automationMode: nil, to: [:]
      ) as NSDictionary,
      ["snapshotTree": true] as NSDictionary
    )
  }

  // The same wire pin for a reachability read: it resolves to the walk, so its argv and payload stay
  // empty.
  func testAReachabilityReadAsksTheGuestForNoSnapshot() {
    let traversal = FBAXBridgeUIAutomation.autoTraversal(for: FBAccessibilityRequestOptions(keys: [.interactable]))
    XCTAssertEqual(FBAXBridgeOneshotTransport.traversalArgument(traversal), [])
    XCTAssertTrue(
      FBAXBridgePersistentTransport.adding(
        attributes: nil, explainUnreachable: false, traversal: traversal, automationMode: nil, to: [:]
      ).isEmpty)
  }

  // The explicit single fetch is pinned in its own right, not only as today's default, so its argv and
  // payload stay asserted if the default ever moves again.
  func testTheSingleFetchAsksTheGuestForASnapshot() {
    XCTAssertEqual(FBAXBridgeOneshotTransport.traversalArgument(.singleFetch), ["--snapshot-tree", "1"])
    XCTAssertEqual(
      FBAXBridgePersistentTransport.adding(
        attributes: nil, explainUnreachable: false, traversal: .singleFetch, automationMode: nil, to: [:]
      ) as NSDictionary,
      ["snapshotTree": true] as NSDictionary
    )
  }

  // FBSimulatorRemoteAutomation serves one snapshot shape and its read takes no traversal into account
  // at all, so its answer cannot depend on the key set — and it has no argv of its own to pin.
  func testRemoteAutomationWalksPerNodeForEveryKeySet() {
    XCTAssertEqual(FBSimulatorRemoteAutomation.autoTraversal(for: FBAccessibilityRequestOptions()), .viewHierarchy)
    XCTAssertEqual(
      FBSimulatorRemoteAutomation.autoTraversal(for: FBAccessibilityRequestOptions(keys: Set(FBAXKeys.allCases))),
      .viewHierarchy
    )
  }

  // A named traversal reaches the read unchanged. Pinned against the real backends rather than the
  // strategy's own resolution test: an explicit `--traversal view-hierarchy` must keep selecting the
  // walk after the default changes.
  func testANamedTraversalOverridesTheBackendDefault() {
    for traversal in FBAXTraversal.allCases {
      guard let strategy = FBAXTraversalStrategy(rawValue: traversal.rawValue) else {
        return XCTFail("no strategy names \(traversal)")
      }
      let options = FBAccessibilityRequestOptions(traversalStrategy: strategy)
      XCTAssertEqual(FBAXBridgeUIAutomation.resolvedTraversal(for: options), traversal)
      XCTAssertEqual(FBSimulatorRemoteAutomation.resolvedTraversal(for: options), traversal)
    }
  }
}

/// What the transport tells a caller when the in-guest reader disappears mid-request.
///
/// EOF on the serve socket is noticed immediately — that part works — so what is worth covering is the
/// *content* of the message, which is the part a caller debugs from.
final class FBAXBridgeGuestDeathTests: XCTestCase {

  // The motivating case: a guest killed by the system. The signal points at the environment rather
  // than at whatever change the caller happens to be testing.
  func testAKilledGuestIsReportedWithItsSignal() {
    let message = FBAXBridgeConnection.socketClosedMessage(pid: 4321, signal: 9, exitCode: nil)
    XCTAssertTrue(message.contains("killed by signal 9"), message)
    XCTAssertTrue(message.contains("pid 4321"), message)
  }

  func testAGuestThatExitedIsReportedWithItsCode() {
    let message = FBAXBridgeConnection.socketClosedMessage(pid: 4321, signal: nil, exitCode: 3)
    XCTAssertTrue(message.contains("exited with code 3"), message)
  }

  // A signalled exit wins over an exit code, because it names something outside the reader as the cause
  // and that is the more actionable of the two.
  func testASignalTakesPrecedenceOverAnExitCode() {
    let message = FBAXBridgeConnection.socketClosedMessage(pid: 4321, signal: 9, exitCode: 0)
    XCTAssertTrue(message.contains("killed by signal 9"), message)
    XCTAssertFalse(message.contains("exited with code"), message)
  }

  // Exit code 0 with no signal is still a death worth reporting — the guest is gone either way, and
  // "exited cleanly" is a different problem from "was killed", which is the whole point of saying which.
  func testACleanExitIsStillReported() {
    XCTAssertTrue(
      FBAXBridgeConnection.socketClosedMessage(pid: 4321, signal: 0, exitCode: 0).contains("exited with code 0")
    )
  }

  // Nothing to consult, nothing added: a caller is told what is true and no more.
  func testSocketClosedMessageOmitsDetailWhenPidAndStatusUnknown() {
    XCTAssertEqual(
      FBAXBridgeConnection.socketClosedMessage(pid: nil, signal: nil, exitCode: nil),
      "serve socket closed by peer"
    )
    XCTAssertEqual(FBAXBridgeConnection.socketClosedMessage(process: nil), "serve socket closed by peer")
  }

  // A process whose exit status never resolved is still named, rather than the message pretending it
  // knows or the read stalling to find out.
  func testAGuestWithNoRecordedStatusIsStillNamed() {
    let message = FBAXBridgeConnection.socketClosedMessage(pid: 4321, signal: nil, exitCode: nil)
    XCTAssertTrue(message.contains("no exit status recorded"), message)
    XCTAssertTrue(message.contains("pid 4321"), message)
  }
}

/// A minimal `FBAXTreeReader` serving a canned read, so the shared `describeTree` composition can be
/// observed without a simulator. `readRawTree`, `warnIfTruncated`, `warnIfMostElementsUnframed` and `hitTest`
/// are the seams
/// `describeTree` drives; every other `FBUIAutomation` verb is an unused conformance stub.
private final class StubTreeReader: FBAXTreeReader, @unchecked Sendable {

  let backend: FBUIAutomationBackend = .axBridge(persistence: .oneShot, frontmostMethod: .centerPoint, automationMode: true)

  private let read: FBAXTreeRead
  private let hitTestResult: FBAccessibilityElementsResponse?

  private(set) var readCount = 0
  /// The attribute list each read was asked for — how a test asserts that requesting a key put its
  /// attributes on the wire, and that not requesting it left them off.
  private(set) var readAttributes: [[String]?] = []
  /// Whether each read asked the guest to explain its unreachable elements — how a test asserts that the
  /// cost is only incurred when the key that needs it was requested.
  private(set) var explainRequests: [Bool] = []
  private(set) var truncationWarnings: [Bool] = []
  /// The traversal each read was performed with — how a test asserts a caller's choice reached the wire,
  /// and what an unchosen one resolved to.
  private(set) var traversals: [FBAXTraversal] = []
  /// The traversal each profile was built for, so a test can assert the profile is told the same thing
  /// the read was rather than working it out for itself.
  private(set) var profiledTraversals: [FBAXTraversal] = []
  /// The keys each read reported it could not answer.
  private(set) var unsatisfiableWarnings: [Set<FBAXKeys>] = []
  private(set) var hitTestPoints: [CGPoint] = []

  init(read: FBAXTreeRead, hitTestResult: FBAccessibilityElementsResponse? = nil) {
    self.read = read
    self.hitTestResult = hitTestResult
  }

  func readRawTree(
    for query: FBAccessibilityElementQuery,
    attributes: [String]?,
    explainUnreachable: Bool,
    traversal: FBAXTraversal
  ) async throws -> FBAXTreeRead {
    readCount += 1
    readAttributes.append(attributes)
    explainRequests.append(explainUnreachable)
    traversals.append(traversal)
    return read
  }

  static func autoTraversal(for options: FBAccessibilityRequestOptions) -> FBAXTraversal {
    .viewHierarchy
  }

  func warnIfUnsatisfiable(_ keys: Set<FBAXKeys>, traversal: FBAXTraversal) async {
    unsatisfiableWarnings.append(keys)
  }

  func profile(
    for read: FBAXTreeRead, elementCount: Int, serializeDuration: CFAbsoluteTime,
    traversal: FBAXTraversal
  ) -> FBAccessibilityProfile? {
    profiledTraversals.append(traversal)
    return .guestBridge(
      FBAXBridgeProfile(
        elementCount: Int64(elementCount), totalDuration: 0, acquireDuration: 0, readDuration: 0,
        serializeDuration: serializeDuration, traversal: traversal
      ))
  }

  /// Records the key set of any read that would have warned about per-node hit-testing.
  private(set) var reachabilityWarnings: [Set<FBAXKeys>] = []

  func warnIfReachabilityAcrossTree(_ keys: Set<FBAXKeys>) async {
    if keys.contains(.interactable) || keys.contains(.occludedBy) {
      reachabilityWarnings.append(keys)
    }
  }

  func warnIfTruncated(_ truncated: Bool) async {
    truncationWarnings.append(truncated)
  }

  private(set) var geometryWarnings: [FBAccessibilityFrameSummary?] = []

  func warnIfMostElementsUnframed(_ frames: FBAccessibilityFrameSummary?) async {
    geometryWarnings.append(frames)
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

  func drag(
    from source: FBAccessibilityElementQuery, to destination: FBAccessibilityElementQuery, options: FBDragOptions
  ) async throws {}
}

/// The composition of the key vocabulary's derived sets.
final class FBAXKeySetTests: XCTestCase {

  // Derived from `allCases`, so a new key joins `everything` automatically.
  func testEverythingIsEveryKey() {
    XCTAssertEqual(FBAXKeys.everything, Set(FBAXKeys.allCases))
    XCTAssertTrue(FBAXKeys.everything.isSuperset(of: FBAXKeys.defaultSet))
  }

  // The expensive keys are included deliberately: a caller asking for everything is asking for the
  // fields that cost extra guest work.
  func testEverythingIncludesTheKeysThatCostExtraGuestWork() {
    XCTAssertTrue(FBAXKeys.everything.contains(.interactable))
    XCTAssertTrue(FBAXKeys.everything.contains(.occludedBy))
  }
}
