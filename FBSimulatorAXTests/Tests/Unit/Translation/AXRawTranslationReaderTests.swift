/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import AccessibilityPlatformTranslation
import AppKit
@testable import FBSimulatorAX
import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
import XCTest

final class AXRawTranslationReaderTests: XCTestCase {

  private static let pid: pid_t = 4242

  private static func reader(
    _ transport: AXRawTranslationTransportDouble, collector: AccessibilityProfilingCollector = AccessibilityProfilingCollector()
  ) -> AXRawTranslationReader {
    AXRawTranslationReader(
      transport: transport, clientType: .xctest, timeout: 1, collector: collector, token: "token")
  }

  private static func reference(_ objectID: UInt64) -> AXPTranslationObjectDouble {
    AXPTranslationObjectDouble(pid: pid, objectID: objectID)
  }

  private static let defaultPlan = AXReadPlan(keys: AXKeys.defaultSet, depth: .unlimited)

  // MARK: - Round trips

  func testEachElementIsReadInOneMultipleAttributeRequestCarryingTheReadsClient() throws {
    let transport = AXRawTranslationTransportDouble(elements: [
      1: [.frame: NSValue(rect: NSRect(x: 0, y: 0, width: 402, height: 874)), .role: 1, .children: [Self.reference(2), Self.reference(3)]],
      2: [.frame: NSValue(rect: NSRect(x: 0, y: 100, width: 402, height: 44)), .role: 2, .label: "General"],
      3: [.frame: NSValue(rect: NSRect(x: 0, y: 144, width: 402, height: 44)), .role: 14, .label: "About"],
    ])
    let collector = AccessibilityProfilingCollector()

    let root = try Self.reader(transport, collector: collector).read(Self.reference(1), plan: Self.defaultPlan)

    XCTAssertEqual(transport.requestedObjectIDs, [1, 2, 3])
    XCTAssertEqual(transport.requests.map(\.requestType), [5, 5, 5])
    XCTAssertEqual(transport.requests.map(\.clientType), [4, 4, 4])
    XCTAssertEqual(collector.xpcCallCount, 3)
    XCTAssertEqual(root.children.map(\.label), ["General", "About"])
    XCTAssertEqual(root.children.map(\.pid), [Self.pid, Self.pid])
  }

  func testARoleDescriptionAsksForWhatItsFallbackReadsInTheSameRequest() {
    let attributes = AXRawTranslationReader.attributes(
      for: AXReadPlan(attributes: [.roleDescription], depth: .limited(0)), readingChildren: false)
    XCTAssertEqual(attributes, [.frame, .roleDescription, .role, .subrole, .isRemoteElement])
  }

  func testAttributesWithoutATranslatorNumberAreNotAskedFor() {
    let attributes = AXRawTranslationReader.attributes(
      for: AXReadPlan(attributes: [.title, .required, .hidden, .customActions], depth: .limited(0)), readingChildren: true)
    XCTAssertEqual(attributes, [.frame, .customActions, .children])
  }

  func testAnElementListedAmongItsOwnDescendantsIsReadOnce() throws {
    let transport = AXRawTranslationTransportDouble(elements: [
      1: [.role: 1, .children: [Self.reference(2)]],
      2: [.role: 5, .children: [Self.reference(2), Self.reference(1)]],
    ])

    let root = try Self.reader(transport).read(Self.reference(1), plan: Self.defaultPlan)

    XCTAssertEqual(transport.requestedObjectIDs, [1, 2])
    XCTAssertEqual(root.children.count, 1)
    XCTAssertEqual(root.children.first?.children.count, 0)
  }

  func testAChildListedTwiceAmongItsParentsChildren() throws {
    // A scroll view's scroll bar is listed twice among the scroll view's children for the automation tree, and
    // the platform element's batched read reports it at both places.
    let transport = AXRawTranslationTransportDouble(elements: [
      1: [.role: 1, .children: [Self.reference(2)]],
      2: [.role: 10, .children: [Self.reference(3), Self.reference(3)]],
      3: [.role: 13, .label: "Vertical scroll bar"],
    ])

    let root = try Self.reader(transport).read(Self.reference(1), plan: Self.defaultPlan)

    XCTAssertEqual(root.children.first?.children.map(\.label), ["Vertical scroll bar", "Vertical scroll bar"])
    XCTAssertEqual(transport.requestedObjectIDs, [1, 2, 3, 3])
  }

  func testAnUnansweredElementStopsTheRead() {
    let transport = AXRawTranslationTransportDouble(elements: [:])

    XCTAssertThrowsError(try Self.reader(transport).read(Self.reference(9), plan: Self.defaultPlan)) { error in
      guard case AccessibilityError.serviceNotAnswering(.request(kind: "multiple_attribute", timeout: 1), _, _) = error else {
        return XCTFail("expected an unanswered multiple-attribute request, got \(error)")
      }
    }
  }

  // MARK: - Conversion

  private static func decoded(_ values: [BridgeAXTranslatorAttribute: Any], plan: AXReadPlan) -> AXRawTranslationReader.Decoded {
    let answer = BridgeAXTranslatorAnswer(
      resultData: Dictionary(uniqueKeysWithValues: values.map { (NSNumber(value: $0.key.rawValue), $0.value) }) as NSDictionary)
    return AXRawTranslationReader.Decoded(answer, plan: plan)
  }

  private static let everything = AXReadPlan(attributes: Set(AXReadPlan.Attribute.allCases), depth: .limited(0))

  func testRolesAndSubrolesAreNamedAsAppKitNamesThem() {
    let decoded = Self.decoded([.role: 3, .subrole: 3], plan: Self.everything)
    XCTAssertEqual(decoded.role, "AXCheckBox")
    XCTAssertEqual(decoded.subrole, "AXSwitch")
  }

  func testARemoteElementIsAGroup() {
    XCTAssertEqual(Self.decoded([.role: 2, .isRemoteElement: true], plan: Self.everything).role, "AXGroup")
  }

  func testUnknownRoleAndSubroleNumbersReadAsNone() {
    let decoded = Self.decoded([.role: 0, .subrole: 0], plan: Self.everything)
    XCTAssertNil(decoded.role)
    XCTAssertNil(decoded.subrole)
  }

  func testTheApplicationsOwnRoleDescriptionWinsWhenItGivesOne() {
    XCTAssertEqual(Self.decoded([.role: 2, .roleDescription: "back button"], plan: Self.everything).roleDescription, "back button")
  }

  func testAnEmptyRoleDescriptionFallsBackToAppKitsDescriptionOfTheRoleAndSubrole() {
    XCTAssertEqual(
      Self.decoded([.role: 2, .roleDescription: ""], plan: Self.everything).roleDescription,
      NSAccessibility.Role.button.description(with: nil))
    XCTAssertEqual(
      Self.decoded([.role: 15, .subrole: 1], plan: Self.everything).roleDescription,
      NSAccessibility.Role.textField.description(with: .searchField))
  }

  func testAGenericElementHasAnEmptyRoleDescription() {
    XCTAssertEqual(Self.decoded([.role: 4], plan: Self.everything).roleDescription, "")
  }

  func testValuesPassThroughAndFlagsReadFalseWhenAbsent() {
    let decoded = Self.decoded(
      [
        .frame: NSValue(rect: NSRect(x: 1, y: 2, width: 3, height: 4)), .label: "Wi-Fi", .identifier: "wifi", .value: "On",
        .help: "", .placeholderValue: "Search", .traits: NSNumber(value: 1 << 0), .isEnabled: NSNumber(value: 1),
      ],
      plan: Self.everything)
    XCTAssertEqual(decoded.frame, NSRect(x: 1, y: 2, width: 3, height: 4))
    XCTAssertEqual(decoded.label, "Wi-Fi")
    XCTAssertEqual(decoded.identifier, "wifi")
    XCTAssertEqual(decoded.value as? String, "On")
    XCTAssertEqual(decoded.help, "")
    XCTAssertEqual(decoded.placeholder, "Search")
    XCTAssertEqual(decoded.traits, AXExtractTraits(1 << 0))
    XCTAssertEqual(decoded.isEnabled, true)
    XCTAssertEqual(decoded.isFocused, false)
    XCTAssertEqual(decoded.isExpanded, false)
  }

  func testUnplannedAttributesStayUnread() {
    let decoded = Self.decoded([.role: 2, .label: "General"], plan: AXReadPlan(attributes: [.label], depth: .limited(0)))
    XCTAssertEqual(decoded.label, "General")
    XCTAssertNil(decoded.role)
    XCTAssertNil(decoded.isEnabled)
  }

  func testAttributesTheTranslatorDoesNotAnswerTakeTheirDefaults() throws {
    let transport = AXRawTranslationTransportDouble(elements: [1: [.role: 2]])
    let snapshot = try Self.reader(transport).read(Self.reference(1), plan: Self.everything)
    XCTAssertNil(snapshot.title)
    XCTAssertEqual(snapshot.isRequired, false)
    XCTAssertEqual(snapshot.isHidden, false)
    XCTAssertEqual(snapshot.customActionNames, [])
  }

  func testCustomActionsAreNamedFromTheTranslatorsAnswer() throws {
    let transport = AXRawTranslationTransportDouble(elements: [
      1: [
        .role: 2,
        .customActions: [
          ["AXPCustomActionName": "Edit mode", "AXPCustomActionIdentifier": "Name:Edit mode"],
          ["AXPCustomActionName": "Today", "AXPCustomActionIdentifier": "Name:Today"],
        ],
      ]
    ])
    let snapshot = try Self.reader(transport).read(Self.reference(1), plan: AXReadPlan(attributes: [.customActions], depth: .limited(0)))
    XCTAssertEqual(snapshot.customActionNames, ["Edit mode", "Today"])
  }

  // MARK: - Request

  func testARawReadsActionHandleForAnElementTheTranslatorHasAlreadyBuilt() throws {
    // The translator built this element for an earlier read, which has since closed.
    let cached = AccessibilityTestElementBuilder.button(withLabel: "OK", identifier: nil, frame: .zero)
    cached.translation = Self.reference(2)
    cached.translation.bridgeDelegateToken = "an earlier read"
    let translator = AXPTranslatorDouble()
    translator.cachedElementsByObjectID = [2: cached]
    let root = AccessibilityTestElementBuilder.application(withLabel: "App", frame: .zero, children: [])
    root.translation = Self.reference(1)
    let request = AXTranslationRequest(
      kind: .frontmostApplication,
      transport: AXRawTranslationTransportDouble(elements: [
        1: [.role: 1, .children: [Self.reference(2)]],
        2: [.role: 2, .label: "OK"],
      ]))
    request.translator = unsafeBitCast(translator as AnyObject, to: AXPTranslator.self)

    let snapshot = try request.snapshot(of: root.translation, plan: AXReadPlan(attributes: [.label], depth: .limited(1)))

    let handle = try XCTUnwrap(snapshot.children.first?.handle)
    XCTAssertTrue(request.element(for: handle) as AnyObject === cached, "acting builds the translator's element")
    XCTAssertEqual(cached.translation.bridgeDelegateToken, request.token, "an action on the handle reaches this read")
  }
}
