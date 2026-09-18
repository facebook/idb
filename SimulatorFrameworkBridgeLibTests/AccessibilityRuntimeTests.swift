/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation
@_implementationOnly import SimulatorFrameworkBridgeLib
import XCTest

private let kAXElementType = "XC_kAXXCAttributeElementType"
private let kAXLabel = "XC_kAXXCAttributeLabel"
private let kAXChildren = "XC_kAXXCAttributeChildren"
private let kAXFrame = "XC_kAXXCAttributeFrame"
private let kAXVisiblePoint = "XC_kAXXCAttributeVisiblePoint"
private let kNodeIsEnabled = "FBIsEnabled"
private let kNodeTranslatorRole = "FBTranslatorRole"

// The pid every test that needs a readable application uses. Arbitrary, but a plausible one — nothing in
// the reader treats any particular value specially beyond the non-positive rejection.
private let kAppPid: pid_t = 4321

private func FBAXTestsErrorWithCode(_ code: Int32) -> NSError {
  return NSError(domain: "XCTAutomationErrorDomain", code: 1, userInfo: [FBAXAccessibilityErrorKey: NSNumber(value: code), NSLocalizedDescriptionKey: "runtime said no"])
}

/**
 * Drives `FBAXBridgeHandleRequest` against a fake `FBAXRuntime`, reaching outcomes a real simulator only
 * produces against a dead, mid-launch or SIGSTOP-ed application.
 */
final class AccessibilityRuntimeTests: XCTestCase {
  private var runtime: FBAXFakeRuntime!

  override func setUp() {
    super.setUp()
    runtime = FBAXFakeRuntime()
    FBAXBridgeSetRuntimeForTesting(runtime)
  }

  override func tearDown() {
    // The substitution is process-wide, so leaving it set would leak into every other test in the bundle.
    FBAXBridgeSetRuntimeForTesting(nil)
    runtime = nil
    super.tearDown()
  }

  // MARK: - Encoding normalisation

  func testTypesOnlyDropsOffsetsAndKeepsTypes() {
    let examples = [
      // Already normalised: nothing to drop.
      "v@:": "v@:",
      "Q@:": "Q@:",
      // The common case — a return, self, selector and their offsets.
      "Q16@0:8": "Q@:",
      "@24@0:8Q16": "@@:Q",
      "v24@0:8@16": "v@:@",
      // Blocks, out-parameters, const char * and bare pointers keep their punctuation.
      "v32@0:8@?24": "v@:@?",
      "@40@0:8@16^@24@32": "@@:@^@@",
      "@24@0:8r*16": "@@:r*",
      // A pointer to an opaque struct — the shape `AXUIElementRef` arrives as.
      "^{__AXUIElement=}16@0:8": "^{__AXUIElement=}@:",
      // Digits inside an aggregate are part of the type and survive; the frame numbers around them do not.
      "{FBAXQuad=[4i]}32@0:8{FBAXPair=ii}16": "{FBAXQuad=[4i]}@:{FBAXPair=ii}",
      "[8i]16@0:8": "[8i]@:",
      "(u=i[2c])16@0:8": "(u=i[2c])@:",
      // Nested aggregates: the depth counter has to come back to zero before dropping resumes.
      "{a={b=[4i]}}24@0:8i16": "{a={b=[4i]}}@:i",
      // The empty encoding is not a crash.
      "": "",
    ]
    for encoding in examples.keys {
      assertEqualObjects(FBAXTypesOnly(encoding), axValue(examples, encoding), "normalising \(String(describing: encoding))")
    }
  }

  // The table in the runtime may be written with or without offsets.
  func testTypesOnlyMakesRuntimeAndHandWrittenEncodingsAgree() throws {
    let length = try XCTUnwrap(class_getInstanceMethod(NSString.self, #selector(getter: NSString.length)))
    assertEqualObjects(FBAXTypesOnly(try XCTUnwrap(method_getTypeEncoding(length))), FBAXTypesOnly("Q@:"))

    let objectAtIndex = try XCTUnwrap(class_getInstanceMethod(NSArray.self, #selector(NSArray.object(at:))))
    assertEqualObjects(FBAXTypesOnly(try XCTUnwrap(method_getTypeEncoding(objectAtIndex))), FBAXTypesOnly("@@:Q"))
  }

  func testTypesOnlyIsIdempotent() {
    for encoding in ["Q16@0:8", "{FBAXQuad=[4i]}32@0:8{FBAXPair=ii}16", "v32@0:8@?24"] {
      let once = FBAXTypesOnly(encoding)
      assertEqualObjects(FBAXTypesOnly(once), once, "normalising \(String(describing: encoding)) twice")
    }
  }

  // MARK: - Bound signature checking

  // Runs against the guest's copies of the frameworks; a shape that moved only inside an iOS runtime
  // image would pass against the host's.
  func testEveryBoundSignatureAgreesWithTheRuntime() {
    let warnings = FBAXSignatureWarnings()
    assertEqualObjects(warnings, [], "\(String(describing: warnings.joined(separator: "\n")))")
  }

  func testSignatureAgreesWithTheRuntime() {
    XCTAssertNil(FBAXSignatureMismatch("NSString", "length", false, "Q@:"))
    XCTAssertNil(FBAXSignatureMismatch("NSString", "stringWithUTF8String:", true, "@@:r*"))
    XCTAssertNil(FBAXSignatureMismatch("NSArray", "objectAtIndex:", false, "@@:Q"))
  }

  // Offsets differ by ABI, so the check must not fire on them.
  func testSignatureIgnoresFrameSizesAndOffsets() {
    XCTAssertNil(FBAXSignatureMismatch("NSString", "length", false, "Q16@0:8"))
    XCTAssertNil(FBAXSignatureMismatch("NSArray", "objectAtIndex:", false, "@24@0:8Q16"))
  }

  func testSignatureKeepsDigitsInsideAggregateEncodings() {
    XCTAssertNil(FBAXSignatureMismatch("FBAXSignatureProbe", "quadFromPair:", false, "{FBAXQuad=[4i]}@:{FBAXPair=ii}"))

    let mismatch = FBAXSignatureMismatch("FBAXSignatureProbe", "quadFromPair:", false, "{FBAXQuad=[8i]}@:{FBAXPair=ii}")
    XCTAssertNotNil(mismatch, "an array length inside the struct is a different type and must not be dropped")
  }

  func testSignatureMismatchNamesWhatItFoundAndWhatItAssumed() {
    let mismatch = FBAXSignatureMismatch("NSString", "length", false, "i@:")
    XCTAssertNotNil(mismatch)
    XCTAssertTrue(((mismatch)?.contains("-[NSString length]") == true), "\(String(describing: mismatch))")
    XCTAssertTrue(((mismatch)?.contains("Q@:") == true), "the encoding found must be named: \(String(describing: mismatch))")
    XCTAssertTrue(((mismatch)?.contains("i@:") == true), "the encoding assumed must be named: \(String(describing: mismatch))")
  }

  func testSignatureMismatchReportedForMissingClassOrSelector() {
    let absentClass = FBAXSignatureMismatch("FBAXNoSuchClass", "length", false, "Q@:")
    XCTAssertNotNil(absentClass)
    XCTAssertTrue(((absentClass)?.contains("FBAXNoSuchClass") == true), "\(String(describing: absentClass))")

    XCTAssertNotNil(FBAXSignatureMismatch("NSString", "fbaxNoSuchSelector", false, "Q@:"))
  }

  func testSignatureDistinguishesClassFromInstanceMethods() {
    XCTAssertNotNil(FBAXSignatureMismatch("NSString", "length", true, "Q@:"))
    XCTAssertNotNil(FBAXSignatureMismatch("NSString", "stringWithUTF8String:", false, "@@:r*"))
  }

  // MARK: - Read-error classification

  // Too broad and a reader bug reads as "the app isn't there"; too narrow and a dead app is an untyped error.
  func testEachActionableAXCodeClassifiesAsItsOwnCondition() {
    let unavailable = FBAXReadOutcome.failure(forAttributeError: FBAXTestsErrorWithCode(FBAXError.serverNotFound.rawValue))
    XCTAssertEqual(unavailable.status, FBAXReadStatus.applicationUnavailable)

    let notResponding = FBAXReadOutcome.failure(forAttributeError: FBAXTestsErrorWithCode(FBAXError.ipcTimeout.rawValue))
    XCTAssertEqual(notResponding.status, FBAXReadStatus.applicationNotResponding, "an IPC timeout classifies as application-not-responding, not unavailable")

    for code in [NSNumber(value: FBAXError.invalidUIElement.rawValue), NSNumber(value: FBAXError.success.rawValue), NSNumber(value: -1)] {
      let outcome = FBAXReadOutcome.failure(forAttributeError: FBAXTestsErrorWithCode(code.int32Value))
      XCTAssertEqual(outcome.status, FBAXReadStatus.failed, "AX code \(String(describing: code)) must stay an opaque failure")
    }
  }

  // `nil` reaches the classifier whenever the runtime returns false without populating the out-parameter.
  func testErrorWithoutAnAccessibilityCodeIsAPlainFailure() {
    XCTAssertEqual(FBAXReadOutcome.failure(forAttributeError: nil).status, FBAXReadStatus.failed)

    let foreign = NSError(domain: NSCocoaErrorDomain, code: -25215, userInfo: nil)
    let outcome = FBAXReadOutcome.failure(forAttributeError: foreign)
    XCTAssertEqual(outcome.status, FBAXReadStatus.failed, "the code must be read from the userInfo, not the NSError code")
  }

  // MARK: - Hit-test outcomes

  func testHitTestErrorClassification() {
    XCTAssertNil(FBAXHitTestOutcome(forHitTestError: FBAXError.success.rawValue, hasElement: true), "success with an element returns nil; the caller wraps the element")
    // Success with no element out is still nothing at the point, not a contradiction to report.
    XCTAssertEqual(FBAXHitTestOutcome(forHitTestError: FBAXError.success.rawValue, hasElement: false)?.status, FBAXHitTestStatus.empty)
    XCTAssertEqual(FBAXHitTestOutcome(forHitTestError: FBAXError.serverNotFound.rawValue, hasElement: false)?.status, FBAXHitTestStatus.applicationUnavailable, "server-not-found classifies as application-unavailable, not empty")
    XCTAssertEqual(FBAXHitTestOutcome(forHitTestError: FBAXError.invalidUIElement.rawValue, hasElement: false)?.status, FBAXHitTestStatus.empty, "a genuinely empty point")
    XCTAssertEqual(FBAXHitTestOutcome(forHitTestError: FBAXError.ipcTimeout.rawValue, hasElement: false)?.status, FBAXHitTestStatus.applicationNotResponding, "an IPC timeout classifies as application-not-responding, not empty or unavailable")
  }

  func testHitOnASeededPointAnswersWithTheElementAndItsOwningPid() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("XCUIElementTypeButton"), owningProcessIdentifier: kAppPid)

    let response = FBAXBridgeHandleRequest(["verb": "hittest", "pid": NSNumber(value: kAppPid), "x": NSNumber(value: 10), "y": NSNumber(value: 20)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid))
    assertEqualObjects(axValue(axValue(response, "tree"), kAXElementType), "XCUIElementTypeButton")
    XCTAssertEqual(runtime.lastHitTestProcessIdentifier, kAppPid, "an explicit pid must scope the hit-test")
    XCTAssertEqual(runtime.lastHitTestPoint.x, 10)
    XCTAssertEqual(runtime.lastHitTestPoint.y, 20)
  }

  func testHitWithNoPidIsDisplayWideAndReportsTheOwningPid() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("XCUIElementTypeCell"), owningProcessIdentifier: 99)

    let response = FBAXBridgeHandleRequest(["verb": "hittest", "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: 99), "the owning pid must come from the outcome")
    XCTAssertEqual(runtime.lastHitTestProcessIdentifier, 0, "no pid means a display-wide hit-test")
  }

  func testEmptyPointIsASuccessfulEmptyResult() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.empty()

    let response = FBAXBridgeHandleRequest(["verb": "hittest", "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "empty"), NSNumber(value: true))
    XCTAssertNil(axValue(response, "tree"))
    XCTAssertNil(axValue(response, "error"))
  }

  func testUnavailableApplicationIsTaggedAndNamesThePidWhenSeeded() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.applicationUnavailable()

    let seeded = FBAXBridgeHandleRequest(["verb": "hittest", "pid": NSNumber(value: kAppPid), "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(seeded, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(seeded, "error_kind"), "application_unavailable")
    assertEqualObjects(axValue(seeded, "error"), "pid 4321 has no accessibility server to hit-test")

    assertEqualObjects(axValue(seeded, "pid"), NSNumber(value: kAppPid), "a tagged failure names the process it is about")

    let systemWide = FBAXBridgeHandleRequest(["verb": "hittest", "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(systemWide, "error_kind"), "application_unavailable")
    assertEqualObjects(axValue(systemWide, "error"), "no accessibility server answered the system-wide hit-test")
    XCTAssertNil(axValue(systemWide, "pid"), "a display-wide hit-test nothing answered has no process to name")
  }

  func testNotRespondingAndUnavailableProduceDistinctErrorKinds() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.applicationNotResponding()

    let seeded = FBAXBridgeHandleRequest(["verb": "hittest", "pid": NSNumber(value: kAppPid), "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(seeded, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(seeded, "error_kind"), "application_not_responding")
    assertEqualObjects(axValue(seeded, "error"), "pid 4321 did not answer the hit-test in time")
    assertEqualObjects(axValue(seeded, "pid"), NSNumber(value: kAppPid))

    let systemWide = FBAXBridgeHandleRequest(["verb": "hittest", "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(systemWide, "error_kind"), "application_not_responding")
    assertEqualObjects(axValue(systemWide, "error"), "the application at the hit-test point did not answer in time")
    XCTAssertNil(axValue(systemWide, "empty"), "empty must not be set on a not-responding response")
  }

  func testFailedHitTestIsAnOpaqueFailureCarryingTheReason() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.failed("AXUIElementCreateSystemWide returned NULL")

    let response = FBAXBridgeHandleRequest(["verb": "hittest", "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error"), "AXUIElementCreateSystemWide returned NULL")
    XCTAssertNil(axValue(response, "error_kind"), "a reader failure must not be tagged as an unavailable application")
  }

  func testHitElementThatCannotBeReadIsReportedFromTheReadOutcome() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.applicationUnavailable(), owningProcessIdentifier: kAppPid)
    let unavailable = FBAXBridgeHandleRequest(["verb": "hittest", "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(unavailable, "error_kind"), "application_unavailable")
    assertEqualObjects(axValue(unavailable, "error"), "pid 4321 has no accessibility server")
    assertEqualObjects(axValue(unavailable, "pid"), NSNumber(value: kAppPid), "the pid the hit-test attributed it to is still named")

    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.applicationNotResponding(), owningProcessIdentifier: kAppPid)
    let notResponding = FBAXBridgeHandleRequest(["verb": "hittest", "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(notResponding, "error_kind"), "application_not_responding")
    assertEqualObjects(axValue(notResponding, "error"), "pid 4321 did not answer the read of the hit element in time")

    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.failed(FBAXTestsErrorWithCode(FBAXError.invalidUIElement.rawValue)), owningProcessIdentifier: kAppPid)
    let failed = FBAXBridgeHandleRequest(["verb": "hittest", "x": NSNumber(value: 1), "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(failed, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(failed, "error"), "failed to read the hit element")
    XCTAssertNil(axValue(failed, "error_kind"))
  }

  // MARK: - The default frontmost method

  func testAFrontmostReadWithNoMethodAsksTheWindowServer() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.empty()
    runtime.windowServerOutcome = FBAXFrontmostOutcome.resolved(kAppPid)
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")

    let response = FBAXBridgeHandleRequest(["verb": "describe", "x": NSNumber(value: 201), "y": NSNumber(value: 437)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid))
    assertEqualObjects(axValue(response, "method"), "window-server", "the response names the resolver that ran")
    XCTAssertEqual(runtime.windowServerCount, 1)
    XCTAssertEqual(runtime.hitTestCount, 0, "the anchor is not consulted for the authoritative frontmost")
  }

  // MARK: - Raises while answering

  func testARaiseWhileAnsweringBecomesAResponseAndLeavesTheReaderAnswering() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.readRaiseReason = "the runtime went away mid-read"

    let raised = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    assertEqualObjects(axValue(raised, "ok"), NSNumber(value: false))
    XCTAssertTrue(((axValue(raised, "error") as? String)?.contains("the runtime went away mid-read") == true), "the response must carry what was raised: \(String(describing: axValue(raised, "error")))")

    // The point of answering rather than aborting: the next request is still served.
    runtime.readRaiseReason = nil
    let after = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    assertEqualObjects(axValue(after, "ok"), NSNumber(value: true), "the reader must still answer after a raise: \(String(describing: after))")
  }

  // MARK: - Request validation

  // Arguments are rejected after the runtime is reached, hence the fake.
  func testMalformedArgumentsAreReportedAsABadRequest() {
    let hitTest = FBAXBridgeHandleRequest(["verb": "hittest", "x": "left", "y": NSNumber(value: 2)])
    assertEqualObjects(axValue(hitTest, "error"), "hittest requires numeric x and y")
    assertEqualObjects(axValue(hitTest, "error_kind"), "bad_request")
    XCTAssertEqual(runtime.hitTestCount, 0, "a rejected request must not reach the runtime")

    let describe = FBAXBridgeHandleRequest(["verb": "describe"])
    assertEqualObjects(axValue(describe, "error"), "describe requires either a numeric pid or the frontmost anchor (x, y)")
    assertEqualObjects(axValue(describe, "error_kind"), "bad_request")
  }

  // MARK: - The single-fetch read

  // A fake element carrying `attributes`, with `children` beneath it.
  private func FBAXTestsNode(_ attributes: [String: Any], _ children: [FBAXFakeElement]) -> FBAXFakeElement {
    let element = FBAXFakeElement.readable("UIView")
    element.attributes = attributes
    element.children = children
    return element
  }

  private func FBAXTestsSnapshotRequest(_ extra: [String: Any]) -> [String: Any] {
    var request: [String: Any] =
      ["verb": "describe", "pid": NSNumber(value: kAppPid), "snapshotTree": NSNumber(value: true)]
    request.merge(extra) { _, new in new }
    return request
  }

  func testTheSingleFetchReadCostsOneRoundTripForTheWholeTree() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode(
      ["XC_kAXXCAttributeLabel": "root"],
      [FBAXTestsNode(["XC_kAXXCAttributeLabel": "a"], []), FBAXTestsNode(["XC_kAXXCAttributeLabel": "b"], [])]
    )

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true), "the single fetch must answer: \(String(describing: response))")
    XCTAssertEqual(runtime.snapshotCount, 1, "a three-node tree must cost exactly one fetch")
    assertEqualObjects(axValue(axValue(response, "phases"), "mach_round_trips"), NSNumber(value: 1))
  }

  // The fake numbers attributes differently from the runtime, so a hardcoded number would fail here.
  func testSnapshotAttributesAreMappedBackFromNumbersToNames() {
    runtime.applicationElements[NSNumber(value: kAppPid)] =
      FBAXTestsNode(["XC_kAXXCAttributeLabel": "Cancel", "XC_kAXXCAttributeIdentifier": "cancel-button"], [])

    let tree = axValue(FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:])), "tree")
    assertEqualObjects(axValue(tree, "XC_kAXXCAttributeLabel"), "Cancel")
    assertEqualObjects(axValue(tree, "XC_kAXXCAttributeIdentifier"), "cancel-button")
    XCTAssertTrue(((runtime.lastSnapshotAttributeNames as NSArray?)?.contains("XC_kAXXCAttributeLabel") == true), "the fetch must ask for the names the request resolved to, got: \(String(describing: runtime.lastSnapshotAttributeNames))")
  }

  // The snapshot also answers a children *attribute* of raw element references; only the nesting is usable.
  func testSnapshotChildrenComeFromTheNestingAndNotTheChildrenAttribute() {
    let child = FBAXTestsNode(["XC_kAXXCAttributeLabel": "child"], [])
    let root = FBAXTestsNode(
      ["XC_kAXXCAttributeLabel": "root", "XC_kAXXCAttributeChildren": ["a raw element reference"]],
      [child]
    )
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let tree = axValue(FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:])), "tree")
    let children = axValue(tree, "XC_kAXXCAttributeChildren")
    XCTAssertEqual(axCount(children), 1, "children must come from the nesting: \(String(describing: children))")
    assertEqualObjects(axValue((children as? NSArray)?.firstObject, "XC_kAXXCAttributeLabel"), "child")
  }

  // The pid of the process drawing a hosted subtree in the boundary tests below. Distinct from `kAppPid`
  // is all that matters: the boundary predicate is ownership changing, not any particular value.
  private var kRemotePid: pid_t { 8765 }

  // A tree in which another process draws a subtree — the shape of a web view's page, a photo picker or an
  // autofill sheet. The snapshot served by the host process names the boundary element and cannot
  // serialize beneath it; the per-node walk crosses because the server bridges each walked read.
  private func FBAXTestsTreeWithProcessBoundary() -> FBAXFakeElement {
    let link = FBAXTestsNode(["XC_kAXXCAttributeLabel": "Example Domain"], [])
    let page = FBAXTestsNode(["XC_kAXXCAttributeLabel": "web page"], [link])
    let boundary = FBAXTestsNode(["XC_kAXXCAttributeLabel": "remote element"], [page])
    let webView = FBAXTestsNode(["XC_kAXXCAttributeLabel": "web view"], [boundary])
    let root = FBAXTestsNode(["XC_kAXXCAttributeLabel": "root"], [webView])
    root.owningProcessIdentifier = kAppPid
    webView.owningProcessIdentifier = kAppPid
    boundary.owningProcessIdentifier = kRemotePid
    page.owningProcessIdentifier = kRemotePid
    link.owningProcessIdentifier = kRemotePid
    return root
  }

  // The boundary node in a single-fetch response of the tree above: root -> web view -> remote element.
  private func FBAXTestsBoundaryNode(_ response: [String: Any]) -> Any? {
    let webViews = axValue(axValue(response, "tree"), "XC_kAXXCAttributeChildren")
    return (axValue((webViews as? NSArray)?.firstObject, "XC_kAXXCAttributeChildren") as? NSArray)?.firstObject
  }

  // A snapshot stops where another process draws; the boundary arrives as a childless stub.
  func testTheSingleFetchReadContinuesAcrossAProcessBoundary() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsTreeWithProcessBoundary()

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true), "the read must answer: \(String(describing: response))")
    let boundary = FBAXTestsBoundaryNode(response)
    let hosted = axValue(boundary, "XC_kAXXCAttributeChildren")
    XCTAssertEqual(axCount(hosted), 1, "the hosted subtree must be beneath the boundary: \(String(describing: boundary))")
    assertEqualObjects(axValue((hosted as? NSArray)?.firstObject, "XC_kAXXCAttributeLabel"), "web page")
    XCTAssertEqual(runtime.snapshotCount, 2, "one fetch for the tree and one to continue across the boundary")
    assertEqualObjects(axValue(axValue(response, "phases"), "mach_round_trips"), NSNumber(value: 2))
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: false))
  }

  func testBothTraversalsAnswerTheSameDocumentAcrossAProcessBoundary() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsTreeWithProcessBoundary()

    let walked = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    let fetched = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(walked, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(fetched, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(walked, "tree"), axValue(fetched, "tree"))
  }

  func testAContinuationContinuesAcrossAFurtherBoundary() {
    let innermost = FBAXTestsNode(["XC_kAXXCAttributeLabel": "innermost"], [])
    innermost.owningProcessIdentifier = 111
    let root = FBAXTestsTreeWithProcessBoundary()
    let link = root.children[0].children[0].children[0].children[0]
    link.children = [innermost]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true), "the read must answer: \(String(describing: response))")
    XCTAssertEqual(runtime.snapshotCount, 3, "each boundary costs its own continuation")
    let rendered = String(describing: axValue(response, "tree"))
    XCTAssertTrue(((Optional(rendered))?.contains("innermost") == true), "the twice-hosted subtree must be in the tree: \(String(describing: rendered))")
  }

  func testAProcessBoundaryWhoseOwnerIsNotServingKeepsTheStub() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsTreeWithProcessBoundary()
    runtime.snapshotContinuationError = NSError(domain: "FBAXTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "the owner is not serving"])

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true), "a failed continuation must not fail the read: \(String(describing: response))")
    let boundary = FBAXTestsBoundaryNode(response)
    assertEqualObjects(axValue(boundary, "XC_kAXXCAttributeLabel"), "remote element")
    XCTAssertEqual(axCount(axValue(boundary, "XC_kAXXCAttributeChildren")), 0, "the stub stays childless: \(String(describing: boundary))")
    XCTAssertEqual(runtime.snapshotCount, 2, "the continuation must have been attempted")
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: false))
  }

  func testAProcessBoundaryAtTheDepthBoundReportsTruncationWithoutFetching() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsTreeWithProcessBoundary()

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(["maxDepth": NSNumber(value: 2)]))
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: true), "the hosted subtree is beyond the bound")
    XCTAssertEqual(runtime.snapshotCount, 1, "nothing below the bound is worth a fetch")
  }

  func testTheNodeBudgetHoldsAcrossAProcessBoundary() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsTreeWithProcessBoundary()

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(["maxNodes": NSNumber(value: 3)]))
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: true), "the hosted subtree must not fit in three nodes")
    let boundary = FBAXTestsBoundaryNode(response)
    assertEqualObjects(axValue(boundary, "XC_kAXXCAttributeLabel"), "remote element")
    XCTAssertEqual(axCount(axValue(boundary, "XC_kAXXCAttributeChildren")), 0, "the budget ran out at the boundary: \(String(describing: boundary))")
  }

  func testTheSingleFetchReadHonoursTheDepthBound() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode(
      ["XC_kAXXCAttributeLabel": "root"],
      [FBAXTestsNode(["XC_kAXXCAttributeLabel": "deep"], [])]
    )

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(["maxDepth": NSNumber(value: 0)]))
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: true), "a tree cut at the depth bound reports truncation")
    XCTAssertNil(axValue(axValue(response, "tree"), "XC_kAXXCAttributeChildren"), "nothing below the bound is reported")
  }

  func testTheSingleFetchReadHonoursTheNodeBudget() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode(
      ["XC_kAXXCAttributeLabel": "root"],
      [FBAXTestsNode([:], []), FBAXTestsNode([:], [])]
    )

    // Two nodes of budget for a three-node tree: the root and one child fit, the second does not.
    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(["maxNodes": NSNumber(value: 2)]))
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: true))
    XCTAssertEqual(axCount(axValue(axValue(response, "tree"), "XC_kAXXCAttributeChildren")), 1)
  }

  func testARuntimeWithoutSnapshotSupportIsReportedRatherThanReadAsEmpty() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode(["XC_kAXXCAttributeLabel": "root"], [])
    runtime.snapshotError = NSError(domain: "FBAXBridgeSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: "no userTestingSnapshotForElement:"])

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    XCTAssertTrue(((axValue(response, "error") as? String)?.contains("no userTestingSnapshotForElement:") == true), "the response must carry why the fetch could not be performed: \(String(describing: axValue(response, "error")))")
  }

  // The server answers NULL under kAXErrorSuccess when it will not accept the options.
  func testASnapshotThatAnswersNothingIsAFailureRatherThanAnEmptyTree() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode(["XC_kAXXCAttributeLabel": "root"], [])
    runtime.snapshotAnswersNothing = true

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    XCTAssertNil(axValue(response, "tree"))
  }

  func testMalformedSnapshotRootsAreNotEmptyTrees() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode([:], [])
    for root in ["bad root", NSNull(), NSNumber(value: 1), [] as [Any]] as [Any] {
      // The fake indexes responses across requests as well as continuations.
      runtime.snapshotResults = Array(repeating: root, count: Int(runtime.snapshotCount) + 1)
      let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
      assertEqualObjects(response, ["ok": false, "error": "the single-fetch read returned a shape with no root node"])
    }
    XCTAssertEqual(runtime.snapshotOwnerElements.count, 0)
  }

  func testMalformedSnapshotChildrenDoNotConsumeTheNodeBudget() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode([:], [])
    runtime.snapshotResults = [
      [
        "UIAccessibilitySnapshotKeyChildren": [
          NSNull(),
          ["UIAccessibilitySnapshotKeyAttributes": [7: "child"]],
          "bad child",
        ]
      ]
    ]
    runtime.snapshotNameMappings = [[7: kAXLabel]]

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(["maxNodes": 2]))
    assertEqualObjects(axValue(response, "tree"), [kAXChildren: [[kAXLabel: "child", kAXChildren: []]]])
    assertEqualObjects(axValue(response, "truncated"), false)
  }

  func testMalformedSnapshotAttributesAndNestingAreIgnored() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode([:], [])
    runtime.snapshotResults = [
      [
        "UIAccessibilitySnapshotKeyAttributes": ["not", "a", "dictionary"],
        "UIAccessibilitySnapshotKeyChildren": ["not": "an array"],
      ]
    ]

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "tree"), [kAXChildren: []])
    assertEqualObjects(axValue(response, "truncated"), false)
  }

  func testEachSnapshotFetchUsesItsOwnAttributeMapping() {
    let root = FBAXTestsNode([:], [])
    root.owningProcessIdentifier = kAppPid
    let boundary = FBAXTestsNode([:], [])
    boundary.owningProcessIdentifier = kRemotePid
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    runtime.snapshotResults = [
      [
        "UIAccessibilitySnapshotKeyElement": root,
        "UIAccessibilitySnapshotKeyAttributes": [7: "root"],
        "UIAccessibilitySnapshotKeyChildren": [
          [
            "UIAccessibilitySnapshotKeyElement": boundary,
            "UIAccessibilitySnapshotKeyAttributes": [7: "stub"],
          ]
        ],
      ],
      [
        "UIAccessibilitySnapshotKeyElement": boundary,
        "UIAccessibilitySnapshotKeyAttributes": [7: "remote-id", 42: "remote-label", 99: "unknown"],
      ],
    ]
    runtime.snapshotNameMappings = [[7: kAXLabel], [7: "XC_kAXXCAttributeIdentifier", 42: kAXLabel]]

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(
      axValue(response, "tree"),
      [
        kAXLabel: "root",
        kAXChildren: [
          [
            kAXLabel: "remote-label", "XC_kAXXCAttributeIdentifier": "remote-id", kAXChildren: [],
          ]
        ],
      ])
    XCTAssertEqual(runtime.snapshotCount, 2)
    assertEqualObjects(runtime.snapshotOwnerElements, [root, boundary, boundary])
  }

  func testSnapshotWithoutANumericMappingOmitsAttributes() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode([:], [])
    runtime.snapshotResults = [["UIAccessibilitySnapshotKeyAttributes": [7: "unmapped"]]]

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "tree"), [kAXChildren: []])
    assertEqualObjects(axValue(response, "ok"), true)
  }

  func testSnapshotContinuationWithoutAnErrorKeepsTheStub() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsTreeWithProcessBoundary()
    runtime.snapshotContinuationAnswersNothing = true

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(FBAXTestsBoundaryNode(response), [kAXLabel: "remote element", kAXChildren: []])
    assertEqualObjects(axValue(response, "ok"), true)
    assertEqualObjects(axValue(response, "truncated"), false)
    XCTAssertEqual(runtime.snapshotCount, 2)
  }

  func testSnapshotContinuationLimitRetainsTheLastStub() {
    var subtree = FBAXTestsNode([kAXLabel: "65"], [])
    subtree.owningProcessIdentifier = 1065
    for index in (0..<65).reversed() {
      let parent = FBAXTestsNode([kAXLabel: String(index)], [subtree])
      parent.owningProcessIdentifier = pid_t(1000 + index)
      subtree = parent
    }
    runtime.applicationElements[NSNumber(value: kAppPid)] = subtree

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    XCTAssertEqual(runtime.snapshotCount, 65, "one initial fetch plus 64 continuations")
    assertEqualObjects(axValue(response, "truncated"), true)
    var node = axValue(response, "tree")
    for index in 0...65 {
      assertEqualObjects(axValue(node, kAXLabel), String(index))
      let children = axValue(node, kAXChildren) as? NSArray
      XCTAssertEqual(children?.count, index == 65 ? 0 : 1)
      node = children?.firstObject
    }
  }

  func testSnapshotOwnerQueriesSkipNonLeavesAndNodesBeyondTheBudget() {
    let leaf = FBAXTestsNode([:], [])
    let middle = FBAXTestsNode([:], [leaf])
    let root = FBAXTestsNode([:], [middle])
    for element in [root, middle, leaf] {
      element.owningProcessIdentifier = kAppPid
    }
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest(["maxNodes": 2]))
    assertEqualObjects(axValue(response, "truncated"), true)
    assertEqualObjects(runtime.snapshotOwnerElements, [root])
    assertEqualObjects(runtime.operations, ["automationRead", "applicationElement", "snapshot", "snapshotOwner"])
  }

  func testAnUnknownSnapshotOwnerDisablesDescendantOwnerQueries() {
    let root = FBAXTestsNode([:], [FBAXTestsNode([:], [])])
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(axValue(response, "ok"), true)
    assertEqualObjects(runtime.snapshotOwnerElements, [root])
  }

  func testAnExceptionAtADescendantOwnerAbortsBeforeTheNextSibling() {
    let bad = FBAXTestsNode([:], [])
    bad.snapshotOwnerRaiseReason = "descendant ownership failed"
    let root = FBAXTestsNode([:], [bad, FBAXTestsNode([:], [])])
    root.owningProcessIdentifier = kAppPid
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response = FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:]))
    assertEqualObjects(response, ["ok": false, "error": "the reader raised while answering: descendant ownership failed"])
    assertEqualObjects(runtime.snapshotOwnerElements, [root, bad])
    bad.snapshotOwnerRaiseReason = nil
    assertEqualObjects(axValue(FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:])), "ok"), true)
  }

  // A snapshot answers frames as `AXValue`, not the `NSValue` the per-node walk answers with.
  func testASnapshotFrameIsUnwrappedFromAnAXValue() {
    runtime.applicationElements[NSNumber(value: kAppPid)] =
      FBAXTestsNode([kAXFrame: FBAXFakeRectValue.withRect(CGRect(x: 16, y: 293, width: 370, height: 52))], [])

    let frame = axValue(axValue(FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:])), "tree"), kAXFrame)
    assertEqualObjects(axValue(frame, "X"), NSNumber(value: 16))
    assertEqualObjects(axValue(frame, "Y"), NSNumber(value: 293))
    assertEqualObjects(axValue(frame, "Width"), NSNumber(value: 370))
    assertEqualObjects(axValue(frame, "Height"), NSNumber(value: 52))
  }

  // Named in the request because a default read does not ask for the visible point.
  func testASnapshotVisiblePointIsUnwrappedFromAnAXValue() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode(
      [
        kAXFrame: FBAXFakeRectValue.withRect(CGRect(x: 16, y: 293, width: 370, height: 52)),
        kAXVisiblePoint: FBAXFakePointValue.withPoint(CGPoint(x: 201, y: 319)),
      ],
      []
    )

    let tree = axValue(
      FBAXBridgeHandleRequest(
        FBAXTestsSnapshotRequest(["attributes": [kAXFrame, kAXVisiblePoint]])
      ), "tree")
    assertEqualObjects(axValue(axValue(tree, kAXVisiblePoint), "X"), NSNumber(value: 201))
    assertEqualObjects(axValue(axValue(tree, kAXVisiblePoint), "Y"), NSNumber(value: 319))
    assertEqualObjects(axValue(axValue(tree, kAXFrame), "X"), NSNumber(value: 16), "the frame on the same node is unwrapped the same way")
  }

  func testAnUnrecognisedFrameValueIsEmittedAsNull() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode([kAXFrame: "not a frame"], [])

    let frame = axValue(axValue(FBAXBridgeHandleRequest(FBAXTestsSnapshotRequest([:])), "tree"), kAXFrame)
    assertEqualObjects(frame, NSNull())
  }

  func testAnUnrecognisedPointValueIsEmittedAsNull() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXTestsNode([kAXVisiblePoint: "not a point"], [])

    let point = axValue(
      axValue(
        FBAXBridgeHandleRequest(
          FBAXTestsSnapshotRequest(
            ["attributes": [kAXVisiblePoint]]
          )
        ), "tree"), kAXVisiblePoint)
    assertEqualObjects(point, NSNull())
  }

  // MARK: - Write outcomes

  func testWriteErrorClassification() {
    XCTAssertEqual(FBAXWriteOutcome(forWriteError: FBAXError.success.rawValue).status, FBAXWriteStatus.written)
    XCTAssertEqual(FBAXWriteOutcome(forWriteError: FBAXError.serverNotFound.rawValue).status, FBAXWriteStatus.applicationUnavailable)

    // A timeout is the application being slow, not the application being gone — tagging it unavailable would
    // tell the host to stop retrying something that is still there. It is not a plain failure either: a plain
    // failure means the write did not happen, and a timeout does not say that.
    XCTAssertEqual(FBAXWriteOutcome(forWriteError: FBAXError.ipcTimeout.rawValue).status, FBAXWriteStatus.applicationNotResponding)

    // Every other code is opaque, and the diagnostic has to carry it: triage happens from the wire response
    // alone, and "the write failed" without the number says nothing actionable.
    let rejected = FBAXWriteOutcome(forWriteError: -25201)
    XCTAssertEqual(rejected.status, FBAXWriteStatus.failed)
    XCTAssertTrue(((rejected.failureReason)?.contains("-25201") == true), "\(String(describing: rejected.failureReason))")
  }

  // `FBAXSignatureWarnings` sweeps only ObjC selectors; a C entry point has nothing but this presence check.
  func testTheAXRuntimeWriteEntryPointsResolve() {
    XCTAssertTrue(dlopen(FBAXPathAXRuntime, RTLD_NOW) != nil, "AXRuntime could not be opened")
    XCTAssertTrue(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AXUIElementPerformAction") != nil)
    XCTAssertTrue(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "AXUIElementSetAttributeValue") != nil)
  }

  // Optional in the live runtime; this asserts it is present today, not that the code requires it.
  func testTheAutomationModeReadEntryPointResolves() {
    XCTAssertTrue(dlopen(FBAXPathAXRuntime, RTLD_NOW) != nil, "AXRuntime could not be opened")
    XCTAssertTrue(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXSAutomationEnabled") != nil)
  }

  // MARK: - Guest phase reporting

  func testADescribeReportsItsWalkAndRoundTripCount() {
    let leaf = FBAXFakeElement.readable("UIButton")
    let root = FBAXFakeElement.readable("UIApplication")
    root.children = [leaf]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    let phases = axValue(response, "phases")

    XCTAssertNotNil(phases, "phases must be present on every describe response")
    assertEqualObjects(axValue(phases, "mach_round_trips"), NSNumber(value: 2), "one round trip per node, root plus leaf")
    XCTAssertNotNil(axValue(phases, "traverse_ms"))
    XCTAssertGreaterThanOrEqual(((axValue(phases, "traverse_ms") as? NSNumber)?.doubleValue ?? 0), 0.0)
  }

  // MARK: - Automation mode on the describe path

  // Absent is not false: a host that does not know the field must leave the device alone.
  func testAnAbsentAutomationFieldMutatesNothing() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.automationMode = false

    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])

    assertEqualObjects(runtime.automationModeWrites, [], "an absent field must not write")
    assertEqualObjects(axValue(axValue(response, "automation"), "enabled"), NSNumber(value: false), "the state is still reported")
    assertEqualObjects(axValue(axValue(response, "automation"), "asserted"), NSNumber(value: false))
  }

  func testRequestingAutomationModeWritesAndReportsAsserted() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.automationMode = false

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "automationMode": NSNumber(value: true)])

    assertEqualObjects(runtime.automationModeWrites, [NSNumber(value: true)])
    assertEqualObjects(axValue(axValue(response, "automation"), "enabled"), NSNumber(value: true))
    assertEqualObjects(axValue(axValue(response, "automation"), "asserted"), NSNumber(value: true), "this read changed the device")
  }

  func testRequestingAModeTheDeviceIsAlreadyInWritesNothing() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.automationMode = true

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "automationMode": NSNumber(value: true)])

    assertEqualObjects(runtime.automationModeWrites, [], "nothing to change, so nothing is written")
    assertEqualObjects(axValue(axValue(response, "automation"), "enabled"), NSNumber(value: true))
    assertEqualObjects(axValue(axValue(response, "automation"), "asserted"), NSNumber(value: false), "it was already in that mode")
  }

  func testRequestingAutomationModeOffTurnsItOff() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.automationMode = true

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "automationMode": NSNumber(value: false)])

    assertEqualObjects(runtime.automationModeWrites, [NSNumber(value: false)])
    assertEqualObjects(axValue(axValue(response, "automation"), "enabled"), NSNumber(value: false))
    assertEqualObjects(axValue(axValue(response, "automation"), "asserted"), NSNumber(value: true))
  }

  // A preference write can be accepted and silently not apply.
  func testFailedAutomationModeWriteReportsAssertedFalse() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.automationMode = false
    runtime.automationModeWriteFails = true

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "automationMode": NSNumber(value: true)])

    assertEqualObjects(runtime.automationModeWrites, [NSNumber(value: true)], "the write was attempted")
    assertEqualObjects(axValue(axValue(response, "automation"), "enabled"), NSNumber(value: false), "enabled reads back NO after the failed write")
    assertEqualObjects(axValue(axValue(response, "automation"), "asserted"), NSNumber(value: false), "asserted is NO when the write did not take")
  }

  // Records when the mode is asserted relative to frontmost discovery on a fused read whose discovery
  // fails. The mode decides how much structure a read sees, so that order is observable behaviour.
  func testAFusedFrontmostReadOrdersAutomationAndWindowServerOperations() {
    runtime.automationMode = false
    runtime.windowServerOutcome = FBAXFrontmostOutcome.unresolved("window-server frontmost returned no application object")

    let response = FBAXBridgeHandleRequest([
      "verb": "describe",
      "x": NSNumber(value: 207),
      "y": NSNumber(value: 448),
      "automationMode": NSNumber(value: true),
    ])

    assertEqualObjects(axValue(response, "error_kind"), "frontmost_unresolved")
    // The mode is asserted even though this read goes on to fail, so a retry meets a guest that already
    // has automation on.
    assertEqualObjects(runtime.operations, ["automationRead", "automationWrite", "windowServerFrontmost"])
    assertEqualObjects(runtime.automationModeWrites, [NSNumber(value: true)])
  }

  // MARK: - Device settings

  func testEveryDeviceSettingNameReadsThroughItsSemanticSetting() {
    let settings = [
      "reduce-motion": NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue),
      "reduce-transparency": NSNumber(value: FBAXDeviceSetting.reduceTransparency.rawValue),
      "button-shapes": NSNumber(value: FBAXDeviceSetting.buttonShapes.rawValue),
      "voiceover": NSNumber(value: FBAXDeviceSetting.voiceOver.rawValue),
    ]
    for (name, setting) in settings {
      runtime.deviceSettings[setting] = NSNumber(value: true)

      let response = FBAXBridgeHandleRequest(["verb": "settings-get", "setting": name])

      assertEqualObjects(axValue(response, "ok"), NSNumber(value: true), "\(String(describing: name))")
      assertEqualObjects(axValue(response, "enabled"), NSNumber(value: true), "\(String(describing: name))")
    }
  }

  func testDeviceSettingWriteReturnsReadBackState() {
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)] = NSNumber(value: false)

    let response = FBAXBridgeHandleRequest(
      [
        "verb": "settings-set",
        "setting": "reduce-motion",
        "enabled": NSNumber(value: true),
      ]
    )

    assertEqualObjects(runtime.deviceSettingWrites, ([["setting": NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue), "enabled": NSNumber(value: true)]]))
    assertEqualObjects(axValue(response, "enabled"), NSNumber(value: true))
  }

  func testUnavailableDeviceSettingIsANamedFailure() {
    let response = FBAXBridgeHandleRequest(
      [
        "verb": "settings-get",
        "setting": "voiceover",
      ]
    )

    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error_kind"), "reader_unavailable")
    XCTAssertTrue(((axValue(response, "error") as? String)?.contains("unavailable") == true))
  }

  func testUnavailableDeviceSettingWriteDoesNotReachRuntime() {
    let response = FBAXBridgeHandleRequest(
      [
        "verb": "settings-set",
        "setting": "voiceover",
        "enabled": NSNumber(value: true),
      ]
    )

    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error_kind"), "reader_unavailable")
    assertEqualObjects(runtime.deviceSettingWrites, [])
  }

  func testMalformedDeviceSettingRequestsAreRefused() {
    let unknown = FBAXBridgeHandleRequest(
      [
        "verb": "settings-get",
        "setting": "future-setting",
      ]
    )
    let missingValue = FBAXBridgeHandleRequest(
      [
        "verb": "settings-set",
        "setting": "reduce-motion",
      ]
    )

    assertEqualObjects(axValue(unknown, "error_kind"), "bad_request")
    assertEqualObjects(axValue(missingValue, "error_kind"), "bad_request")
    assertEqualObjects(runtime.deviceSettingWrites, [])
  }

  // MARK: - Write dispatch

  // Seeds the hit-test so a point-addressed write lands on an element reporting `attributes`, and hands the
  // element back so a test can assert the write acted on that one.
  @discardableResult
  private func seedHitElement(withAttributes attributes: [String: Any]) -> FBAXFakeElement {
    let element = FBAXFakeElement()
    element.attributes = attributes
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(element, owningProcessIdentifier: kAppPid)
    return element
  }

  private func FBAXTestsPress() -> [String: Any] {
    return ["verb": "perform", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "action": "press"]
  }

  func testEveryActionNameReachesTheRuntimeAsItsSemanticAction() {
    let actions = [
      "press": NSNumber(value: FBAXAction.press.rawValue),
      "scroll-up": NSNumber(value: FBAXAction.scrollUp.rawValue),
      "scroll-down": NSNumber(value: FBAXAction.scrollDown.rawValue),
      "scroll-left": NSNumber(value: FBAXAction.scrollLeft.rawValue),
      "scroll-right": NSNumber(value: FBAXAction.scrollRight.rawValue),
      "scroll-to-visible": NSNumber(value: FBAXAction.scrollToVisible.rawValue),
    ]
    var performed: UInt = 0
    for name in actions.keys {
      self.seedHitElement(withAttributes: [:])
      let response =
        FBAXBridgeHandleRequest(["verb": "perform", "x": NSNumber(value: 10), "y": NSNumber(value: 20), "action": name])
      assertEqualObjects(axValue(response, "ok"), NSNumber(value: true), "\(String(describing: name))")
      assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid), "\(String(describing: name))")
      performed += 1
      XCTAssertEqual(runtime.performCount, performed, "\(String(describing: name)) must reach the runtime")
      XCTAssertEqual(runtime.lastPerformedAction.rawValue, ((axValue(actions, name) as? NSNumber)?.uintValue ?? 0), "\(String(describing: name))")
    }
  }

  func testUnknownActionIsRejectedWithoutReachingTheRuntime() {
    self.seedHitElement(withAttributes: [:])
    for action in ["pres", "AXPress", "", NSNumber(value: 123), NSNull()] as [Any] {
      let response =
        FBAXBridgeHandleRequest(["verb": "perform", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "action": action])
      assertEqualObjects(axValue(response, "ok"), NSNumber(value: false), "\(String(describing: action))")
      XCTAssertTrue(((axValue(response, "error") as? String)?.hasPrefix("unsupported action:") == true), "\(String(describing: axValue(response, "error")))")
    }
    assertEqualObjects(axValue(FBAXBridgeHandleRequest(["verb": "perform", "x": NSNumber(value: 1), "y": NSNumber(value: 2)]), "error"), "unsupported action: (nil)")
    XCTAssertEqual(runtime.hitTestCount, 0, "a request that cannot be understood must not reach the application")
    XCTAssertEqual(runtime.performCount, 0)
  }

  func testAWriteRequiresNumericCoordinates() {
    self.seedHitElement(withAttributes: [:])
    let requests: [[String: Any]] = [
      ["verb": "perform", "action": "press"],
      ["verb": "perform", "action": "press", "x": NSNumber(value: 1)],
      ["verb": "perform", "action": "press", "x": "1", "y": NSNumber(value: 2)],
      ["verb": "setvalue", "value": "hello"],
      ["verb": "setvalue", "value": "hello", "x": NSNumber(value: 1), "y": NSNull()],
    ]
    for request in requests {
      let response = FBAXBridgeHandleRequest(request)
      assertEqualObjects(axValue(response, "ok"), NSNumber(value: false), "\(String(describing: request))")
      assertEqualObjects(axValue(response, "error"), "a write requires numeric x and y", "\(String(describing: request))")
    }
    XCTAssertEqual(runtime.hitTestCount, 0)
  }

  func testAWriteOnEmptySpaceIsASuccessfulEmptyResult() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.empty()
    let requests: [[String: Any]] = [
      FBAXTestsPress(),
      ["verb": "setvalue", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "value": "hello"],
    ]
    for request in requests {
      let response = FBAXBridgeHandleRequest(request)
      assertEqualObjects(axValue(response, "ok"), NSNumber(value: true), "\(String(describing: axValue(request, "verb")))")
      assertEqualObjects(axValue(response, "empty"), NSNumber(value: true), "\(String(describing: axValue(request, "verb")))")
      XCTAssertNil(axValue(response, "error"), "\(String(describing: axValue(request, "verb")))")
    }
    XCTAssertEqual(runtime.performCount, 0, "nothing at the point means nothing to write to")
    XCTAssertEqual(runtime.setValueCount, 0)
  }

  func testAWriteToAnUnavailableApplicationIsTaggedAndNamesThePidWhenKnown() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.applicationUnavailable()
    let unhit = FBAXBridgeHandleRequest(FBAXTestsPress())
    assertEqualObjects(axValue(unhit, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(unhit, "error_kind"), "application_unavailable")
    assertEqualObjects(axValue(unhit, "error"), "no accessibility server answered the write")

    self.seedHitElement(withAttributes: [:])
    runtime.writeOutcome = FBAXWriteOutcome.applicationUnavailable()
    let died = FBAXBridgeHandleRequest(FBAXTestsPress())
    assertEqualObjects(axValue(died, "error_kind"), "application_unavailable")
    assertEqualObjects(axValue(died, "error"), "pid 4321 has no accessibility server to accept the write")
  }

  // No element populates `XC_kAXXCAttributeUserTestingActions`, so there is no pre-check on it.
  func testAnActionIsPerformedWhateverTheElementAdvertises() {
    for advertised in [["AXScrollToVisible"], [], NSNull()] as [Any] {
      self.seedHitElement(withAttributes: ["XC_kAXXCAttributeUserTestingActions": advertised])
      assertEqualObjects(axValue(FBAXBridgeHandleRequest(FBAXTestsPress()), "ok"), NSNumber(value: true), "\(String(describing: advertised))")
    }
    XCTAssertEqual(runtime.performCount, 3)
  }

  func testWriteAssertionsPreserveNSStringUnicodeEquality() {
    let actual = "\u{00E9}"
    let equivalent = "e\u{0301}"
    XCTAssertFalse((actual as NSString).isEqual(to: equivalent))
    XCTAssertEqual(actual, equivalent)

    for useDescription in [false, true] {
      for verb in ["perform", "setvalue"] {
        let opaque = FBAXFakeOpaqueValue()
        opaque.descriptionValue = actual
        let value: Any = useDescription ? opaque : actual
        seedHitElement(withAttributes: [kAXLabel: value])
        let performedBefore = runtime.performCount
        let setBefore = runtime.setValueCount
        var request: [String: Any] = [
          "verb": verb, "x": 1, "y": 2, "action": "press", "value": "replacement",
          "assertKey": kAXLabel, "assertValue": equivalent,
        ]

        let rejected = FBAXBridgeHandleRequest(request)
        assertEqualObjects(axValue(rejected, "ok"), false)
        assertEqualObjects(axValue(rejected, "error_kind"), "assertion_failed")
        XCTAssertEqual(runtime.performCount, performedBefore)
        XCTAssertEqual(runtime.setValueCount, setBefore)

        request["assertValue"] = actual
        assertEqualObjects(axValue(FBAXBridgeHandleRequest(request), "ok"), true)
        XCTAssertEqual(runtime.performCount, performedBefore + (verb == "perform" ? 1 : 0))
        XCTAssertEqual(runtime.setValueCount, setBefore + (verb == "setvalue" ? 1 : 0))
      }
    }
  }

  func testAnAssertionThatDoesNotMatchRefusesTheWrite() {
    self.seedHitElement(withAttributes: [kAXLabel: "Wi-Fi"])

    let response = FBAXBridgeHandleRequest(
      [
        "verb": "perform",
        "x": NSNumber(value: 200),
        "y": NSNumber(value: 711),
        "action": "press",
        "assertKey": kAXLabel,
        "assertValue": "General",
      ]
    )
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error_kind"), "assertion_failed")
    assertEqualObjects(axValue(response, "error"), "the element at (200.0, 711.0) has XC_kAXXCAttributeLabel Wi-Fi, expected General")
    XCTAssertEqual(runtime.performCount, 0, "a write must not land on an element that is not the one named")
  }

  func testAnAssertionThatMatchesAllowsTheWrite() {
    self.seedHitElement(withAttributes: [kAXLabel: "General"])

    let pressed = FBAXBridgeHandleRequest(
      [
        "verb": "perform",
        "x": NSNumber(value: 1),
        "y": NSNumber(value: 2),
        "action": "press",
        "assertKey": kAXLabel,
        "assertValue": "General",
      ]
    )
    assertEqualObjects(axValue(pressed, "ok"), NSNumber(value: true))
    XCTAssertEqual(runtime.performCount, 1)

    let written = FBAXBridgeHandleRequest(
      [
        "verb": "setvalue",
        "x": NSNumber(value: 1),
        "y": NSNumber(value: 2),
        "value": "hello",
        "assertKey": kAXLabel,
        "assertValue": "General",
      ]
    )
    assertEqualObjects(axValue(written, "ok"), NSNumber(value: true), "the assertion is not specific to one write verb")
    XCTAssertEqual(runtime.setValueCount, 1)
  }

  func testAnAssertionKeyAndValueAreOnlyMeaningfulTogether() {
    self.seedHitElement(withAttributes: [kAXLabel: "General"])
    for partial in [["assertKey": kAXLabel], ["assertValue": "General"]] {
      var request: [String: Any] = FBAXTestsPress()
      request.merge(partial) { _, new in new }
      let response = FBAXBridgeHandleRequest(request)
      assertEqualObjects(axValue(response, "ok"), NSNumber(value: false), "\(String(describing: partial))")
      assertEqualObjects(axValue(response, "error"), "assertKey and assertValue are only meaningful together")
    }
    XCTAssertEqual(runtime.hitTestCount, 0)
  }

  func testAnAssertionOnAnAttributeTheReaderDoesNotFetchIsRejected() {
    self.seedHitElement(withAttributes: [kAXLabel: "General"])
    var request: [String: Any] = FBAXTestsPress()
    request["assertKey"] = "XC_kAXXCAttributeTraits"
    request["assertValue"] = "button"

    let response = FBAXBridgeHandleRequest(request)
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error"), "XC_kAXXCAttributeTraits is not an attribute a write can assert on")
    XCTAssertEqual(runtime.hitTestCount, 0)
  }

  func testSetValueSendsTheValueAndTheHitElementToTheRuntime() {
    let element = self.seedHitElement(withAttributes: [kAXLabel: "Name"])

    let response =
      FBAXBridgeHandleRequest(["verb": "setvalue", "x": NSNumber(value: 30), "y": NSNumber(value: 40), "value": "hello"])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid))
    XCTAssertEqual(runtime.setValueCount, 1)
    assertEqualObjects(runtime.lastWrittenValue, "hello")
    assertEqualObjects(runtime.lastWrittenElement, element, "the write must act on the element the hit-test found")
    XCTAssertEqual(runtime.performCount, 0, "a set-value is not an action")
  }

  func testSetValueRequiresAStringValue() {
    self.seedHitElement(withAttributes: [:])
    for value in [NSNumber(value: 123), ["hello"], ["a": NSNumber(value: 1)], NSNull()] as [Any] {
      let response = FBAXBridgeHandleRequest(["verb": "setvalue", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "value": value])
      assertEqualObjects(axValue(response, "ok"), NSNumber(value: false), "\(String(describing: type(of: value)))")
      assertEqualObjects(axValue(response, "error"), "setvalue requires a string value", "\(String(describing: type(of: value)))")
    }
    assertEqualObjects(axValue(FBAXBridgeHandleRequest(["verb": "setvalue", "x": NSNumber(value: 1), "y": NSNumber(value: 2)]), "error"), "setvalue requires a string value")
    XCTAssertEqual(runtime.hitTestCount, 0)
    XCTAssertEqual(runtime.setValueCount, 0)
  }

  func testAFailedWriteIsAnOpaqueFailureCarryingTheRuntimeReason() {
    self.seedHitElement(withAttributes: [:])
    runtime.writeOutcome = FBAXWriteOutcome.failed("the application did not answer the write in time")

    let response = FBAXBridgeHandleRequest(FBAXTestsPress())
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error"), "the application did not answer the write in time")
    XCTAssertNil(axValue(response, "error_kind"))
  }

  func testAWriteWithAnExplicitPidScopesTheHitTest() {
    self.seedHitElement(withAttributes: [:])
    var request: [String: Any] = FBAXTestsPress()
    request["pid"] = NSNumber(value: kAppPid)

    assertEqualObjects(axValue(FBAXBridgeHandleRequest(request), "ok"), NSNumber(value: true))
    XCTAssertEqual(runtime.lastHitTestProcessIdentifier, kAppPid)

    assertEqualObjects(axValue(FBAXBridgeHandleRequest(FBAXTestsPress()), "ok"), NSNumber(value: true))
    XCTAssertEqual(runtime.lastHitTestProcessIdentifier, 0, "no pid means a display-wide hit-test")
  }

  // MARK: - Attribute value coercion

  func testPointValuedAttributeIsCarriedThroughStructurally() {
    let point = ["X": NSNumber(value: 201), "Y": NSNumber(value: 789.5)]
    let root = FBAXFakeElement.readable("UIApplication")
    root.attributes = [kAXElementType: "UIApplication", kAXVisiblePoint: point]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let emitted = axValue(axValue(FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)]), "tree"), kAXVisiblePoint)
    XCTAssertTrue((emitted is NSDictionary), "a point stays structured, got \(String(describing: type(of: emitted)))")
    assertEqualObjects(axValue(emitted, "X"), NSNumber(value: 201))
    assertEqualObjects(axValue(emitted, "Y"), NSNumber(value: 789.5))
  }

  func testTheFrameAttributeIsCarriedThroughStructurally() {
    let root = FBAXFakeElement.readable("UIApplication")
    root.attributes = [
      kAXElementType: "UIApplication",
      kAXFrame: ["X": NSNumber(value: 0), "Y": NSNumber(value: 791), "Width": NSNumber(value: 402), "Height": NSNumber(value: 83)],
    ]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let emitted = axValue(axValue(FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)]), "tree"), kAXFrame)
    XCTAssertTrue((emitted is NSDictionary), "the frame stays structured, got \(String(describing: type(of: emitted)))")
    assertEqualObjects(axValue(emitted, "Width"), NSNumber(value: 402))
  }

  // XCTest's reader returns an `NSError` as the attribute's value for any AX failure other than no-value or
  // unsupported.
  func testAnAttributeThatFailedToReadIsEmittedAsItsValue() {
    let failure = NSError(domain: "AXError", code: -25204, userInfo: [NSLocalizedDescriptionKey: "kAXErrorCannotComplete"])
    let root = FBAXFakeElement.readable("UIApplication")
    root.attributes = [kAXElementType: "UIApplication", kAXLabel: failure]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let tree = axValue(FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)]), "tree")
    assertEqualObjects(axValue(tree, kAXLabel), NSNull(), "a failure is not the attribute's value")
    assertEqualObjects(axValue(axValue(tree, "FBAttributeReadFailures"), kAXLabel), "kAXErrorCannotComplete", "the failed key is named with its reason rather than silently reading as no value")
  }

  // MARK: - The translator vocabulary seam

  func testATranslatorReadOfALeafAtTheDepthCapDoesNotReportTruncation() {
    let root = FBAXFakeElement.readable("UIApplication")
    root.attributes = [kAXElementType: "UIApplication"]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    runtime.translatorAttributeValues = [NSNumber(value: FBAXPAttribute.attributeLabel.rawValue): "Settings"]

    let response = FBAXBridgeHandleRequest(
      [
        "verb": "describe",
        "pid": NSNumber(value: kAppPid),
        "translatorVocabulary": NSNumber(value: true),
        "maxDepth": NSNumber(value: 0),
      ]
    )

    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: false), "truncated is NO when the depth cap cut nothing")
  }

  func testATranslatorWalkCostsTwoRoundTripsPerNode() {
    let root = FBAXFakeElement.readable("UIApplication")
    root.attributes = [kAXElementType: "UIApplication"]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    runtime.translatorAttributeValues = [
      NSNumber(value: FBAXPAttribute.attributeLabel.rawValue): "Settings",
      NSNumber(value: FBAXPAttribute.attributeChildren.rawValue): [FBAXFakeElement.readable("UIView"), FBAXFakeElement.readable("UIView")],
    ]

    _ = FBAXBridgeHandleRequest(
      [
        "verb": "describe",
        "pid": NSNumber(value: kAppPid),
        "translatorVocabulary": NSNumber(value: true),
        "maxDepth": NSNumber(value: 1),
      ]
    )

    // Three nodes: the root and its two children. Two requests each — one batch of attributes, one for
    // children, which the handler special-cases out of the batch and so cannot be folded into it.
    XCTAssertEqual(runtime.translatorReadCount, 6)
  }

  func testATranslatorReadEmitsTheEnabledAnswerItFetched() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorAttributeValues = [NSNumber(value: FBAXPAttribute.attributeLabel.rawValue): "General", NSNumber(value: FBAXPAttribute.attributeIsEnabled.rawValue): NSNumber(value: false)]

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "translatorVocabulary": NSNumber(value: true)])

    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(axValue(response, "tree"), kNodeIsEnabled), NSNumber(value: false), "the fetched enabled answer must reach the wire")
  }

  func testATranslatorReadEmitsTheTranslatorsOwnRoleUnmapped() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorAttributeValues = [NSNumber(value: FBAXPAttribute.attributeRole.rawValue): NSNumber(value: 9)]

    let tree =
      axValue(FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "translatorVocabulary": NSNumber(value: true)]), "tree")

    assertEqualObjects(axValue(tree, kNodeTranslatorRole), NSNumber(value: 9))
    XCTAssertNil(axValue(tree, kAXElementType), "the translator role must not be emitted under the elementType key")
  }

  // The host derives `interactable` from the XCTest key, so the point must land under it.
  func testATranslatorReadEmitsTheVisiblePoint() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorAttributeValues = [
      NSNumber(value: FBAXPAttribute.attributeVisiblePoint.rawValue): NSValue(cgPoint: CGPoint(x: 201, y: 311))
    ]

    let tree =
      axValue(FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "translatorVocabulary": NSNumber(value: true)]), "tree")

    assertEqualObjects(axValue(axValue(tree, "XC_kAXXCAttributeVisiblePoint"), "X"), NSNumber(value: 201))
    assertEqualObjects(axValue(axValue(tree, "XC_kAXXCAttributeVisiblePoint"), "Y"), NSNumber(value: 311))
  }

  func testATranslatorReadEmitsTheTraitsBitmask() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorAttributeValues = [NSNumber(value: FBAXPAttribute.attributeTraits.rawValue): NSNumber(value: 1 << 6)]

    let tree =
      axValue(FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "translatorVocabulary": NSNumber(value: true)]), "tree")

    assertEqualObjects(axValue(tree, "FBTraits"), NSNumber(value: 1 << 6))
  }

  func testATranslatorReadEmitsAPerElementIdentity() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorAttributeValues = [NSNumber(value: FBAXPAttribute.attributeMemoryAddress.rawValue): NSNumber(value: 0x600001234560)]

    let tree =
      axValue(FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "translatorVocabulary": NSNumber(value: true)]), "tree")

    assertEqualObjects(axValue(tree, "FBElementIdentity"), NSNumber(value: 0x600001234560))
  }

  func testATranslatorReadThatCannotBePerformedIsAFailureNotAnEmptyTree() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorAttributeValues = nil

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "translatorVocabulary": NSNumber(value: true)])

    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    XCTAssertNil(axValue(response, "tree"), "a read that could not be performed must not answer with a tree")
  }

  // The translator answers synthesized defaults for a pid that names no process; only the availability
  // probe fails this.
  func testATranslatorReadOfAnUnavailableApplicationFailsRatherThanFabricatingARoot() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.applicationUnavailable()
    runtime.translatorAttributeValues = [NSNumber(value: FBAXPAttribute.attributeRole.rawValue): NSNumber(value: 1), NSNumber(value: FBAXPAttribute.attributeIsEnabled.rawValue): NSNumber(value: true)]

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "translatorVocabulary": NSNumber(value: true)])

    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error_kind"), "application_unavailable")
    XCTAssertNil(axValue(response, "tree"), "a process with no accessibility server must not answer with a root")
  }

  func testAFusedFrontmostTranslatorReadStillNamesTheResolverThatRan() {
    runtime.windowServerOutcome = FBAXFrontmostOutcome.resolved(kAppPid)
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorAttributeValues = [NSNumber(value: FBAXPAttribute.attributeLabel.rawValue): "SampleApp"]

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "x": NSNumber(value: 201), "y": NSNumber(value: 437), "translatorVocabulary": NSNumber(value: true)])

    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid))
    assertEqualObjects(axValue(response, "method"), "window-server")
  }

  private func translatorRequest(_ extra: [String: Any] = [:]) -> [String: Any] {
    var request: [String: Any] = ["verb": "describe", "pid": kAppPid, "translatorVocabulary": true]
    request.merge(extra) { _, new in new }
    return request
  }

  func testTranslatorBatchAndChildrenRequestsPreserveElementIdentity() {
    let root = FBAXFakeElement.readable("UIApplication")
    let child = FBAXFakeElement.readable("UIView")
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    runtime.translatorResponses = [[33: "root"], [8: [child]], [33: "child"], [:]]

    let response = FBAXBridgeHandleRequest(translatorRequest())

    assertEqualObjects(axValue(response, "tree"), [kAXLabel: "root", kAXChildren: [[kAXLabel: "child", kAXChildren: []]]])
    let requests = runtime.translatorRequests.compactMap { $0 as? [String: Any] }
    let batch = [33, 21, 25, 53, 32, 27, 45, 51, 112, 77, 128]
    assertEqualObjects(requests.compactMap { $0["attributes"] }, [batch, [8], batch, [8]])
    assertEqualObjects(requests.compactMap { $0["element"] }, [root, root, child, child])
    assertEqualObjects(runtime.lastReadAttributes, [kAXElementType])
    assertEqualObjects(axValue(axValue(response, "phases"), "mach_round_trips"), 4)
  }

  func testTranslatorRequestsChildrenAtTheDepthLimit() {
    let root = FBAXFakeElement.readable("UIApplication")
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    runtime.translatorResponses = [[:], [8: [FBAXFakeElement.readable("child")]]]

    let response = FBAXBridgeHandleRequest(translatorRequest(["maxDepth": 0]))

    assertEqualObjects(axValue(response, "tree"), [kAXChildren: []])
    assertEqualObjects(axValue(response, "truncated"), true)
    XCTAssertEqual(runtime.translatorReadCount, 2)
    assertEqualObjects((runtime.translatorRequests.lastObject as? [String: Any])?["attributes"], [8])
  }

  func testTranslatorSkipsAnOrdinaryFailedChildAndKeepsItsSibling() {
    let root = FBAXFakeElement.readable("UIApplication")
    let failed = FBAXFakeElement.readable("failed")
    let sibling = FBAXFakeElement.readable("sibling")
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    runtime.translatorResponses = [[:], [8: [failed, sibling]], NSNull(), [33: "sibling"], [:]]

    let response = FBAXBridgeHandleRequest(translatorRequest())

    assertEqualObjects(axValue(response, "tree"), [kAXChildren: [[kAXLabel: "sibling", kAXChildren: []]]])
    assertEqualObjects(axValue(response, "truncated"), false)
    XCTAssertEqual(runtime.translatorReadCount, 5)
  }

  func testTranslatorNilChildrenAreAnEmptySuccessfulNode() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorResponses = [[:], NSNull()]

    let response = FBAXBridgeHandleRequest(translatorRequest())

    assertEqualObjects(axValue(response, "ok"), true)
    assertEqualObjects(axValue(response, "tree"), [kAXChildren: []])
    assertEqualObjects(axValue(response, "truncated"), false)
  }

  func testTranslatorChildListExceptionsAbortAndLeaveTheNextRequestUsable() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorAttributeValues = [:]
    runtime.translatorRaiseAtRead = 2

    let response = FBAXBridgeHandleRequest(translatorRequest())

    assertEqualObjects(response, ["ok": false, "error": "the reader raised while answering: translator read 2 failed"])
    XCTAssertEqual(runtime.translatorReadCount, 2)
    runtime.translatorRaiseAtRead = 0
    assertEqualObjects(axValue(FBAXBridgeHandleRequest(translatorRequest()), "ok"), true)
  }

  func testTranslatorChildExceptionsAbortBeforeTheNextSibling() {
    let root = FBAXFakeElement.readable("UIApplication")
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    runtime.translatorResponses = [[:], [8: [FBAXFakeElement.readable("bad"), FBAXFakeElement.readable("sibling")]]]
    runtime.translatorRaiseAtRead = 3

    let response = FBAXBridgeHandleRequest(translatorRequest())

    assertEqualObjects(response, ["ok": false, "error": "the reader raised while answering: translator read 3 failed"])
    XCTAssertEqual(runtime.translatorReadCount, 3)
  }

  func testTranslatorBudgetCountsFailedChildren() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.translatorResponses = [[:], [8: [FBAXFakeElement.readable("bad"), FBAXFakeElement.readable("sibling")]], NSNull()]

    let response = FBAXBridgeHandleRequest(translatorRequest(["maxNodes": 2]))

    assertEqualObjects(axValue(response, "tree"), [kAXChildren: []])
    assertEqualObjects(axValue(response, "truncated"), true)
    XCTAssertEqual(runtime.translatorReadCount, 3)
  }

  // MARK: - Unreachable explanations

  private func unreachableRoot(_ visible: Any = false) -> FBAXFakeElement {
    let root = FBAXFakeElement.readable("UIApplication")
    root.attributes = ["XC_kAXXCAttributeIsVisible": visible, "XC_kAXXCAttributeCenterPoint": ["X": 12, "Y": 34]]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    return root
  }

  private func explanationRequest() -> [String: Any] {
    return ["verb": "describe", "pid": kAppPid, "explainUnreachable": true]
  }

  func testUnreachableExplanationReadsTheDisplayWideHitElement() {
    _ = unreachableRoot()
    let overlay = FBAXFakeElement.readable("Overlay")
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(overlay, owningProcessIdentifier: 9000)

    let response = FBAXBridgeHandleRequest(explanationRequest())

    let explanation = axValue(axValue(response, "tree"), "FBExplainedBy")
    assertEqualObjects(explanation, [kAXElementType: "Overlay", kAXLabel: "Overlay", kAXChildren: ([] as NSArray).description])
    XCTAssertEqual(runtime.lastHitTestProcessIdentifier, 0)
    XCTAssertEqual(runtime.lastHitTestPoint, CGPoint(x: 12, y: 34))
    assertEqualObjects(runtime.lastReadAttributes, [kAXElementType, kAXLabel, "XC_kAXXCAttributeIdentifier", kAXFrame, "XC_kAXXCAttributeAutomationType"])
    assertEqualObjects(runtime.operations, ["automationRead", "applicationElement", "readAttributes", "hitTest", "readAttributes"])
    assertEqualObjects(axValue(axValue(response, "phases"), "mach_round_trips"), 3)
  }

  func testUnreachableExplanationOmitsOrdinaryHitTestFailure() {
    _ = unreachableRoot()
    runtime.hitTestOutcome = FBAXHitTestOutcome.applicationNotResponding()

    let response = FBAXBridgeHandleRequest(explanationRequest())

    assertEqualObjects(axValue(response, "ok"), true)
    XCTAssertNil(axValue(axValue(response, "tree"), "FBExplainedBy"))
    assertEqualObjects(axValue(axValue(response, "phases"), "mach_round_trips"), 2)
  }

  func testUnreachableExplanationOmitsOrdinaryAttributeReadFailure() {
    _ = unreachableRoot()
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.applicationUnavailable(), owningProcessIdentifier: 9000)

    let response = FBAXBridgeHandleRequest(explanationRequest())

    assertEqualObjects(axValue(response, "ok"), true)
    XCTAssertNil(axValue(axValue(response, "tree"), "FBExplainedBy"))
    assertEqualObjects(axValue(axValue(response, "phases"), "mach_round_trips"), 3)
  }

  func testUnreachableExplanationReadExceptionAbortsAndRecovers() {
    _ = unreachableRoot()
    let overlay = FBAXFakeElement.readable("Overlay")
    overlay.readRaiseReason = "explanation failed"
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(overlay, owningProcessIdentifier: 9000)

    assertEqualObjects(FBAXBridgeHandleRequest(explanationRequest()), ["ok": false, "error": "the reader raised while answering: explanation failed"])
    overlay.readRaiseReason = nil
    assertEqualObjects(axValue(FBAXBridgeHandleRequest(explanationRequest()), "ok"), true)
  }

  func testVisibilityExceptionAbortsBeforeHitTestingAndNextRequestRecovers() {
    let visibility = FBAXFakeVisibilityValue()
    visibility.raises = true
    let root = unreachableRoot(visibility)
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("Overlay"), owningProcessIdentifier: 9000)

    assertEqualObjects(FBAXBridgeHandleRequest(explanationRequest()), ["ok": false, "error": "the reader raised while answering: visibility failed"])
    XCTAssertEqual(runtime.hitTestCount, 0)

    root.attributes = ["XC_kAXXCAttributeIsVisible": false, "XC_kAXXCAttributeCenterPoint": ["X": 12, "Y": 34]]
    assertEqualObjects(axValue(FBAXBridgeHandleRequest(explanationRequest()), "ok"), true)
    XCTAssertEqual(runtime.hitTestCount, 1)
  }

  func testCentreCoordinateExceptionAbortsBeforeHitTestingAndNextRequestRecovers() {
    let coordinate = FBAXFakeVisibilityValue()
    let visibility = FBAXFakeVisibilityValue()
    visibility.coordinateToInvalidate = coordinate
    let root = unreachableRoot(visibility)
    let centre: [String: Any] = ["X": coordinate, "Y": 34]
    root.attributes = ["XC_kAXXCAttributeIsVisible": visibility, "XC_kAXXCAttributeCenterPoint": centre]
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("Overlay"), owningProcessIdentifier: 9000)

    assertEqualObjects(FBAXBridgeHandleRequest(explanationRequest()), ["ok": false, "error": "the reader raised while answering: geometry coordinate failed"])
    XCTAssertEqual(runtime.hitTestCount, 0)

    root.attributes = ["XC_kAXXCAttributeIsVisible": false, "XC_kAXXCAttributeCenterPoint": ["X": 12, "Y": 34]]
    assertEqualObjects(axValue(FBAXBridgeHandleRequest(explanationRequest()), "ok"), true)
    XCTAssertEqual(runtime.hitTestCount, 1)
  }

  func testReachableAndUnclassifiedNodesDoNotRequestExplanations() {
    for visible in [true, "unknown", NSNull()] as [Any] {
      _ = unreachableRoot(visible)
      assertEqualObjects(axValue(FBAXBridgeHandleRequest(explanationRequest()), "ok"), true)
    }
    XCTAssertEqual(runtime.hitTestCount, 0)
  }

  // MARK: - Private attribute values

  func testWrongGeometryTypesAndMalformedDictionariesBecomeNull() {
    let root = FBAXFakeElement.readable("UIApplication")
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    let values: [(String, Any)] = [
      (kAXFrame, NSValue(cgPoint: CGPoint(x: 1, y: 2))),
      (kAXVisiblePoint, NSValue(cgRect: CGRect(x: 1, y: 2, width: 3, height: 4))),
      (kAXFrame, ["X": 1, "Y": 2]),
      (kAXVisiblePoint, ["X": 1]),
    ]
    for (key, value) in values {
      root.attributes = [key: value]
      let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid])
      assertEqualObjects(axValue(response, "ok"), true)
      assertEqualObjects(axValue(axValue(response, "tree"), key), NSNull())
    }
  }

  func testGeometryDictionariesPreserveAdditionalFields() {
    let root = FBAXFakeElement.readable("UIApplication")
    let frame = ["X": 1, "Y": 2, "Width": 3, "Height": 4, "extra": 5]
    let point = ["X": 1, "Y": 2, "extra": 3]
    root.attributes = [kAXFrame: frame, kAXVisiblePoint: point]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let tree = axValue(FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid]), "tree")

    assertEqualObjects(axValue(tree, kAXFrame), frame)
    assertEqualObjects(axValue(tree, kAXVisiblePoint), point)
  }

  func testOpaqueValuesUseTheirDescriptionAndContainDescriptionExceptions() {
    let value = FBAXFakeOpaqueValue()
    let root = FBAXFakeElement.readable("UIApplication")
    root.attributes = ["XC_kAXXCAttributeValue": value]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    let request: [String: Any] = ["verb": "describe", "pid": kAppPid]

    assertEqualObjects(axValue(axValue(FBAXBridgeHandleRequest(request), "tree"), "XC_kAXXCAttributeValue"), "opaque accessibility value")
    value.raiseReason = "description failed"
    assertEqualObjects(FBAXBridgeHandleRequest(request), ["ok": false, "error": "the reader raised while answering: description failed"])
    value.raiseReason = nil
    assertEqualObjects(axValue(FBAXBridgeHandleRequest(request), "ok"), true)
  }

  func testCoreGraphicsDictionaryExceptionsAreObservableInsideObjectiveC() {
    for rectangle in [false, true] {
      let healthy = FBAXGeometryDictionaryProbe(rectangle, false)
      assertEqualObjects(healthy["accepted"], true)
      assertEqualObjects(healthy["raised"], false)
      XCTAssertGreaterThan((healthy["lookups"] as? NSNumber)?.intValue ?? 0, 0)

      let raised = FBAXGeometryDictionaryProbe(rectangle, true)
      assertEqualObjects(raised["accepted"], false)
      assertEqualObjects(raised["raised"], true)
      assertEqualObjects(raised["reason"], "geometry dictionary lookup failed")
      XCTAssertGreaterThan((raised["lookups"] as? NSNumber)?.intValue ?? 0, 0)
    }
  }

  func testGeometryDictionaryExceptionsAreContainedAndTheNextRequestSucceeds() {
    let root = FBAXFakeElement.readable("UIApplication")
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    for key in [kAXFrame, "XC_kAXXCAttributeVisiblePoint", "XC_kAXXCAttributeCenterPoint"] {
      let value = FBAXGeometryDictionaryProbeValue.geometry()
      value.raises = true
      root.attributes = [key: value]
      let request: [String: Any] = ["verb": "describe", "pid": kAppPid, "attributes": [key]]
      assertEqualObjects(
        FBAXBridgeHandleRequest(request),
        ["ok": false, "error": "the reader raised while answering: geometry dictionary lookup failed"])
      XCTAssertGreaterThan(value.lookups, 0)
      root.attributes = [key: ["X": 1, "Y": 2, "Width": 3, "Height": 4]]
      assertEqualObjects(axValue(FBAXBridgeHandleRequest(request), "ok"), true)
    }
  }

  func testGeometryAccessorExceptionsAreContained() {
    let root = FBAXFakeElement.readable("UIApplication")
    runtime.applicationElements[NSNumber(value: kAppPid)] = root
    for access in ["type", "value"] {
      root.attributes = [kAXFrame: FBAXFakeGeometryValue.throwing(onAccess: access)]
      let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid])
      assertEqualObjects(response, ["ok": false, "error": "the reader raised while answering: geometry \(access) failed"])
    }
  }

  func testFailedChildReadsStillConsumeTheNodeBudget() {
    let root = FBAXFakeElement.readable("UIApplication")
    root.children = [FBAXFakeElement.failed(nil), FBAXFakeElement.readable("sibling")]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid, "maxNodes": 1])

    assertEqualObjects(axValue(axValue(response, "tree"), kAXChildren), [])
    assertEqualObjects(axValue(response, "truncated"), true)
    assertEqualObjects(runtime.operations, ["automationRead", "applicationElement", "readAttributes", "readAttributes"])
  }

  func testFailedDeviceSettingOutcomesRetainTheRuntimeReason() {
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)] = false
    runtime.deviceSettingReadOutcome = FBAXDeviceSettingOutcome.failed("read failed")
    runtime.deviceSettingWriteOutcome = FBAXDeviceSettingOutcome.failed("write failed")

    assertEqualObjects(FBAXBridgeHandleRequest(["verb": "settings-get", "setting": "reduce-motion"]), ["ok": false, "error": "read failed", "error_kind": "reader_unavailable"])
    assertEqualObjects(FBAXBridgeHandleRequest(["verb": "settings-set", "setting": "reduce-motion", "enabled": true]), ["ok": false, "error": "write failed", "error_kind": "reader_unavailable"])
  }

  func testDeviceSettingWriteReportsADifferentAuthoritativeState() {
    runtime.deviceSettings[NSNumber(value: FBAXDeviceSetting.reduceMotion.rawValue)] = false
    runtime.deviceSettingWriteOutcome = FBAXDeviceSettingOutcome.resolved(false)

    let response = FBAXBridgeHandleRequest(["verb": "settings-set", "setting": "reduce-motion", "enabled": true])

    assertEqualObjects(response, ["ok": true, "enabled": false])
    assertEqualObjects(runtime.deviceSettingWrites, [["setting": FBAXDeviceSetting.reduceMotion.rawValue, "enabled": true]])
  }

  func testBothWriteCommandsReportApplicationTimeoutWithTheOwningPid() {
    self.seedHitElement(withAttributes: [:])
    runtime.writeOutcome = FBAXWriteOutcome.applicationNotResponding()
    for request in [FBAXTestsPress(), ["verb": "setvalue", "x": 1, "y": 2, "value": "text"]] {
      assertEqualObjects(FBAXBridgeHandleRequest(request), ["ok": false, "error": "pid 4321 did not answer the write in time", "error_kind": "application_not_responding", "pid": kAppPid])
    }
    XCTAssertEqual(runtime.performCount, 1)
    XCTAssertEqual(runtime.setValueCount, 1)
  }

  // MARK: - Request-named attributes

  // The fake echoes what it holds, so only the ask can be asserted.
  func testARequestNamingAttributesIsReadWithThem() {
    let root = FBAXFakeElement.readable("UIApplication")
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    _ = FBAXBridgeHandleRequest(
      [
        "verb": "describe",
        "pid": NSNumber(value: kAppPid),
        "attributes": [kAXLabel, kAXVisiblePoint],
      ]
    )
    assertEqualObjects(runtime.lastReadAttributes, ([kAXLabel, kAXVisiblePoint, kAXChildren]))
  }

  func testARequestNamingNoAttributesIsReadWithTheDefaultList() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")

    FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    assertEqualObjects(
      runtime.lastReadAttributes,
      ([
        "XC_kAXXCAttributeElementType", "XC_kAXXCAttributeElementBaseType", kAXLabel,
        "XC_kAXXCAttributeValue", "XC_kAXXCAttributeIdentifier", kAXFrame,
        "XC_kAXXCAttributeAutomationType", kAXChildren,
      ]))
  }

  func testTheChildrenAttributeIsAlwaysRead() {
    let root = FBAXFakeElement.readable("UIApplication")
    root.children = [FBAXFakeElement.readable("XCUIElementTypeWindow")]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "attributes": [kAXLabel]])
    XCTAssertTrue(((runtime.lastReadAttributes as NSArray?)?.contains(kAXChildren) == true), "children is always read")
    assertEqualObjects(axValue(axValue(axValue(axValue(response, "tree"), kAXChildren), 0), kAXElementType), "XCUIElementTypeWindow")
  }

  func testAMalformedAttributeListFallsBackToTheDefault() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    let defaultCount = 8

    for malformed in ["XC_kAXXCAttributeLabel", [], [NSNumber(value: 123)], ["a": NSNumber(value: 1)]] as [Any] {
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "attributes": malformed])
      XCTAssertEqual((runtime.lastReadAttributes?.count ?? 0), defaultCount, "a \(String(describing: type(of: malformed))) list falls back")
    }

    _ = FBAXBridgeHandleRequest(
      [
        "verb": "describe",
        "pid": NSNumber(value: kAppPid),
        "attributes": [kAXLabel, NSNumber(value: 123), kAXVisiblePoint],
      ]
    )
    assertEqualObjects(runtime.lastReadAttributes, ([kAXLabel, kAXVisiblePoint, kAXChildren]), "a non-string member is dropped and the rest survives")
  }

  func testAWriteCanAssertOnlyOnAnAttributeItNames() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("XCUIElementTypeButton"), owningProcessIdentifier: kAppPid)

    let unnamed = FBAXBridgeHandleRequest(
      [
        "verb": "perform", "x": NSNumber(value: 10), "y": NSNumber(value: 20), "action": "press",
        "assertKey": kAXVisiblePoint, "assertValue": "anything",
      ]
    )
    assertEqualObjects(axValue(unnamed, "ok"), NSNumber(value: false), "an unfetched key is not assertable")
    assertEqualObjects(axValue(unnamed, "error_kind"), "bad_request")

    let named = FBAXBridgeHandleRequest(
      [
        "verb": "perform", "x": NSNumber(value: 10), "y": NSNumber(value: 20), "action": "press",
        "attributes": [kAXVisiblePoint],
        "assertKey": kAXVisiblePoint, "assertValue": "anything",
      ]
    )
    assertNotEqualObjects(axValue(named, "error_kind"), "bad_request", "naming the key makes it assertable")
  }

  // MARK: - Describe outcomes

  func testDescribeReadsTheTreeAndReportsThePid() {
    let root = FBAXFakeElement.readable("UIApplication")
    root.children = [FBAXFakeElement.readable("XCUIElementTypeWindow")]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "maxDepth": NSNumber(value: 5)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid))
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: false))
    assertEqualObjects(axValue(axValue(response, "tree"), kAXElementType), "UIApplication")
    assertEqualObjects(axValue(axValue(axValue(axValue(response, "tree"), kAXChildren), 0), kAXElementType), "XCUIElementTypeWindow")
  }

  func testDescribeWithNoApplicationElementIsAFailureNamingThePid() {
    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error"), "no application element for pid 4321")
  }

  func testDescribeOfAnUnreadableRootIsTaggedUnavailable() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.applicationUnavailable()

    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error_kind"), "application_unavailable")
    assertEqualObjects(axValue(response, "error"), "pid 4321 has no accessibility server")
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid))
  }

  func testDescribeOfARootThatDidNotAnswerIsTaggedNotResponding() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.applicationNotResponding()

    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error_kind"), "application_not_responding")
    assertEqualObjects(axValue(response, "error"), "pid 4321 did not answer the read of its element tree in time")
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid))
  }

  func testDescribeOfAFailedRootQuotesTheRuntimeOrSaysItReportedNothing() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.failed(FBAXTestsErrorWithCode(FBAXError.invalidUIElement.rawValue))
    let quoted = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    assertEqualObjects(axValue(quoted, "ok"), NSNumber(value: false))
    XCTAssertNil(axValue(quoted, "error_kind"))
    assertEqualObjects(axValue(quoted, "error"), "failed to read the element tree for pid 4321: runtime said no")

    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.failed(nil)
    let silent = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid)])
    assertEqualObjects(axValue(silent, "error"), "failed to read the element tree for pid 4321: the accessibility runtime reported no error")
  }

  func testAnUnreadableChildIsDroppedWithoutFailingTheRead() {
    let root = FBAXFakeElement.readable("UIApplication")
    root.children = [
      FBAXFakeElement.readable("first"),
      FBAXFakeElement.applicationUnavailable(),
      FBAXFakeElement.failed(FBAXTestsErrorWithCode(FBAXError.ipcTimeout.rawValue)),
      FBAXFakeElement.readable("last"),
    ]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "maxDepth": NSNumber(value: 5)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true), "an unreadable child must not fail the whole read")
    let children = axValue(axValue(response, "tree"), kAXChildren)
    XCTAssertEqual(axCount(children), 2, "only the readable children survive")
    assertEqualObjects(axValue(axValue(children, 0), kAXLabel), "first")
    assertEqualObjects(axValue(axValue(children, 1), kAXLabel), "last", "a later sibling must survive an earlier failure")
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: false), "a dropped child is not truncation")
  }

  func testDepthCapMarksTheReadTruncated() {
    let root = FBAXFakeElement.readable("UIApplication")
    let child = FBAXFakeElement.readable("XCUIElementTypeWindow")
    child.children = [FBAXFakeElement.readable("XCUIElementTypeButton")]
    root.children = [child]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let cut = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "maxDepth": NSNumber(value: 1)])
    assertEqualObjects(axValue(cut, "truncated"), NSNumber(value: true))
    XCTAssertEqual(axCount(axValue(axValue(axValue(axValue(cut, "tree"), kAXChildren), 0), kAXChildren)), 0, "descent stopped at the cap")

    let whole = FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "maxDepth": NSNumber(value: 5)])
    assertEqualObjects(axValue(whole, "truncated"), NSNumber(value: false))
    XCTAssertEqual(axCount(axValue(axValue(axValue(axValue(whole, "tree"), kAXChildren), 0), kAXChildren)), 1)
  }

  func testNodeBudgetExhaustionMarksTheReadTruncated() {
    let root = FBAXFakeElement.readable("UIApplication")
    root.children = [
      FBAXFakeElement.readable("first"),
      FBAXFakeElement.readable("second"),
      FBAXFakeElement.readable("third"),
    ]
    runtime.applicationElements[NSNumber(value: kAppPid)] = root

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "pid": NSNumber(value: kAppPid), "maxDepth": NSNumber(value: 5), "maxNodes": NSNumber(value: 2)])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "truncated"), NSNumber(value: true))
    XCTAssertEqual(axCount(axValue(axValue(response, "tree"), kAXChildren)), 2, "the walk stopped when the budget ran out")
  }

  // MARK: - Frontmost dispatch

  func testCenterPointResolvesTheAnchorsOwnerAndIsEchoedBack() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("leaf"), owningProcessIdentifier: kAppPid)
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")

    let response = FBAXBridgeHandleRequest(
      ["verb": "describe", "x": NSNumber(value: 201), "y": NSNumber(value: 437), "method": "center-point"]
    )
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: true))
    assertEqualObjects(axValue(response, "pid"), NSNumber(value: kAppPid))
    assertEqualObjects(axValue(response, "method"), "center-point")
    XCTAssertEqual(runtime.hitTestCount, 1)
    XCTAssertEqual(runtime.lastHitTestProcessIdentifier, 0, "the frontmost hit-test is display-wide")
    XCTAssertEqual(runtime.lastHitTestPoint.x, 201, "the request's anchor is what gets hit-tested")
  }

  func testEachFrontmostMethodIsDispatchedToItsOwnResolverAndEchoedBack() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")
    runtime.windowServerOutcome = FBAXFrontmostOutcome.resolved(kAppPid)
    runtime.runningBoardOutcome = FBAXFrontmostOutcome.resolved(kAppPid)

    let windowServer =
      FBAXBridgeHandleRequest(["verb": "describe", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "method": "window-server"])
    assertEqualObjects(axValue(windowServer, "method"), "window-server")
    XCTAssertEqual(runtime.windowServerCount, 1)
    XCTAssertEqual(runtime.runningBoardCount, 0)
    XCTAssertEqual(runtime.hitTestCount, 0)

    let runningBoard =
      FBAXBridgeHandleRequest(["verb": "describe", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "method": "runningboard"])
    assertEqualObjects(axValue(runningBoard, "method"), "runningboard")
    XCTAssertEqual(runtime.runningBoardCount, 1)
    XCTAssertEqual(runtime.windowServerCount, 1, "the window-server resolver must not run again")
  }

  func testAFailedResolverDoesNotFallBackToAnotherMethod() {
    runtime.windowServerOutcome = FBAXFrontmostOutcome.unresolved("the window server did not answer")
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("leaf"), owningProcessIdentifier: kAppPid)
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")

    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "method": "window-server"])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error"), "the window server did not answer")
    // A strategy that could not answer is about the strategy, not about any one application — so it is its
    // own kind, and must not be reported as an application the caller should go and reconfigure.
    assertEqualObjects(axValue(response, "error_kind"), "frontmost_unresolved")
    XCTAssertEqual(runtime.hitTestCount, 0, "no fallback to the positional resolver")
    XCTAssertEqual(runtime.runningBoardCount, 0, "no fallback to RunningBoard")
  }

  func testCenterPointCarriesEachNonResolvingOutcomeThroughAsItsOwnKind() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.empty()
    let empty = FBAXBridgeHandleRequest(
      ["verb": "describe", "x": NSNumber(value: 9999), "y": NSNumber(value: 9999), "method": "center-point"]
    )
    assertEqualObjects(axValue(empty, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(empty, "error"), "system-wide hit-test at (9999.0, 9999.0) found no element")
    assertEqualObjects(axValue(empty, "error_kind"), "frontmost_unresolved")

    runtime.hitTestOutcome = FBAXHitTestOutcome.applicationUnavailable()
    let unavailable = FBAXBridgeHandleRequest(
      ["verb": "describe", "x": NSNumber(value: 5), "y": NSNumber(value: 6), "method": "center-point"]
    )
    assertEqualObjects(axValue(unavailable, "error"), "no accessibility server answered the system-wide hit-test at (5.0, 6.0)")
    assertEqualObjects(axValue(unavailable, "error_kind"), "application_unavailable")
    XCTAssertNil(axValue(unavailable, "pid"), "a frontmost query that resolved nothing has no process to name")

    runtime.hitTestOutcome = FBAXHitTestOutcome.applicationNotResponding()
    let notResponding = FBAXBridgeHandleRequest(
      ["verb": "describe", "x": NSNumber(value: 5), "y": NSNumber(value: 6), "method": "center-point"]
    )
    assertEqualObjects(axValue(notResponding, "error"), "the application at (5.0, 6.0) did not answer the system-wide hit-test in time")
    assertEqualObjects(axValue(notResponding, "error_kind"), "application_not_responding")
  }

  func testAnUnsupportedFrontmostMethodConsultsNoResolver() {
    let response =
      FBAXBridgeHandleRequest(["verb": "describe", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "method": "not-a-method"])
    assertEqualObjects(axValue(response, "ok"), NSNumber(value: false))
    assertEqualObjects(axValue(response, "error"), "unsupported frontmost method: not-a-method")
    assertEqualObjects(axValue(response, "error_kind"), "frontmost_unresolved")
    XCTAssertEqual(runtime.hitTestCount, 0)
    XCTAssertEqual(runtime.windowServerCount, 0)
    XCTAssertEqual(runtime.runningBoardCount, 0)
  }

  func testANonStringMethodFallsBackToTheDefault() {
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("leaf"), owningProcessIdentifier: kAppPid)
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("UIApplication")

    runtime.windowServerOutcome = FBAXFrontmostOutcome.resolved(kAppPid)

    let response = FBAXBridgeHandleRequest(["verb": "describe", "x": NSNumber(value: 1), "y": NSNumber(value: 2), "method": NSNumber(value: 7)])
    assertEqualObjects(axValue(response, "method"), "window-server")
    XCTAssertEqual(runtime.windowServerCount, 1)
  }

  // MARK: - Decoded request coercion

  private var flagCoercionCases: [(Any, Bool)] {
    [("YES", true), ("1", true), ("false", false), ("0", false), (NSNumber(value: 2), true), (NSNumber(value: -1), true), (NSNumber(value: 0), false)]
  }

  func testSnapshotFlagPreservesFoundationBooleanCoercion() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("root")
    for (value, enabled) in flagCoercionCases {
      let before = runtime.snapshotCount

      let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid, "snapshotTree": value])

      assertEqualObjects(response["ok"], true)
      assertEqualObjects(axValue(response["tree"], kAXLabel), "root")
      XCTAssertEqual(runtime.snapshotCount - before, enabled ? 1 : 0)
    }
  }

  func testTranslatorFlagPreservesFoundationBooleanCoercion() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("original")
    runtime.translatorAttributeValues = [33: "translated"]
    for (value, enabled) in flagCoercionCases {
      let before = runtime.translatorReadCount

      let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid, "translatorVocabulary": value])

      assertEqualObjects(response["ok"], true)
      assertEqualObjects(axValue(response["tree"], kAXLabel), enabled ? "translated" : "original")
      XCTAssertEqual(runtime.translatorReadCount - before, enabled ? 2 : 0)
    }
  }

  func testExplanationFlagPreservesFoundationBooleanCoercion() {
    _ = unreachableRoot()
    runtime.hitTestOutcome = FBAXHitTestOutcome.hit(FBAXFakeElement.readable("overlay"), owningProcessIdentifier: 9000)
    for (value, enabled) in flagCoercionCases {
      let before = runtime.hitTestCount

      let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid, "explainUnreachable": value])

      assertEqualObjects(response["ok"], true)
      XCTAssertEqual(axValue(response["tree"], "FBExplainedBy") != nil, enabled)
      XCTAssertEqual(runtime.hitTestCount - before, enabled ? 1 : 0)
    }
  }

  func testMalformedTraversalFlagsReturnPlainErrorsAndRecover() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("root")
    for flag in ["snapshotTree", "translatorVocabulary", "explainUnreachable"] {
      for value in [NSNull(), [], [:]] as [Any] {
        let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid, flag: value])

        assertEqualObjects(response["ok"], false)
        XCTAssertNil(response["error_kind"])
        XCTAssertNil(response["tree"])
        XCTAssertTrue((response["error"] as? String)?.hasPrefix("the reader raised while answering:") == true)
        XCTAssertTrue((response["error"] as? String)?.contains("boolValue") == true)
        assertEqualObjects(FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid])["ok"], true)
      }
    }
    XCTAssertEqual(runtime.snapshotCount, 0)
    XCTAssertEqual(runtime.translatorReadCount, 0)
    XCTAssertEqual(runtime.hitTestCount, 0)
  }

  func testSnapshotSelectionDoesNotInterpretUnusedTraversalFlags() {
    runtime.applicationElements[NSNumber(value: kAppPid)] = FBAXFakeElement.readable("root")

    let response = FBAXBridgeHandleRequest(["verb": "describe", "pid": kAppPid, "snapshotTree": "YES", "translatorVocabulary": NSNull(), "explainUnreachable": NSNull()])

    assertEqualObjects(response["ok"], true)
    assertEqualObjects(axValue(response["tree"], kAXLabel), "root")
    XCTAssertEqual(runtime.snapshotCount, 1)
    XCTAssertEqual(runtime.translatorReadCount, 0)
    XCTAssertEqual(runtime.hitTestCount, 0)
  }

  func testUnsupportedVerbPreservesFoundationValueDescriptions() {
    let cases: [(Any, String)] = [(123, "123"), (NSNull(), "<null>"), (["describe"], "(\n    describe\n)"), (["a": 1], "{\n    a = 1;\n}")]
    for (value, description) in cases {
      let response = FBAXBridgeHandleRequest(["verb": value])

      assertEqualObjects(response, ["ok": false, "error_kind": "bad_request", "error": "unsupported verb: \(description)"])
    }
    assertEqualObjects(runtime.operations, [])
  }

  func testUnsupportedActionPreservesFoundationValueDescriptions() {
    let cases: [(Any, String)] = [(123, "123"), (NSNull(), "<null>"), (["press"], "(\n    press\n)"), (["a": 1], "{\n    a = 1;\n}")]
    for (value, description) in cases {
      let response = FBAXBridgeHandleRequest(["verb": "perform", "action": value, "x": 1, "y": 2])

      assertEqualObjects(response, ["ok": false, "error_kind": "bad_request", "error": "unsupported action: \(description)"])
    }
    assertEqualObjects(runtime.operations, [])
  }

}

private func axValue(_ object: Any?, _ key: AnyHashable, file: StaticString = #filePath, line: UInt = #line) -> Any? {
  if let dictionary = object as? NSDictionary { return dictionary[key] }
  if let array = object as? NSArray, let index = key as? Int { return array[index] }
  if object != nil { XCTFail("Expected a dictionary or array", file: file, line: line) }
  return nil
}

private func assertEqualObjects(_ lhs: Any?, _ rhs: Any?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
  if let lhs {
    XCTAssertTrue((lhs as AnyObject as? NSObject)?.isEqual(rhs) == true, message, file: file, line: line)
  } else {
    XCTAssertNil(rhs, message, file: file, line: line)
  }
}

private func assertNotEqualObjects(_ lhs: Any?, _ rhs: Any?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
  if let lhs {
    XCTAssertFalse((lhs as AnyObject as? NSObject)?.isEqual(rhs) == true, message, file: file, line: line)
  } else {
    XCTAssertNotNil(rhs, message, file: file, line: line)
  }
}

private func axCount(_ object: Any?, file: StaticString = #filePath, line: UInt = #line) -> Int {
  guard let object else { return 0 }
  if let array = object as? NSArray { return array.count }
  XCTFail("Expected an array", file: file, line: line)
  return 0

}
