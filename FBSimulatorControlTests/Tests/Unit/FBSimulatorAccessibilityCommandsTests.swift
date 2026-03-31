// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import XCTest

@testable import FBSimulatorControl

final class FBSimulatorAccessibilityCommandsTests: XCTestCase {

  // MARK: - Properties

  private var fixture: FBAccessibilityTestFixture?

  // MARK: - Helpers

  private var commands: FBSimulatorAccessibilityCommands {
    FBSimulatorAccessibilityCommands.commands(with: unsafeBitCast(fixture!.simulator, to: FBSimulator.self))
  }

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
  ) -> FBAccessibilityElementsResponse {
    let cmds = commands
    XCTAssertNotNil(cmds)

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
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
  ) -> FBAccessibilityElementsResponse {
    fixture!.translator.macPlatformElementResult = elementDouble

    let cmds = commands

    let element = try! cmds.accessibilityElement(at: point).await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
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
  ) -> FBAccessibilityElementsResponse {
    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
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
  ) -> FBAccessibilityElementsResponse {
    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    options.nestedFormat = false
    options.keys = Set(["AXLabel", "frame"])
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
  private func assertElementAtPointKeyFiltering(withProfiling enableProfiling: Bool) -> FBAccessibilityElementsResponse {
    // Configure objectAtPointResult to return the title label element
    let titleLabel = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "Confirm Action",
      frame: NSRect(x: 20, y: 100, width: 350, height: 30)
    )
    fixture!.translator.macPlatformElementResult = titleLabel

    let cmds = commands

    let element = try! cmds.accessibilityElement(at: CGPoint(x: 100, y: 115)).await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    options.nestedFormat = false
    options.keys = Set(["AXLabel", "type", "frame"])
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
    fixture?.tearDown()
    fixture = nil
    super.tearDown()
  }

  /// Creates and activates the fixture with the given root element tree.
  private func setUp(withRootElement rootElement: FBSimulatorControlTests_AXPMacPlatformElement_Double) {
    fixture = FBAccessibilityTestFixture.bootedSimulator()
    fixture!.rootElement = rootElement
    fixture!.setUp()
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

  func testAccessibilityCommandsProducesCorrectFlatOutput() {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    assertFlatOutput(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsProducesCorrectFlatOutputWithProfiling() {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    let response = assertFlatOutput(withProfiling: true, childElements: children)
    // 4 elements x 15 properties (all except actionNames) = 60 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 60)
  }

  func testAccessibilityCommandsProducesCorrectNestedOutput() {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    assertNestedOutput(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsProducesCorrectNestedOutputWithProfiling() {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    let response = assertNestedOutput(withProfiling: true, childElements: children)
    // 4 elements x 15 properties (all except actionNames) = 60 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 60)
  }

  func testAccessibilityCommandsRespectsKeyFiltering() {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    assertKeyFiltering(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsRespectsKeyFilteringWithProfiling() {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    setUp(withRootElement: defaultRoot(withChildren: children))
    let response = assertKeyFiltering(withProfiling: true, childElements: children)
    // 4 elements x 3 properties (AXFrame always, label, frame dict) = 12 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 12)

    // Verify fetched keys match exactly the keys that were requested
    let expectedKeys: Set<String> = Set([FBAXKeys.frame.rawValue, FBAXKeys.label.rawValue, FBAXKeys.frameDict.rawValue])
    XCTAssertEqual(response.profilingData!.fetchedKeys as! Set<String>, expectedKeys, "fetchedKeys should match exactly the keys that were requested")
  }

  func testAccessibilityPerformTapOnButtonSucceeds() {
    setUp(withRootElement: defaultElementTree)

    // Configure objectAtPointResult to return the OK button element
    let okButton = FBAccessibilityTestElementBuilder.button(
      withLabel: "OK",
      identifier: "ok_button",
      frame: NSRect(x: 20, y: 750, width: 150, height: 44)
    )
    fixture!.translator.macPlatformElementResult = okButton

    let cmds = commands

    // Acquire element handle then perform tap
    let element = try! cmds.accessibilityElement(at: CGPoint(x: 95, y: 772)).await(withTimeout: 5.0)

    // Read the label using the decomposed API and verify it
    let label = try! element.stringValue(forSearchableKey: .label)
    XCTAssertEqual(label, "OK")

    // Perform the unconditional tap
    try! element.tap()

    // Serialize and verify structure — same expected dict as element-at-point tests
    let options = FBAccessibilityRequestOptions.default()
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

  func testAccessibilityElementAtPointReturnsElement() {
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

    assertElementAtPoint(withProfiling: false, point: CGPoint(x: 275, y: 772), element: cancelButton, expected: expected)
  }

  func testAccessibilityElementAtPointReturnsElementWithProfiling() {
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

    let response = assertElementAtPoint(withProfiling: true, point: CGPoint(x: 275, y: 772), element: cancelButton, expected: expected)
    // 1 element x 15 properties (no children) = 15 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 1, expectedAttributeFetches: 15)
  }

  func testAccessibilityElementAtPointRespectsKeyFiltering() {
    setUp(withRootElement: defaultElementTree)
    assertElementAtPointKeyFiltering(withProfiling: false)
  }

  func testAccessibilityElementAtPointRespectsKeyFilteringWithProfiling() {
    setUp(withRootElement: defaultElementTree)
    let response = assertElementAtPointKeyFiltering(withProfiling: true)
    // 1 element x 4 properties (AXFrame always, label, role for type, frame dict) = 4 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 1, expectedAttributeFetches: 4)

    // Verify fetched keys match exactly the keys that were requested
    let expectedKeys: Set<String> = Set([FBAXKeys.frame.rawValue, FBAXKeys.label.rawValue, FBAXKeys.type.rawValue, FBAXKeys.frameDict.rawValue])
    XCTAssertEqual(response.profilingData!.fetchedKeys as! Set<String>, expectedKeys, "fetchedKeys should match exactly the keys that were requested")
  }

  // MARK: - Coverage Calculation Tests

  func testCoverageCalculationDisabledByDefault() {
    setUp(withRootElement: defaultElementTree)

    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    let response = try! element.serialize(with: options)
    element.close()
    XCTAssertNil(response.frameCoverage, "Coverage should be nil when collectFrameCoverage is not enabled")
  }

  func testCoverageCalculationWithDefaultFixture() {
    // Simple test verifying coverage is returned when enabled
    setUp(withRootElement: defaultElementTree)

    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    options.collectFrameCoverage = true
    let response = try! element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage, "Coverage should be returned when collectFrameCoverage is enabled")

    let coverage = response.frameCoverage!.doubleValue
    XCTAssertGreaterThan(coverage, 0.0, "Coverage should be greater than 0")
    XCTAssertLessThan(coverage, 0.15, "Coverage should be low since only 3 small elements")
  }

  func testCoverageCalculationWithSafariLikeLayout() {
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

    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    options.collectFrameCoverage = true
    let response = try! element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage)

    let coverage = response.frameCoverage!.doubleValue
    XCTAssertGreaterThan(coverage, 0.2, "Coverage should be > 20% from bars")
    XCTAssertLessThan(coverage, 0.4, "Coverage should be < 40% due to empty WebView area")
  }

  func testCoverageCalculationWithFullCoverage() {
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

    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    options.collectFrameCoverage = true
    let response = try! element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage)

    let coverage = response.frameCoverage!.doubleValue
    XCTAssertGreaterThanOrEqual(coverage, 0.99, "Coverage should be near 100% when element covers full screen")
  }

  func testCoverageCalculationSkipsApplicationElement() {
    // Create a tree with ONLY an Application element (no children)
    let root = FBAccessibilityTestElementBuilder.application(
      withLabel: "App Window",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: []
    )

    setUp(withRootElement: root)

    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    options.collectFrameCoverage = true
    let response = try! element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage)

    // Application element is skipped, so coverage should be 0
    let coverage = response.frameCoverage!.doubleValue
    XCTAssertEqual(coverage, 0.0, accuracy: 0.001, "Coverage should be 0 when only Application element exists")
  }

  func testAdditionalFrameCoverageIsNilWithoutRemoteContent() {
    // Test that additionalFrameCoverage is nil when no remote content is discovered
    setUp(withRootElement: defaultElementTree)

    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    options.collectFrameCoverage = true
    let response = try! element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.frameCoverage, "frameCoverage should be set when collectFrameCoverage is enabled")
    XCTAssertNil(response.additionalFrameCoverage, "additionalFrameCoverage should be nil when no remote content is discovered")
  }

  func testAdditionalFrameCoverageIsNilWithoutRemoteContentOptions() {
    // Test that additionalFrameCoverage is nil when remote content options are not set
    setUp(withRootElement: defaultElementTree)

    let cmds = commands

    let element = try! cmds.accessibilityElementForFrontmostApplication().await(withTimeout: 5.0)

    let options = FBAccessibilityRequestOptions.default()
    options.collectFrameCoverage = true
    // remoteContentOptions is nil by default
    let response = try! element.serialize(with: options)
    element.close()
    XCTAssertNil(response.additionalFrameCoverage, "additionalFrameCoverage should be nil without remoteContentOptions")
  }
}
