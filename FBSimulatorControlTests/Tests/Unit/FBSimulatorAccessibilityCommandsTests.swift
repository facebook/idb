/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorAccessibilityCommandsTests: XCTestCase {

  // MARK: - Properties

  private var fixture: FBAccessibilityTestFixture?
  private var simulator: FBSimulator!

  // MARK: - Helpers

  /// All properties accessed during full serialization (no key filtering)
  private var allSerializationProperties: Set<String> {
    Set([
      "accessibilityLabel",
      "accessibilityIdentifier",
      "accessibilityValue",
      "accessibilityTitle",
      "accessibilityHelp",
      "accessibilityRole",
      "accessibilityRoleDescription",
      "accessibilitySubrole",
      "accessibilityFrame",
      "accessibilityEnabled",
      "accessibilityRequired",
      "accessibilityCustomActions",
      "accessibilityChildren",
      "translation",
    ])
  }

  /// Properties accessed for single-element serialization (no children recursion)
  private var singleElementSerializationProperties: Set<String> {
    Set([
      "accessibilityLabel",
      "accessibilityIdentifier",
      "accessibilityValue",
      "accessibilityTitle",
      "accessibilityHelp",
      "accessibilityRole",
      "accessibilityRoleDescription",
      "accessibilitySubrole",
      "accessibilityFrame",
      "accessibilityEnabled",
      "accessibilityRequired",
      "accessibilityCustomActions",
      "translation",
    ])
  }

  /// Properties accessed for AXLabel and frame key filtering
  private var labelAndFrameFilteredProperties: Set<String> {
    Set([
      "accessibilityLabel",
      "accessibilityFrame",
      "accessibilityChildren", // Always accessed for recursion
      "translation", // Always accessed for pid
    ])
  }

  /// Properties accessed for AXLabel, type, and frame key filtering
  private var labelTypeFrameFilteredProperties: Set<String> {
    Set([
      "accessibilityLabel",
      "accessibilityRole", // Needed for "type" derivation
      "accessibilityFrame",
      "translation", // Always accessed for pid
    ])
  }

  /// Properties accessed during tap operation (includes action validation)
  private var tapOperationProperties: Set<String> {
    Set([
      "accessibilityLabel",
      "accessibilityIdentifier",
      "accessibilityValue",
      "accessibilityTitle",
      "accessibilityHelp",
      "accessibilityRole",
      "accessibilityRoleDescription",
      "accessibilitySubrole",
      "accessibilityFrame",
      "accessibilityEnabled",
      "accessibilityRequired",
      "accessibilityCustomActions",
      "accessibilityChildren",
      "accessibilityActionNames", // Accessed for action validation
      "translation",
    ])
  }

  /// Asserts profiling data metrics with expected counts
  private func assertProfilingData(
    _ profilingData: FBAccessibilityProfilingData?,
    expectedElements: Int64,
    expectedAttributeFetches: Int64
  ) {
    XCTAssertNotNil(profilingData, "Profiling data should be present")
    guard let profilingData else { return }
    XCTAssertEqual(profilingData.elementCount, expectedElements, "Element count mismatch")
    XCTAssertEqual(profilingData.attributeFetchCount, expectedAttributeFetches, "Attribute fetch count mismatch")
    XCTAssertGreaterThanOrEqual(profilingData.xpcCallCount, 0, "XPC call count should be non-negative")
    XCTAssertGreaterThanOrEqual(profilingData.translationDuration, 0, "Translation duration should be non-negative")
    XCTAssertGreaterThanOrEqual(profilingData.elementConversionDuration, 0, "Element conversion duration should be non-negative")
    XCTAssertGreaterThanOrEqual(profilingData.serializationDuration, 0, "Serialization duration should be non-negative")
  }

  // MARK: - Core Test Helpers

  /// Core test for flat output - returns response for optional profiling assertions
  @discardableResult
  private func assertFlatOutput(
    withProfiling enableProfiling: Bool,
    childElements: [FBSimulatorControlTests_AXPMacPlatformElement_Double]
  ) async throws -> FBAccessibilityElementsResponse {
    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.nestedFormat = false
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try! element.serialize(with: options)
    element.close()

    let result = response.elements as! [Any]
    XCTAssertEqual(result.count, 4, "Flat format should have 4 elements (root + 3 children)")

    // Expected full output for all 4 elements
    let expected: [[String: Any]] = [
      [
        "AXLabel": "App Window",
        "AXFrame": "{{0, 0}, {390, 844}}",
        "AXValue": NSNull(),
        "AXUniqueId": NSNull(),
        "type": "Application",
        "title": NSNull(),
        "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
        "help": NSNull(),
        "enabled": true,
        "custom_actions": [] as [Any],
        "role": "AXApplication",
        "role_description": NSNull(),
        "subrole": NSNull(),
        "content_required": false,
        "pid": 12345,
        "traits": NSNull(),
      ],
      [
        "AXLabel": "Confirm Action",
        "AXFrame": "{{20, 100}, {350, 30}}",
        "AXValue": NSNull(),
        "AXUniqueId": NSNull(),
        "type": "StaticText",
        "title": NSNull(),
        "frame": ["x": 20, "y": 100, "width": 350, "height": 30],
        "help": NSNull(),
        "enabled": true,
        "custom_actions": [] as [Any],
        "role": "AXStaticText",
        "role_description": NSNull(),
        "subrole": NSNull(),
        "content_required": false,
        "pid": 12345,
        "traits": NSNull(),
      ],
      [
        "AXLabel": "OK",
        "AXFrame": "{{20, 750}, {150, 44}}",
        "AXValue": NSNull(),
        "AXUniqueId": "ok_button",
        "type": "Button",
        "title": NSNull(),
        "frame": ["x": 20, "y": 750, "width": 150, "height": 44],
        "help": NSNull(),
        "enabled": true,
        "custom_actions": [] as [Any],
        "role": "AXButton",
        "role_description": NSNull(),
        "subrole": NSNull(),
        "content_required": false,
        "pid": 12345,
        "traits": NSNull(),
      ],
      [
        "AXLabel": "Cancel",
        "AXFrame": "{{200, 750}, {150, 44}}",
        "AXValue": NSNull(),
        "AXUniqueId": "cancel_button",
        "type": "Button",
        "title": NSNull(),
        "frame": ["x": 200, "y": 750, "width": 150, "height": 44],
        "help": NSNull(),
        "enabled": true,
        "custom_actions": [] as [Any],
        "role": "AXButton",
        "role_description": NSNull(),
        "subrole": NSNull(),
        "content_required": false,
        "pid": 12345,
        "traits": NSNull(),
      ],
    ]

    XCTAssertEqual(result as NSArray, expected as NSArray)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(result))

    // Verify property access tracking - all serialization properties should be accessed
    XCTAssertEqual(
      fixture!.rootElement!.accessedProperties as! Set<String>,
      allSerializationProperties,
      "All serialization properties should be accessed for root element"
    )
    for child in childElements {
      XCTAssertEqual(
        child.accessedProperties as! Set<String>,
        allSerializationProperties,
        "All serialization properties should be accessed for child element"
      )
    }

    return response
  }

  /// Core test for element at point - returns response for optional profiling assertions
  @discardableResult
  private func assertElementAtPoint(
    withProfiling enableProfiling: Bool,
    point: CGPoint,
    element elementDouble: FBSimulatorControlTests_AXPMacPlatformElement_Double,
    expected: [String: Any]
  ) async throws -> FBAccessibilityElementsResponse {
    fixture!.translator.macPlatformElementResult = elementDouble

    let element = try await simulator.accessibilityElement(at: point)

    var options = FBAccessibilityRequestOptions()
    options.nestedFormat = false
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try! element.serialize(with: options)
    element.close()

    let result = response.elements as! [String: Any]
    XCTAssertEqual(result as NSDictionary, expected as NSDictionary)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(result))

    // Verify property access tracking - single element doesn't recurse children
    XCTAssertEqual(
      elementDouble.accessedProperties as! Set<String>,
      singleElementSerializationProperties,
      "Single element at point should access all properties except children"
    )

    return response
  }

  /// Core test for nested output - returns response for optional profiling assertions
  @discardableResult
  private func assertNestedOutput(
    withProfiling enableProfiling: Bool,
    childElements: [FBSimulatorControlTests_AXPMacPlatformElement_Double]
  ) async throws -> FBAccessibilityElementsResponse {
    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.nestedFormat = true
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try! element.serialize(with: options)
    element.close()

    let result = response.elements as! [Any]
    XCTAssertEqual(result.count, 1, "Nested format should have 1 root element")

    // Expected full nested output
    let expected: [[String: Any]] = [
      [
        "AXLabel": "App Window",
        "AXFrame": "{{0, 0}, {390, 844}}",
        "AXValue": NSNull(),
        "AXUniqueId": NSNull(),
        "type": "Application",
        "title": NSNull(),
        "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
        "help": NSNull(),
        "enabled": true,
        "custom_actions": [] as [Any],
        "role": "AXApplication",
        "role_description": NSNull(),
        "subrole": NSNull(),
        "content_required": false,
        "pid": 12345,
        "traits": NSNull(),
        "children": [
          [
            "AXLabel": "Confirm Action",
            "AXFrame": "{{20, 100}, {350, 30}}",
            "AXValue": NSNull(),
            "AXUniqueId": NSNull(),
            "type": "StaticText",
            "title": NSNull(),
            "frame": ["x": 20, "y": 100, "width": 350, "height": 30],
            "help": NSNull(),
            "enabled": true,
            "custom_actions": [] as [Any],
            "role": "AXStaticText",
            "role_description": NSNull(),
            "subrole": NSNull(),
            "content_required": false,
            "pid": 12345,
            "traits": NSNull(),
            "children": [] as [Any],
          ] as [String: Any],
          [
            "AXLabel": "OK",
            "AXFrame": "{{20, 750}, {150, 44}}",
            "AXValue": NSNull(),
            "AXUniqueId": "ok_button",
            "type": "Button",
            "title": NSNull(),
            "frame": ["x": 20, "y": 750, "width": 150, "height": 44],
            "help": NSNull(),
            "enabled": true,
            "custom_actions": [] as [Any],
            "role": "AXButton",
            "role_description": NSNull(),
            "subrole": NSNull(),
            "content_required": false,
            "pid": 12345,
            "traits": NSNull(),
            "children": [] as [Any],
          ] as [String: Any],
          [
            "AXLabel": "Cancel",
            "AXFrame": "{{200, 750}, {150, 44}}",
            "AXValue": NSNull(),
            "AXUniqueId": "cancel_button",
            "type": "Button",
            "title": NSNull(),
            "frame": ["x": 200, "y": 750, "width": 150, "height": 44],
            "help": NSNull(),
            "enabled": true,
            "custom_actions": [] as [Any],
            "role": "AXButton",
            "role_description": NSNull(),
            "subrole": NSNull(),
            "content_required": false,
            "pid": 12345,
            "traits": NSNull(),
            "children": [] as [Any],
          ] as [String: Any],
        ] as [[String: Any]],
      ]
    ]

    XCTAssertEqual(result as NSArray, expected as NSArray)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(result))

    // Verify property access tracking - all serialization properties should be accessed
    XCTAssertEqual(
      fixture!.rootElement!.accessedProperties as! Set<String>,
      allSerializationProperties,
      "All serialization properties should be accessed for root element"
    )
    for child in childElements {
      XCTAssertEqual(
        child.accessedProperties as! Set<String>,
        allSerializationProperties,
        "All serialization properties should be accessed for child element"
      )
    }

    return response
  }

  /// Core test for key filtering - returns response for optional profiling assertions
  @discardableResult
  private func assertKeyFiltering(
    withProfiling enableProfiling: Bool,
    childElements: [FBSimulatorControlTests_AXPMacPlatformElement_Double]
  ) async throws -> FBAccessibilityElementsResponse {
    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.nestedFormat = false
    options.keys = Set([FBAXKeys.label, .frameDict])
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try! element.serialize(with: options)
    element.close()

    let result = response.elements as! [Any]
    XCTAssertEqual(result.count, 4, "Should have 4 elements")

    // Expected output with only the requested keys
    let expected: [[String: Any]] = [
      [
        "AXLabel": "App Window",
        "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
      ],
      [
        "AXLabel": "Confirm Action",
        "frame": ["x": 20, "y": 100, "width": 350, "height": 30],
      ],
      [
        "AXLabel": "OK",
        "frame": ["x": 20, "y": 750, "width": 150, "height": 44],
      ],
      [
        "AXLabel": "Cancel",
        "frame": ["x": 200, "y": 750, "width": 150, "height": 44],
      ],
    ]

    XCTAssertEqual(result as NSArray, expected as NSArray)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(result))

    // Verify property access tracking - only filtered properties should be accessed
    XCTAssertEqual(
      fixture!.rootElement!.accessedProperties as! Set<String>,
      labelAndFrameFilteredProperties,
      "Only label and frame properties should be accessed for root element"
    )
    for child in childElements {
      XCTAssertEqual(
        child.accessedProperties as! Set<String>,
        labelAndFrameFilteredProperties,
        "Only label and frame properties should be accessed for child element"
      )
    }

    return response
  }

  /// Core test for element at point with key filtering - returns response for optional profiling assertions
  @discardableResult
  private func assertElementAtPointKeyFiltering(withProfiling enableProfiling: Bool) async throws -> FBAccessibilityElementsResponse {
    // Configure objectAtPointResult to return the title label element
    let titleLabel = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "Confirm Action",
      frame: NSRect(x: 20, y: 100, width: 350, height: 30)
    )
    fixture!.translator.macPlatformElementResult = titleLabel

    let element = try await simulator.accessibilityElement(at: CGPoint(x: 100, y: 115))

    var options = FBAccessibilityRequestOptions()
    options.nestedFormat = false
    options.keys = Set([FBAXKeys.label, .type, .frameDict])
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try! element.serialize(with: options)
    element.close()

    let result = response.elements as! [String: Any]

    let expected: [String: Any] = [
      "AXLabel": "Confirm Action",
      "type": "StaticText",
      "frame": ["x": 20, "y": 100, "width": 350, "height": 30],
    ]

    XCTAssertEqual(result as NSDictionary, expected as NSDictionary)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(result))

    // Verify property access tracking - only filtered properties should be accessed
    XCTAssertEqual(
      titleLabel.accessedProperties as! Set<String>,
      labelTypeFrameFilteredProperties,
      "Only label, role (for type), and frame properties should be accessed with key filtering"
    )

    return response
  }

  // MARK: - Setup/Teardown

  override func tearDown() {
    simulator = nil
    fixture?.tearDown()
    fixture = nil
    super.tearDown()
  }

  /// Creates and activates the fixture with the given root element tree, then
  /// builds a real `FBSimulator`, a mock translation dispatcher, and registers an
  /// `FBSimulatorAccessibilityCommands` with that dispatcher injected into the
  /// simulator's command cache. Production paths that resolve `accessibilityCommands()`
  /// on the simulator will return it.
  private func setUp(
    withRootElement rootElement: FBSimulatorControlTests_AXPMacPlatformElement_Double,
    launchCtl: (any LaunchCtlCommands)? = nil
  ) {
    fixture = FBAccessibilityTestFixture.bootedSimulator()
    fixture!.rootElement = rootElement
    fixture!.setUp()

    let sim = FBSimulatorTestSupport.testableSimulator(withDevice: fixture!.device)
    let dispatcher = FBSimulator.createAccessibilityTranslationDispatcher(withTranslator: fixture!.translator)
    let commands = FBSimulatorAccessibilityCommands(simulator: sim, translationDispatcher: dispatcher, launchCtl: launchCtl)
    sim.commandCache.register(commands, as: FBSimulatorAccessibilityCommands.self)

    simulator = sim
  }

  // MARK: - Default Element Factories

  private var defaultTitleLabel: FBSimulatorControlTests_AXPMacPlatformElement_Double {
    FBAccessibilityTestElementBuilder.staticText(withLabel: "Confirm Action", frame: NSRect(x: 20, y: 100, width: 350, height: 30))
  }

  private var defaultOkButton: FBSimulatorControlTests_AXPMacPlatformElement_Double {
    FBAccessibilityTestElementBuilder.button(withLabel: "OK", identifier: "ok_button", frame: NSRect(x: 20, y: 750, width: 150, height: 44))
  }

  private var defaultCancelButton: FBSimulatorControlTests_AXPMacPlatformElement_Double {
    FBAccessibilityTestElementBuilder.button(withLabel: "Cancel", identifier: "cancel_button", frame: NSRect(x: 200, y: 750, width: 150, height: 44))
  }

  private func defaultRoot(withChildren children: [FBSimulatorControlTests_AXPMacPlatformElement_Double]) -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    FBAccessibilityTestElementBuilder.application(withLabel: "App Window", frame: NSRect(x: 0, y: 0, width: 390, height: 844), children: children)
  }

  private var defaultElementTree: FBSimulatorControlTests_AXPMacPlatformElement_Double {
    defaultRoot(withChildren: [defaultTitleLabel, defaultOkButton, defaultCancelButton])
  }

  // MARK: - Tests

  func testAccessibilityCommandsProducesCorrectFlatOutput() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    _ = try await assertFlatOutput(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsProducesCorrectFlatOutputWithProfiling() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    let response = try await assertFlatOutput(withProfiling: true, childElements: children)
    // 4 elements x 15 properties (all except actionNames) = 60 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 60)
  }

  func testAccessibilityCommandsProducesCorrectNestedOutput() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    _ = try await assertNestedOutput(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsProducesCorrectNestedOutputWithProfiling() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    let response = try await assertNestedOutput(withProfiling: true, childElements: children)
    // 4 elements x 15 properties (all except actionNames) = 60 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 60)
  }

  func testAccessibilityCommandsRespectsKeyFiltering() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    _ = try await assertKeyFiltering(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsRespectsKeyFilteringWithProfiling() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    let response = try await assertKeyFiltering(withProfiling: true, childElements: children)
    // 4 elements x 3 properties (AXFrame always, label, frame dict) = 12 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 12)

    // Verify fetched keys match exactly the keys that were requested
    let expectedKeys: Set<String> = Set([FBAXKeys.frame.rawValue, FBAXKeys.label.rawValue, FBAXKeys.frameDict.rawValue])
    XCTAssertEqual(response.profilingData!.fetchedKeys, expectedKeys, "fetchedKeys should match exactly the keys that were requested")
  }

  func testAccessibilityPerformTapOnButtonSucceeds() async throws {
    setUp(withRootElement: defaultElementTree)

    // Configure objectAtPointResult to return the OK button element
    let okButton = FBAccessibilityTestElementBuilder.button(
      withLabel: "OK",
      identifier: "ok_button",
      frame: NSRect(x: 20, y: 750, width: 150, height: 44)
    )
    fixture!.translator.macPlatformElementResult = okButton

    // Acquire element handle then perform tap
    let element = try await simulator.accessibilityElement(at: CGPoint(x: 95, y: 772))

    // Read the label using the decomposed API and verify it
    let label = try! element.stringValue(forSearchableKey: .label)
    XCTAssertEqual(label, "OK")

    // Perform the unconditional tap
    try! (element as FBAccessibilityElement).tap()

    // Serialize and verify structure — same expected dict as element-at-point tests
    var options = FBAccessibilityRequestOptions()
    options.nestedFormat = true
    let response = try! element.serialize(with: options)

    let result = response.elements as! [String: Any]
    let expected: [String: Any] = [
      "AXLabel": "OK",
      "AXFrame": "{{20, 750}, {150, 44}}",
      "AXValue": NSNull(),
      "AXUniqueId": "ok_button",
      "type": "Button",
      "title": NSNull(),
      "frame": ["x": 20, "y": 750, "width": 150, "height": 44],
      "help": NSNull(),
      "enabled": true,
      "custom_actions": [] as [Any],
      "role": "AXButton",
      "role_description": NSNull(),
      "subrole": NSNull(),
      "content_required": false,
      "pid": 12345,
      "traits": NSNull(),
      "children": [] as [Any],
    ]
    XCTAssertEqual(result as NSDictionary, expected as NSDictionary)
    XCTAssertTrue(JSONSerialization.isValidJSONObject(result))

    element.close()

    // Verify property access tracking - tap + serialization accesses
    XCTAssertTrue(
      okButton.accessedProperties.contains("accessibilityLabel"),
      "Tap operation should access label"
    )
    XCTAssertTrue(
      okButton.accessedProperties.contains("accessibilityActionNames"),
      "Tap operation should access action names"
    )
  }

  func testAccessibilityElementAtPointReturnsElement() async throws {
    setUp(withRootElement: defaultElementTree)

    let cancelButton = FBAccessibilityTestElementBuilder.button(
      withLabel: "Cancel",
      identifier: "cancel_button",
      frame: NSRect(x: 200, y: 750, width: 150, height: 44)
    )

    let expected: [String: Any] = [
      "AXLabel": "Cancel",
      "AXFrame": "{{200, 750}, {150, 44}}",
      "AXValue": NSNull(),
      "AXUniqueId": "cancel_button",
      "type": "Button",
      "title": NSNull(),
      "frame": ["x": 200, "y": 750, "width": 150, "height": 44],
      "help": NSNull(),
      "enabled": true,
      "custom_actions": [] as [Any],
      "role": "AXButton",
      "role_description": NSNull(),
      "subrole": NSNull(),
      "content_required": false,
      "pid": 12345,
      "traits": NSNull(),
    ]

    _ = try await assertElementAtPoint(withProfiling: false, point: CGPoint(x: 275, y: 772), element: cancelButton, expected: expected)
  }

  func testAccessibilityElementAtPointReturnsElementWithProfiling() async throws {
    setUp(withRootElement: defaultElementTree)

    let cancelButton = FBAccessibilityTestElementBuilder.button(
      withLabel: "Cancel",
      identifier: "cancel_button",
      frame: NSRect(x: 200, y: 750, width: 150, height: 44)
    )

    let expected: [String: Any] = [
      "AXLabel": "Cancel",
      "AXFrame": "{{200, 750}, {150, 44}}",
      "AXValue": NSNull(),
      "AXUniqueId": "cancel_button",
      "type": "Button",
      "title": NSNull(),
      "frame": ["x": 200, "y": 750, "width": 150, "height": 44],
      "help": NSNull(),
      "enabled": true,
      "custom_actions": [] as [Any],
      "role": "AXButton",
      "role_description": NSNull(),
      "subrole": NSNull(),
      "content_required": false,
      "pid": 12345,
      "traits": NSNull(),
    ]

    let response = try await assertElementAtPoint(withProfiling: true, point: CGPoint(x: 275, y: 772), element: cancelButton, expected: expected)
    // 1 element x 15 properties (no children) = 15 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 1, expectedAttributeFetches: 15)
  }

  func testAccessibilityElementAtPointRespectsKeyFiltering() async throws {
    setUp(withRootElement: defaultElementTree)
    _ = try await assertElementAtPointKeyFiltering(withProfiling: false)
  }

  func testAccessibilityElementAtPointRespectsKeyFilteringWithProfiling() async throws {
    setUp(withRootElement: defaultElementTree)
    let response = try await assertElementAtPointKeyFiltering(withProfiling: true)
    // 1 element x 4 properties (AXFrame always, label, role for type, frame dict) = 4 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 1, expectedAttributeFetches: 4)

    // Verify fetched keys match exactly the keys that were requested
    let expectedKeys: Set<String> = Set([FBAXKeys.frame.rawValue, FBAXKeys.label.rawValue, FBAXKeys.type.rawValue, FBAXKeys.frameDict.rawValue])
    XCTAssertEqual(response.profilingData!.fetchedKeys, expectedKeys, "fetchedKeys should match exactly the keys that were requested")
  }

  // MARK: - Coverage Calculation Tests

  func testCoverageCalculationDisabledByDefault() async throws {
    setUp(withRootElement: defaultElementTree)

    let element = try await simulator.accessibilityElementForFrontmostApplication()

    let options = FBAccessibilityRequestOptions()
    let response = try element.serialize(with: options)
    element.close()
    XCTAssertNil(response.frameCoverage, "Coverage should be nil when collectFrameCoverage is not enabled")
  }

  func testCoverageCalculationWithDefaultFixture() async throws {
    // Simple test verifying coverage is returned when enabled
    setUp(withRootElement: defaultElementTree)

    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage, "Coverage should be returned when collectFrameCoverage is enabled")

    let coverage = response.frameCoverage!
    XCTAssertGreaterThan(coverage, 0.0, "Coverage should be greater than 0")
    XCTAssertLessThan(coverage, 0.15, "Coverage should be low since only 3 small elements")
  }

  func testCoverageCalculationWithSafariLikeLayout() async throws {
    let navBar = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "Navigation Bar",
      frame: NSRect(x: 0, y: 0, width: 390, height: 44)
    )

    let urlBar = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "URL Bar",
      frame: NSRect(x: 0, y: 44, width: 390, height: 50)
    )

    let bottomToolbar = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "Bottom Toolbar",
      frame: NSRect(x: 0, y: 700, width: 390, height: 144)
    )

    let root = FBAccessibilityTestElementBuilder.application(
      withLabel: "Safari",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: [navBar, urlBar, bottomToolbar]
    )

    setUp(withRootElement: root)

    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage)

    let coverage = response.frameCoverage!
    XCTAssertGreaterThan(coverage, 0.2, "Coverage should be > 20% from bars")
    XCTAssertLessThan(coverage, 0.4, "Coverage should be < 40% due to empty WebView area")
  }

  func testCoverageCalculationWithFullCoverage() async throws {
    // Create an element that covers the entire screen
    let fullCoverageElement = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "Full Coverage",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844)
    )

    let root = FBAccessibilityTestElementBuilder.application(
      withLabel: "App Window",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: [fullCoverageElement]
    )

    setUp(withRootElement: root)

    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage)

    let coverage = response.frameCoverage!
    XCTAssertGreaterThanOrEqual(coverage, 0.99, "Coverage should be near 100% when element covers full screen")
  }

  func testCoverageCalculationSkipsApplicationElement() async throws {
    // Create a tree with ONLY an Application element (no children)
    let root = FBAccessibilityTestElementBuilder.application(
      withLabel: "App Window",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: []
    )

    setUp(withRootElement: root)

    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage)

    // Application element is skipped, so coverage should be 0
    let coverage = response.frameCoverage!
    XCTAssertEqual(coverage, 0.0, accuracy: 0.001, "Coverage should be 0 when only Application element exists")
  }

  func testAdditionalFrameCoverageIsNilWithoutRemoteContent() async throws {
    // Test that additionalFrameCoverage is nil when no remote content is discovered
    setUp(withRootElement: defaultElementTree)

    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage, "frameCoverage should be set when collectFrameCoverage is enabled")
    XCTAssertNil(response.additionalFrameCoverage, "additionalFrameCoverage should be nil when no remote content is discovered")
  }

  func testAdditionalFrameCoverageIsNilWithoutRemoteContentOptions() async throws {
    // Test that additionalFrameCoverage is nil when remote content options are not set
    setUp(withRootElement: defaultElementTree)

    let element = try await simulator.accessibilityElementForFrontmostApplication()

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    // remoteContentOptions is nil by default
    let response = try element.serialize(with: options)
    element.close()
    XCTAssertNil(response.additionalFrameCoverage, "additionalFrameCoverage should be nil without remoteContentOptions")
  }

  func testRemoteContentDiscoveryMergesDiscoveredElement() async throws {
    // The frontmost app (pid 12345) is an AXApplication with no children, so the
    // main traversal marks no coverage. A separate-process element (pid 99999)
    // sits mid-screen and must be found via grid hit-testing and merged into the
    // flat output, with additionalFrameCoverage reflecting the newly covered area.
    let appElement = FBAccessibilityTestElementBuilder.application(
      withLabel: "App",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: []
    )
    let remoteElement = FBAccessibilityTestElementBuilder.button(
      withLabel: "Remote WebView Content",
      identifier: "remote_button",
      frame: NSRect(x: 0, y: 400, width: 390, height: 100)
    )
    setUp(withRootElement: appElement)

    // Object-at-point hit-testing returns a translation with a distinct pid that
    // maps to the remote element; the frontmost translation (pid 12345) still
    // resolves to the app element.
    let remoteTranslation = FBSimulatorControlTests_AXPTranslationObject_Double()
    remoteTranslation.pid = 99999
    fixture!.translator.objectAtPointResult = remoteTranslation
    fixture!.translator.macPlatformElementResultsByPid = [99999: remoteElement]

    let element = try await simulator.accessibilityElementForFrontmostApplication()
    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    var remoteOptions = FBAccessibilityRemoteContentOptions()
    remoteOptions.gridStepSize = 50
    options.remoteContentOptions = remoteOptions
    let response = try element.serialize(with: options)
    element.close()

    XCTAssertNotNil(response.additionalFrameCoverage, "additionalFrameCoverage should be set when remote content is discovered")

    let elements = response.elements as! [Any]
    let labels = elements.compactMap { ($0 as? [String: Any])?["AXLabel"] as? String }
    XCTAssertEqual(elements.count, 2, "App element plus one discovered remote element")
    XCTAssertTrue(labels.contains("Remote WebView Content"), "Discovered remote element should be merged into the output")
  }

  // MARK: - Marker Search Tests (accessibilityElementMatching)

  func testAccessibilityElementMatchingFindsDescendantByLabel() async throws {
    setUp(withRootElement: defaultElementTree)

    let element = try await simulator.accessibilityElementMatching(value: "OK", forKey: .label, depth: 10)
    defer { element.close() }

    XCTAssertEqual(try element.stringValue(forSearchableKey: .label), "OK")
  }

  func testAccessibilityElementMatchingFindsByUniqueID() async throws {
    setUp(withRootElement: defaultElementTree)

    let element = try await simulator.accessibilityElementMatching(value: "cancel_button", forKey: .uniqueID, depth: 10)
    defer { element.close() }

    XCTAssertEqual(try element.stringValue(forSearchableKey: .label), "Cancel")
  }

  func testAccessibilityElementMatchingIsSubstringMatch() async throws {
    setUp(withRootElement: defaultElementTree)

    // "Conf" is a substring of the "Confirm Action" static text label.
    let element = try await simulator.accessibilityElementMatching(value: "Conf", forKey: .label, depth: 10)
    defer { element.close() }

    XCTAssertEqual(try element.stringValue(forSearchableKey: .label), "Confirm Action")
  }

  func testAccessibilityElementMatchingMatchesRootAtDepthZero() async throws {
    setUp(withRootElement: defaultElementTree)

    // depth 0 only inspects the root element itself.
    let element = try await simulator.accessibilityElementMatching(value: "App Window", forKey: .label, depth: 0)
    defer { element.close() }

    XCTAssertEqual(try element.stringValue(forSearchableKey: .label), "App Window")
  }

  func testAccessibilityElementMatchingByRoleReturnsFirstDFSMatch() async throws {
    setUp(withRootElement: defaultElementTree)

    // Root is AXApplication, first child is AXStaticText; the first AXButton in DFS order is "OK".
    let element = try await simulator.accessibilityElementMatching(value: "AXButton", forKey: .role, depth: 10)
    defer { element.close() }

    XCTAssertEqual(try element.stringValue(forSearchableKey: .label), "OK")
  }

  func testAccessibilityElementMatchingNotFoundThrows() async throws {
    setUp(withRootElement: defaultElementTree)

    do {
      let element = try await simulator.accessibilityElementMatching(value: "DefinitelyMissing", forKey: .label, depth: 10)
      element.close()
      XCTFail("Expected matching to throw for a missing element")
    } catch {
      XCTAssertTrue(
        "\(error)".contains("not found"),
        "Expected a not-found error, got: \(error)"
      )
    }
  }

  func testAccessibilityElementMatchingRespectsDepthBound() async throws {
    // Build a tree where the target is two levels below the root:
    // root -> container -> deepButton
    let deepButton = FBAccessibilityTestElementBuilder.button(
      withLabel: "Deep",
      identifier: "deep_id",
      frame: NSRect(x: 0, y: 0, width: 10, height: 10)
    )
    let container = FBAccessibilityTestElementBuilder.application(
      withLabel: "Container",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: [deepButton]
    )
    let root = FBAccessibilityTestElementBuilder.application(
      withLabel: "App Window",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: [container]
    )
    setUp(withRootElement: root)

    // depth 1 cannot reach a level-2 descendant.
    do {
      let tooShallow = try await simulator.accessibilityElementMatching(value: "Deep", forKey: .label, depth: 1)
      tooShallow.close()
      XCTFail("Expected depth-1 search not to reach a level-2 element")
    } catch {
      // expected
    }

    // depth 2 reaches it.
    let found = try await simulator.accessibilityElementMatching(value: "Deep", forKey: .label, depth: 2)
    defer { found.close() }
    XCTAssertEqual(try found.stringValue(forSearchableKey: .label), "Deep")
  }

  // MARK: - Serialize-to-Data Golden / Envelope Tests

  /// Canonical (sorted-keys) JSON string for an object — the exact encoding both
  /// `sime2e` (full `asDictionary()`) and the gRPC companion (`.elements` only)
  /// emit on the wire. Used as a byte-level oracle for the swiftification.
  private func canonicalJSONString(_ object: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
  }

  func testSerializedEnvelopeDefaultContainsOnlyElements() async throws {
    setUp(withRootElement: defaultElementTree)
    let element = try await simulator.accessibilityElementForFrontmostApplication()
    let response = try element.serialize(with: FBAccessibilityRequestOptions())
    element.close()

    let dict = response.asDictionary()
    XCTAssertEqual(Set(dict.keys), ["elements"], "Default envelope must carry elements only")
  }

  func testSerializedEnvelopeWithProfilingContainsProfile() async throws {
    setUp(withRootElement: defaultElementTree)
    let element = try await simulator.accessibilityElementForFrontmostApplication()
    var options = FBAccessibilityRequestOptions()
    options.enableProfiling = true
    let response = try element.serialize(with: options)
    element.close()

    let dict = response.asDictionary()
    XCTAssertEqual(Set(dict.keys), ["elements", "profile"])
    let profile = try XCTUnwrap(dict["profile"] as? [String: Any])
    XCTAssertEqual(
      Set(profile.keys),
      [
        "element_count",
        "attribute_fetch_count",
        "xpc_call_count",
        "translation_duration_ms",
        "element_conversion_duration_ms",
        "serialization_duration_ms",
        "total_xpc_duration_ms",
      ],
      "Profile envelope keys changed"
    )
  }

  func testSerializedEnvelopeWithCoverageContainsCoverage() async throws {
    setUp(withRootElement: defaultElementTree)
    let element = try await simulator.accessibilityElementForFrontmostApplication()
    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try element.serialize(with: options)
    element.close()

    let dict = response.asDictionary()
    XCTAssertEqual(Set(dict.keys), ["elements", "coverage"])
    let coverage = try XCTUnwrap(dict["coverage"] as? [String: Any])
    XCTAssertNotNil(coverage["frame"], "Coverage envelope must carry frame")
    XCTAssertNil(coverage["additional"], "No remote content -> no additional coverage")
  }

  func testGRPCElementsOnlyBytesMatchExpected() async throws {
    setUp(withRootElement: defaultElementTree)

    // The cancel button is returned for the point query; the gRPC companion
    // serializes `response.elements` directly (no envelope).
    let cancel = FBAccessibilityTestElementBuilder.button(
      withLabel: "Cancel",
      identifier: "cancel_button",
      frame: NSRect(x: 200, y: 750, width: 150, height: 44)
    )
    fixture!.translator.macPlatformElementResult = cancel
    let element = try await simulator.accessibilityElement(at: CGPoint(x: 275, y: 772))
    defer { element.close() }

    let response = try element.serialize(with: FBAccessibilityRequestOptions())

    let expected: [String: Any] = [
      "AXLabel": "Cancel",
      "AXFrame": "{{200, 750}, {150, 44}}",
      "AXValue": NSNull(),
      "AXUniqueId": "cancel_button",
      "type": "Button",
      "title": NSNull(),
      "frame": ["x": 200, "y": 750, "width": 150, "height": 44],
      "help": NSNull(),
      "enabled": true,
      "custom_actions": [] as [Any],
      "role": "AXButton",
      "role_description": NSNull(),
      "subrole": NSNull(),
      "content_required": false,
      "pid": 12345,
      "traits": NSNull(),
    ]

    XCTAssertEqual(
      try canonicalJSONString(response.elements),
      try canonicalJSONString(expected),
      "gRPC elements-only JSON bytes changed"
    )
  }

  func testSerializeToDataIsDeterministicAndRoundTrips() async throws {
    setUp(withRootElement: defaultElementTree)
    let element = try await simulator.accessibilityElementForFrontmostApplication()
    let response = try element.serialize(with: FBAccessibilityRequestOptions())
    element.close()

    let envelope = response.asDictionary()
    let first = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    let second = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    XCTAssertEqual(first, second, "sorted-keys serialization must be deterministic")

    let reparsed = try JSONSerialization.jsonObject(with: first) as? [String: Any]
    XCTAssertEqual(reparsed?["elements"] as? [[String: Any]] as NSArray?, envelope["elements"] as? [[String: Any]] as NSArray?)
  }

  // MARK: - SpringBoard Remediation (zero-frame stale hierarchy)

  func testFrontmostRemediatesWhenZeroFramedRootPidIsDead() async throws {
    // A zero-framed root whose owning pid (12345) is not a live launchd service is the
    // stale-SpringBoard signal: remediation must restart CoreSimulatorBridge, then retry.
    let zeroFrameRoot = FBAccessibilityTestElementBuilder.application(withLabel: "App", frame: .zero, children: [])
    let launchCtl = FBSimulatorControlTests_LaunchCtl_Double.with(running: [:])
    setUp(withRootElement: zeroFrameRoot, launchCtl: launchCtl)

    let element = try await simulator.accessibilityElementForFrontmostApplication()
    element.close()

    XCTAssertEqual(launchCtl.stoppedServices, ["com.apple.CoreSimulator.bridge"], "a stale hierarchy must restart CoreSimulatorBridge")
  }

  func testFrontmostDoesNotRemediateWhenZeroFramedRootPidIsLive() async throws {
    // A zero frame alone is not stale: when the owning pid is still a live service, no remediation.
    let zeroFrameRoot = FBAccessibilityTestElementBuilder.application(withLabel: "App", frame: .zero, children: [])
    let launchCtl = FBSimulatorControlTests_LaunchCtl_Double.with(running: ["com.apple.SpringBoard": 12345])
    setUp(withRootElement: zeroFrameRoot, launchCtl: launchCtl)

    let element = try await simulator.accessibilityElementForFrontmostApplication()
    element.close()

    XCTAssertTrue(launchCtl.stoppedServices.isEmpty, "a live pid means the hierarchy is healthy — no remediation")
  }
}
