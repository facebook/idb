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
    _ profile: FBAccessibilityProfile?,
    expectedElements: Int64,
    expectedAttributeFetches: Int64
  ) {
    XCTAssertNotNil(profile, "Profiling data should be present")
    // The accessibility backend is the translator lane, so it must be that case and not the guest one —
    // asserting the case is what stops a future change quietly serving the wrong profile shape here.
    guard case let .translator(profilingData)? = profile else {
      return XCTFail("the accessibility backend must report a translator profile, got \(String(describing: profile))")
    }
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
    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.format = .default
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try await element.serialize(with: options)
    element.close()

    let result = response.legacyElementsObject() as! [Any]
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

    let element = try await simulator.resolveElement(for: .point(point))

    var options = FBAccessibilityRequestOptions()
    options.format = .default
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try await element.serialize(with: options)
    element.close()

    let result = response.legacyElementsObject() as! [String: Any]
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
    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.format = .nested
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try await element.serialize(with: options)
    element.close()

    let result = response.legacyElementsObject() as! [Any]
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
    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.format = .default
    options.keys = Set([FBAXKeys.label, .frameDict])
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try await element.serialize(with: options)
    element.close()

    let result = response.legacyElementsObject() as! [Any]
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

    let element = try await simulator.resolveElement(for: .point(CGPoint(x: 100, y: 115)))

    var options = FBAccessibilityRequestOptions()
    options.format = .default
    options.keys = Set([FBAXKeys.label, .type, .frameDict])
    options.enableLogging = true
    options.enableProfiling = enableProfiling

    let response = try await element.serialize(with: options)
    element.close()

    let result = response.legacyElementsObject() as! [String: Any]

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
  ) throws {
    fixture = FBAccessibilityTestFixture.bootedSimulator()
    fixture!.rootElement = rootElement
    try fixture!.setUp()

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
    try setUp(withRootElement: defaultRoot(withChildren: children))
    _ = try await assertFlatOutput(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsProducesCorrectFlatOutputWithProfiling() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    try setUp(withRootElement: defaultRoot(withChildren: children))
    let response = try await assertFlatOutput(withProfiling: true, childElements: children)
    // 4 elements x 15 properties (all except actionNames) = 60 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 60)
  }

  func testAccessibilityCommandsProducesCorrectNestedOutput() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    try setUp(withRootElement: defaultRoot(withChildren: children))
    _ = try await assertNestedOutput(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsProducesCorrectNestedOutputWithProfiling() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    try setUp(withRootElement: defaultRoot(withChildren: children))
    let response = try await assertNestedOutput(withProfiling: true, childElements: children)
    // 4 elements x 15 properties (all except actionNames) = 60 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 60)
  }

  func testAccessibilityCommandsRespectsKeyFiltering() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    try setUp(withRootElement: defaultRoot(withChildren: children))
    _ = try await assertKeyFiltering(withProfiling: false, childElements: children)
  }

  func testAccessibilityCommandsRespectsKeyFilteringWithProfiling() async throws {
    let children = [defaultTitleLabel, defaultOkButton, defaultCancelButton]
    try setUp(withRootElement: defaultRoot(withChildren: children))
    let response = try await assertKeyFiltering(withProfiling: true, childElements: children)
    // 4 elements x 3 properties (AXFrame always, label, frame dict) = 12 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 4, expectedAttributeFetches: 12)

    // Verify fetched keys match exactly the keys that were requested
    let expectedKeys: Set<String> = Set([FBAXKeys.frame.rawValue, FBAXKeys.label.rawValue, FBAXKeys.frameDict.rawValue])
    XCTAssertEqual(response.profilingData?.translatorProfile?.fetchedKeys, expectedKeys, "fetchedKeys should match exactly the keys that were requested")
  }

  // `FBTapOptions.duration` asks for a long-press. The accessibility backend performs `AXPress`, which is
  // instantaneous and has nowhere to put a hold, so the request is refused rather than quietly served as
  // an ordinary tap — a test asking for a long-press and getting a tap passes for the wrong reason.
  func testAccessibilityTapRefusesAHoldDuration() async throws {
    try setUp(withRootElement: defaultElementTree)
    let okButton = FBAccessibilityTestElementBuilder.button(
      withLabel: "OK",
      identifier: "ok_button",
      frame: NSRect(x: 20, y: 750, width: 150, height: 44)
    )
    fixture!.translator.macPlatformElementResult = okButton

    let automation = try simulator.uiAutomation(backend: .accessibility)
    do {
      try await automation.tap(.point(CGPoint(x: 95, y: 772)), options: FBTapOptions(duration: 2))
      XCTFail("a hold this backend cannot perform must be refused")
    } catch let error as FBUIAutomationError {
      guard case let .operationUnsupported(backend, operation) = error else {
        return XCTFail("expected operationUnsupported, got \(error)")
      }
      XCTAssertEqual(backend, .accessibility)
      XCTAssertEqual(operation, "A tap with a hold duration")
    }

    XCTAssertFalse(
      okButton.accessedProperties.contains("accessibilityActionNames"),
      "a refused tap must not reach the element at all"
    )
  }

  func testAccessibilityPerformTapOnButtonSucceeds() async throws {
    try setUp(withRootElement: defaultElementTree)

    // Configure objectAtPointResult to return the OK button element
    let okButton = FBAccessibilityTestElementBuilder.button(
      withLabel: "OK",
      identifier: "ok_button",
      frame: NSRect(x: 20, y: 750, width: 150, height: 44)
    )
    fixture!.translator.macPlatformElementResult = okButton

    // Acquire element handle then perform tap
    let element = try await simulator.resolveElement(for: .point(CGPoint(x: 95, y: 772)))

    // Read the label using the decomposed API and verify it
    let label = try await element.stringValue(forSearchableKey: .label)
    XCTAssertEqual(label, "OK")

    // Perform the unconditional tap
    try await (element as FBAccessibilityElement).tap()

    // Serialize and verify structure — same expected dict as element-at-point tests
    var options = FBAccessibilityRequestOptions()
    options.format = .nested
    let response = try await element.serialize(with: options)

    let result = response.legacyElementsObject() as! [String: Any]
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
    try setUp(withRootElement: defaultElementTree)

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
    try setUp(withRootElement: defaultElementTree)

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
    try setUp(withRootElement: defaultElementTree)
    _ = try await assertElementAtPointKeyFiltering(withProfiling: false)
  }

  func testAccessibilityElementAtPointRespectsKeyFilteringWithProfiling() async throws {
    try setUp(withRootElement: defaultElementTree)
    let response = try await assertElementAtPointKeyFiltering(withProfiling: true)
    // 1 element x 4 properties (AXFrame always, label, role for type, frame dict) = 4 attribute fetches
    assertProfilingData(response.profilingData, expectedElements: 1, expectedAttributeFetches: 4)

    // Verify fetched keys match exactly the keys that were requested
    let expectedKeys: Set<String> = Set([FBAXKeys.frame.rawValue, FBAXKeys.label.rawValue, FBAXKeys.type.rawValue, FBAXKeys.frameDict.rawValue])
    XCTAssertEqual(response.profilingData?.translatorProfile?.fetchedKeys, expectedKeys, "fetchedKeys should match exactly the keys that were requested")
  }

  // MARK: - Coverage Calculation Tests

  func testCoverageCalculationDisabledByDefault() async throws {
    try setUp(withRootElement: defaultElementTree)

    let element = try await simulator.resolveElement(for: .frontmost)

    let options = FBAccessibilityRequestOptions()
    let response = try await element.serialize(with: options)
    element.close()
    XCTAssertNil(response.coverage?.frame, "Coverage should be nil when collectFrameCoverage is not enabled")
  }

  func testCoverageCalculationWithDefaultFixture() async throws {
    // Simple test verifying coverage is returned when enabled
    try setUp(withRootElement: defaultElementTree)

    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.coverage?.frame, "Coverage should be returned when collectFrameCoverage is enabled")

    let coverage = response.coverage!.frame
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

    try setUp(withRootElement: root)

    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.coverage?.frame)

    let coverage = response.coverage!.frame
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

    try setUp(withRootElement: root)

    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.coverage?.frame)

    let coverage = response.coverage!.frame
    XCTAssertGreaterThanOrEqual(coverage, 0.99, "Coverage should be near 100% when element covers full screen")
  }

  func testCoverageCalculationSkipsApplicationElement() async throws {
    // Create a tree with ONLY an Application element (no children)
    let root = FBAccessibilityTestElementBuilder.application(
      withLabel: "App Window",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: []
    )

    try setUp(withRootElement: root)

    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.coverage?.frame)

    // Application element is skipped, so coverage should be 0
    let coverage = response.coverage!.frame
    XCTAssertEqual(coverage, 0.0, accuracy: 0.001, "Coverage should be 0 when only Application element exists")
  }

  // Coverage is computed from the serialized model, so it can only measure frames the read actually
  // serialized. Requesting it therefore widens the key set with what it reads — the frame to measure and
  // the type that identifies the application root it must skip — rather than silently reporting nothing
  // for a narrow `--key`.
  //
  // This costs no extra work on the wire: the walk fetches the frame for every node regardless of the
  // key set, so the widening only changes what is emitted.
  func testRequestingCoverageWidensTheKeySetToTheAttributesItReads() async throws {
    let bar = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "Navigation Bar",
      frame: NSRect(x: 0, y: 0, width: 390, height: 422)
    )
    try setUp(
      withRootElement: FBAccessibilityTestElementBuilder.application(
        withLabel: "App Window",
        frame: NSRect(x: 0, y: 0, width: 390, height: 844),
        children: [bar]
      ))

    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions()
    options.keys = [.label]
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()

    let coverage = try XCTUnwrap(response.coverage?.frame, "coverage is collected despite the narrow key set")
    XCTAssertEqual(coverage, 0.5, accuracy: 0.01, "the bar covers the upper half; the Application root is skipped")

    let first = try XCTUnwrap((response.legacyElementsObject() as? [Any])?.first as? [String: Any])
    XCTAssertEqual(
      Set(first.keys),
      [FBAXKeys.label.rawValue, FBAXKeys.frameDict.rawValue, FBAXKeys.type.rawValue],
      "the requested key, widened by exactly what the dimensions read: the frame to measure, the type "
        + "identifying the root to skip, and the label `content` counts as perceivable"
    )
  }

  func testAdditionalFrameCoverageIsNilWithoutRemoteContent() async throws {
    // Test that the additional coverage is nil when no remote content is discovered
    try setUp(withRootElement: defaultElementTree)

    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()
    XCTAssertNotNil(response.coverage?.frame, "coverage should be reported when collectFrameCoverage is enabled")
    XCTAssertNil(response.coverage?.additional, "the additional coverage should be nil when no remote content is discovered")
  }

  func testAdditionalFrameCoverageIsNilWithoutRemoteContentOptions() async throws {
    // Test that the additional coverage is nil when remote content options are not set
    try setUp(withRootElement: defaultElementTree)

    let element = try await simulator.resolveElement(for: .frontmost)

    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    // remoteContentOptions is nil by default
    let response = try await element.serialize(with: options)
    element.close()
    XCTAssertNil(response.coverage?.additional, "the additional coverage should be nil without remoteContentOptions")
  }

  func testRemoteContentDiscoveryMergesDiscoveredElement() async throws {
    // The frontmost app (pid 12345) is an AXApplication with no children, so the
    // main traversal marks no coverage. A separate-process element (pid 99999)
    // sits mid-screen and must be found via grid hit-testing and merged into the
    // flat output, with the additional coverage reflecting the newly covered area.
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
    try setUp(withRootElement: appElement)

    // Object-at-point hit-testing returns a translation with a distinct pid that
    // maps to the remote element; the frontmost translation (pid 12345) still
    // resolves to the app element.
    let remoteTranslation = FBSimulatorControlTests_AXPTranslationObject_Double()
    remoteTranslation.pid = 99999
    fixture!.translator.objectAtPointResult = remoteTranslation
    fixture!.translator.macPlatformElementResultsByPid = [99999: remoteElement]

    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    var remoteOptions = FBAccessibilityRemoteContentOptions()
    remoteOptions.gridStepSize = 50
    options.remoteContentOptions = remoteOptions
    let response = try await element.serialize(with: options)
    element.close()

    XCTAssertNotNil(response.coverage?.additional, "the additional coverage should be set when remote content is discovered")

    let elements = response.legacyElementsObject() as! [Any]
    let labels = elements.compactMap { ($0 as? [String: Any])?["AXLabel"] as? String }
    XCTAssertEqual(elements.count, 2, "App element plus one discovered remote element")
    XCTAssertTrue(labels.contains("Remote WebView Content"), "Discovered remote element should be merged into the output")
  }

  // MARK: - The element filter inside the walk

  /// A root whose three children are one keeper and two elements `.interactable` drops — no label, no
  /// identifier, and `StaticText`, which is not an actionable role.
  private func filterableRoot() -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    FBAccessibilityTestElementBuilder.application(
      withLabel: "App Window",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: [
        FBAccessibilityTestElementBuilder.button(
          withLabel: "OK", identifier: "ok_button", frame: NSRect(x: 0, y: 0, width: 100, height: 44)
        ),
        FBAccessibilityTestElementBuilder.staticText(withLabel: "", frame: NSRect(x: 0, y: 100, width: 390, height: 44)),
        FBAccessibilityTestElementBuilder.staticText(withLabel: "", frame: NSRect(x: 0, y: 200, width: 390, height: 44)),
      ]
    )
  }

  /// Profiles a whole-tree read of `filterableRoot()` under `filter`. Installs the fixture, so it may
  /// be called only once per test — the translator swizzle refuses a second install.
  private func profile(withFilter filter: FBAccessibilityElementFilter) async throws -> FBAccessibilityProfile? {
    try setUp(withRootElement: filterableRoot())
    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions()
    options.enableProfiling = true
    options.filter = filter
    let response = try await element.serialize(with: options)
    element.close()
    return response.profilingData
  }

  /// Reads `filterableRoot()` under `filter` with coverage on. Installs the fixture, so it may be
  /// called only once per test.
  private func coverage(withFilter filter: FBAccessibilityElementFilter) async throws -> FBAccessibilityCoverage? {
    try setUp(withRootElement: filterableRoot())
    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions()
    options.collectFrameCoverage = true
    options.filter = filter
    let response = try await element.serialize(with: options)
    element.close()
    return response.coverage
  }

  // Under the default filter nothing is dropped, so the two ratios describe the same set of elements
  // and must agree exactly.
  func testWalkedCoverageEqualsReportedCoverageUnderTheDefaultFilter() async throws {
    let measured = try await coverage(withFilter: .all)
    let coverage = try XCTUnwrap(measured)
    XCTAssertEqual(coverage.walked, coverage.frame, accuracy: 0.0001, "with nothing dropped the two are one number")
    XCTAssertGreaterThan(coverage.frame, 0, "the fixture's children cover part of the screen")
  }

  // Under a filter that drops elements the two diverge, and that gap is the point: `frame` is what the
  // caller receives, `walked` is what was there to receive. The fixture drops two static texts that
  // between them cover more screen than the one button that survives.
  func testWalkedCoverageExceedsReportedCoverageWhenTheFilterDrops() async throws {
    let measured = try await coverage(withFilter: .interactable)
    let coverage = try XCTUnwrap(measured)
    XCTAssertGreaterThan(
      coverage.walked, coverage.frame,
      "the dropped static texts are counted by the walk and not by the report"
    )
  }

  /// A screen shaped like a real one: full-screen containers nesting a little actual content. This is
  /// what saturates a single coverage ratio — the containers alone cover the whole screen — so it is
  /// what the dimensions have to tell apart.
  private func containerHeavyRoot() -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    let button = FBAccessibilityTestElementBuilder.button(
      withLabel: "OK", identifier: "ok_button", frame: NSRect(x: 0, y: 0, width: 390, height: 211)
    )
    let innerContainer = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "", frame: NSRect(x: 0, y: 0, width: 390, height: 844)
    )
    return FBAccessibilityTestElementBuilder.application(
      withLabel: "App Window",
      frame: NSRect(x: 0, y: 0, width: 390, height: 844),
      children: [
        FBAccessibilityTestElementBuilder.application(
          withLabel: "Inner", frame: NSRect(x: 0, y: 0, width: 390, height: 844), children: [button, innerContainer]
        )
      ]
    )
  }

  // The point of reporting several ratios: on a container-heavy screen the aggregate one saturates and
  // says nothing, while the dimensions measured over the same walk still discriminate. Here the
  // unlabeled full-screen container fills `walked`, and only the quarter-screen button is interactable.
  func testCoverageDimensionsDiscriminateWhereTheAggregateSaturates() async throws {
    try setUp(withRootElement: containerHeavyRoot())
    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions()
    options.format = .nested
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()

    let coverage = try XCTUnwrap(response.coverage)
    XCTAssertEqual(coverage.walked, 1.0, accuracy: 0.01, "the full-screen container covers everything")
    XCTAssertEqual(coverage.frame, 1.0, accuracy: 0.01, "nothing was filtered, so the report matches the walk")
    XCTAssertEqual(try XCTUnwrap(coverage.content), 0.25, accuracy: 0.01, "only the labelled button is perceivable content")
    XCTAssertEqual(
      try XCTUnwrap(coverage.leaf), 1.0, accuracy: 0.01,
      "both leaves count — the unlabeled container is childless, so it is one"
    )
  }

  // A flat read carries no `children`, so it cannot say which elements are leaves and declines to guess
  // rather than calling every element one.
  func testLeafAndContentCoverageAreAbsentForAFlatRead() async throws {
    try setUp(withRootElement: containerHeavyRoot())
    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions()
    options.format = .default
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()

    let coverage = try XCTUnwrap(response.coverage)
    XCTAssertNil(coverage.leaf, "a flat read has no tree structure to read leaves from")
    XCTAssertNil(coverage.content, "content is leaf-based too, so a flat read cannot report it either")
  }

  // The interactable dimension is measured over the walk, so asking to be shown less does not change
  // what it reports — which is the whole reason it exists rather than being reached via `--filter`.
  func testContentCoverageIsIndependentOfTheRequestedFilter() async throws {
    try setUp(withRootElement: containerHeavyRoot())
    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions()
    options.format = .nested
    options.collectFrameCoverage = true
    options.filter = .interactable
    let response = try await element.serialize(with: options)
    element.close()

    let coverage = try XCTUnwrap(response.coverage)
    XCTAssertEqual(try XCTUnwrap(coverage.content), 0.25, accuracy: 0.01, "the same number the unfiltered read reports")
    XCTAssertEqual(coverage.frame, 0.25, accuracy: 0.01, "while the reported coverage follows the filter")
    XCTAssertEqual(coverage.walked, 1.0, accuracy: 0.01, "and the walk is unchanged")
  }

  // MARK: - When the profiling collector starts existing

  // The dispatcher times both acquisition phases — `perform(withTranslator:)` and
  // `macPlatformElement(fromTranslation:)` — and writes each to `request.collector`, which exists from
  // the moment the request does.
  //
  // The double burns 20 ms in each of those calls, so each phase has 20 ms to report. Asserting a floor
  // rather than a sign is what distinguishes a wired-up measurement from a discarded one.
  func testTheTranslatorProfileReportsAcquisitionTime() async throws {
    try setUp(withRootElement: defaultRoot(withChildren: []))
    fixture!.translator.frontmostApplicationDelay = 0.02
    fixture!.translator.macPlatformElementDelay = 0.02

    let element = try await simulator.resolveElement(for: .frontmost)
    defer { element.close() }
    var options = FBAccessibilityRequestOptions()
    options.enableProfiling = true
    let response = try await element.serialize(with: options)
    let profile = try XCTUnwrap(response.profilingData?.translatorProfile)

    XCTAssertGreaterThanOrEqual(profile.translationDuration, 0.02, "the 20 ms spent resolving the translation is reported")
    XCTAssertGreaterThanOrEqual(profile.elementConversionDuration, 0.02, "as is the 20 ms spent converting it to an element")
    XCTAssertGreaterThan(profile.serializationDuration, 0, "alongside the phase that was already measured")
  }

  // The mechanism behind the above, pinned directly rather than through a read: a request has somewhere
  // to record from the moment it exists, so every dispatcher measurement taken before `serialize` lands.
  func testARequestBeginsWithACollector() {
    XCTAssertNotNil(FBAXTranslationRequest(kind: .frontmostApplication).collector)
  }

  // The baseline the filtered read below is measured against: every node serialized.
  func testAllFilterProfileCountsCoverEveryNode() async throws {
    assertProfilingData(try await profile(withFilter: .all), expectedElements: 4, expectedAttributeFetches: 60)
  }

  // The filter no longer changes what the walk does, so it no longer changes what the walk costs: both
  // filters serialize all four nodes for the same 60 fetches, and the filter decides afterwards which
  // two are reported.
  //
  // These counts went up. Previously a dropped node was never serialized, so it contributed neither an
  // element nor any of its 15 fetches — but it was still probed for a label, an identifier and a role,
  // and those three fetches were never tallied. The old figures were the cost of a *different* walk,
  // understated; these are the cost of this one.
  // Four more fetches than the unfiltered walk, one per element: the filter now matches on the
  // `interactable` verdict, so it requests it. On this backend the verdict is null — there is nothing to
  // derive it from — and the read is still charged for asking, which is what the count records.
  func testInteractableFilterProfileCountsMatchTheUnfilteredWalk() async throws {
    assertProfilingData(try await profile(withFilter: .interactable), expectedElements: 4, expectedAttributeFetches: 64)
  }

  // Remote content is discovered after the walk and appended to the output, and the filter now runs
  // over that merged list — so an element is kept or dropped on what it is, not on whether the main
  // traversal or the remote hit-test happened to find it. It used to be appended straight past the
  // filter, so the element below survived purely because of where it was found.
  func testRemoteContentDiscoveryHonoursTheElementFilter() async throws {
    let appElement = FBAccessibilityTestElementBuilder.application(
      withLabel: "App", frame: NSRect(x: 0, y: 0, width: 390, height: 844), children: []
    )
    // Unlabeled, unidentified StaticText — exactly what `.interactable` exists to drop.
    let remoteElement = FBAccessibilityTestElementBuilder.staticText(
      withLabel: "", frame: NSRect(x: 0, y: 400, width: 390, height: 100)
    )
    try setUp(withRootElement: appElement)

    let remoteTranslation = FBSimulatorControlTests_AXPTranslationObject_Double()
    remoteTranslation.pid = 99999
    fixture!.translator.objectAtPointResult = remoteTranslation
    fixture!.translator.macPlatformElementResultsByPid = [99999: remoteElement]

    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions()
    options.filter = .interactable
    options.collectFrameCoverage = true
    options.remoteContentOptions = FBAccessibilityRemoteContentOptions(gridStepSize: 50)
    let response = try await element.serialize(with: options)
    element.close()

    XCTAssertNotNil(
      response.coverage?.additional,
      "the element was discovered — its coverage is counted even though the filter then drops it"
    )
    let elements = try XCTUnwrap(response.legacyElementsObject() as? [Any])
    XCTAssertEqual(elements.count, 1, "only the labeled app root survives; the discovered element is filtered out")
  }

  // MARK: - Marker Search Tests (accessibilityElementMatching)

  func testAccessibilityElementMatchingFindsDescendantByLabel() async throws {
    try setUp(withRootElement: defaultElementTree)

    let element = try await simulator.resolveElement(for: .marker(value: "OK", key: .label, depth: 10))
    defer { element.close() }

    let elementLabel = try await element.stringValue(forSearchableKey: .label)
    XCTAssertEqual(elementLabel, "OK")
  }

  func testAccessibilityElementMatchingFindsByUniqueID() async throws {
    try setUp(withRootElement: defaultElementTree)

    let element = try await simulator.resolveElement(for: .marker(value: "cancel_button", key: .uniqueID, depth: 10))
    defer { element.close() }

    let elementLabel = try await element.stringValue(forSearchableKey: .label)
    XCTAssertEqual(elementLabel, "Cancel")
  }

  func testAccessibilityElementMatchingIsSubstringMatch() async throws {
    try setUp(withRootElement: defaultElementTree)

    // "Conf" is a substring of the "Confirm Action" static text label.
    let element = try await simulator.resolveElement(for: .marker(value: "Conf", key: .label, depth: 10))
    defer { element.close() }

    let elementLabel = try await element.stringValue(forSearchableKey: .label)
    XCTAssertEqual(elementLabel, "Confirm Action")
  }

  func testAccessibilityElementMatchingMatchesRootAtDepthZero() async throws {
    try setUp(withRootElement: defaultElementTree)

    // depth 0 only inspects the root element itself.
    let element = try await simulator.resolveElement(for: .marker(value: "App Window", key: .label, depth: 0))
    defer { element.close() }

    let elementLabel = try await element.stringValue(forSearchableKey: .label)
    XCTAssertEqual(elementLabel, "App Window")
  }

  func testAccessibilityElementMatchingByRoleReturnsFirstDFSMatch() async throws {
    try setUp(withRootElement: defaultElementTree)

    // Root is AXApplication, first child is AXStaticText; the first AXButton in DFS order is "OK".
    let element = try await simulator.resolveElement(for: .marker(value: "AXButton", key: .role, depth: 10))
    defer { element.close() }

    let elementLabel = try await element.stringValue(forSearchableKey: .label)
    XCTAssertEqual(elementLabel, "OK")
  }

  func testAccessibilityElementMatchingNotFoundThrows() async throws {
    try setUp(withRootElement: defaultElementTree)

    do {
      let element = try await simulator.resolveElement(for: .marker(value: "DefinitelyMissing", key: .label, depth: 10))
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
    try setUp(withRootElement: root)

    // depth 1 cannot reach a level-2 descendant.
    do {
      let tooShallow = try await simulator.resolveElement(for: .marker(value: "Deep", key: .label, depth: 1))
      tooShallow.close()
      XCTFail("Expected depth-1 search not to reach a level-2 element")
    } catch {
      // expected
    }

    // depth 2 reaches it.
    let found = try await simulator.resolveElement(for: .marker(value: "Deep", key: .label, depth: 2))
    defer { found.close() }
    let foundLabel = try await found.stringValue(forSearchableKey: .label)
    XCTAssertEqual(foundLabel, "Deep")
  }

  /// The `complete` document as untyped Foundation — what a consumer parsing the emitted JSON sees.
  private static func documentObject(_ response: FBAccessibilityElementsResponse) -> [String: Any] {
    guard let data = try? JSONEncoder().encode(response.document),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return [:]
    }
    return object
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
    try setUp(withRootElement: defaultElementTree)
    let element = try await simulator.resolveElement(for: .frontmost)
    let response = try await element.serialize(with: FBAccessibilityRequestOptions())
    element.close()

    let dict = try response.legacyEnvelopeObject()
    XCTAssertEqual(Set(dict.keys), ["elements"], "Default envelope must carry elements only")
  }

  // Profiling is reported by the `complete` document, not the legacy envelope: the envelope's bytes are
  // frozen, so a caller asking for timings gets them by asking for the format that can carry them.
  func testCompleteDocumentWithProfilingContainsProfile() async throws {
    try setUp(withRootElement: defaultElementTree)
    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions(format: .complete)
    options.enableProfiling = true
    let response = try await element.serialize(with: options)
    element.close()

    XCTAssertEqual(Set(try response.legacyEnvelopeObject().keys), ["elements"], "the legacy envelope never carries profiling")

    let dict = Self.documentObject(response)
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

  func testCompleteDocumentWithCoverageContainsCoverage() async throws {
    try setUp(withRootElement: defaultElementTree)
    let element = try await simulator.resolveElement(for: .frontmost)
    var options = FBAccessibilityRequestOptions(format: .complete)
    options.collectFrameCoverage = true
    let response = try await element.serialize(with: options)
    element.close()

    XCTAssertEqual(Set(try response.legacyEnvelopeObject().keys), ["elements"], "the legacy envelope never carries coverage")

    let coverage = try XCTUnwrap(Self.documentObject(response)["coverage"] as? [String: Any])
    XCTAssertNotNil(coverage["frame"], "Coverage must carry frame")
    XCTAssertTrue(coverage["additional"] is NSNull, "No remote content -> additional is null, but keeps its key")
  }

  func testGRPCElementsOnlyBytesMatchExpected() async throws {
    try setUp(withRootElement: defaultElementTree)

    // The cancel button is returned for the point query; the gRPC companion
    // serializes `response.elements` directly (no envelope).
    let cancel = FBAccessibilityTestElementBuilder.button(
      withLabel: "Cancel",
      identifier: "cancel_button",
      frame: NSRect(x: 200, y: 750, width: 150, height: 44)
    )
    fixture!.translator.macPlatformElementResult = cancel
    let element = try await simulator.resolveElement(for: .point(CGPoint(x: 275, y: 772)))
    defer { element.close() }

    let response = try await element.serialize(with: FBAccessibilityRequestOptions())

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
      try canonicalJSONString(response.legacyElementsObject()),
      try canonicalJSONString(expected),
      "gRPC elements-only JSON bytes changed"
    )
  }

  func testSerializeToDataIsDeterministicAndRoundTrips() async throws {
    try setUp(withRootElement: defaultElementTree)
    let element = try await simulator.resolveElement(for: .frontmost)
    let response = try await element.serialize(with: FBAccessibilityRequestOptions())
    element.close()

    let envelope = try response.legacyEnvelopeObject()
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
    try setUp(withRootElement: zeroFrameRoot, launchCtl: launchCtl)

    let element = try await simulator.resolveElement(for: .frontmost)
    element.close()

    XCTAssertEqual(launchCtl.stoppedServices, ["com.apple.CoreSimulator.bridge"], "a stale hierarchy must restart CoreSimulatorBridge")
  }

  func testFrontmostDoesNotRemediateWhenZeroFramedRootPidIsLive() async throws {
    // A zero frame alone is not stale: when the owning pid is still a live service, no remediation.
    let zeroFrameRoot = FBAccessibilityTestElementBuilder.application(withLabel: "App", frame: .zero, children: [])
    let launchCtl = FBSimulatorControlTests_LaunchCtl_Double.with(running: ["com.apple.SpringBoard": 12345])
    try setUp(withRootElement: zeroFrameRoot, launchCtl: launchCtl)

    let element = try await simulator.resolveElement(for: .frontmost)
    element.close()

    XCTAssertTrue(launchCtl.stoppedServices.isEmpty, "a live pid means the hierarchy is healthy — no remediation")
  }

  // MARK: - Frontmost nil-translation (describe-all SpringBoard-down classification)

  func testFrontmostDescribeAllReturnsSpringBoardNotRunningWhenSpringBoardDown() async throws {
    // SpringBoard is confirmed not running.
    try setUp(withRootElement: defaultElementTree, launchCtl: FBSimulatorControlTests_LaunchCtl_Double.with(running: [:]))
    // No frontmost translation -> request.perform(withTranslator:) returns nil.
    fixture!.translator.frontmostApplicationResult = nil

    do {
      let element = try await simulator.resolveElement(for: .frontmost)
      element.close()
      XCTFail("Expected springBoardNotRunning")
    } catch FBAccessibilityError.springBoardNotRunning {
      // Expected: the describe-all failure is re-classified to the precise root cause.
    }
  }

  func testFrontmostDescribeAllStaysNoTranslationObjectWhenSpringBoardRunning() async throws {
    // SpringBoard is up, so a nil translation is some other failure (e.g. a transient) — unchanged.
    try setUp(withRootElement: defaultElementTree, launchCtl: FBSimulatorControlTests_LaunchCtl_Double.with(running: ["com.apple.SpringBoard": 4321]))
    fixture!.translator.frontmostApplicationResult = nil

    do {
      let element = try await simulator.resolveElement(for: .frontmost)
      element.close()
      XCTFail("Expected noTranslationObject")
    } catch FBAccessibilityError.noTranslationObject {
      // Expected: re-classification fires only when SpringBoard is confirmed down.
    }
  }

  func testAtPointDescribeStaysNoTranslationObjectWhenTranslationIsNil() async throws {
    try setUp(withRootElement: defaultElementTree)
    // The at-point path can legitimately specify an invalid point, so it is never re-classified.
    fixture!.translator.objectAtPointResult = nil

    do {
      let element = try await simulator.resolveElement(for: .point(CGPoint(x: 10, y: 10)))
      element.close()
      XCTFail("Expected noTranslationObject")
    } catch FBAccessibilityError.noTranslationObject {
      // Expected: the point path keeps the generic message regardless of SpringBoard state.
    }
  }

  // MARK: - Frontmost pid (remote-automation pid anchor)

  func testResolveFrontmostElementExposesProcessIdentifier() async throws {
    // The remote-automation backend anchors its frontmost read on the app's pid, borrowing it from
    // the AX handle rather than hit-testing a screen point. The resolved element must surface that pid
    // (the translation double's pid defaults to 12345).
    let root = FBAccessibilityTestElementBuilder.application(withLabel: "App", frame: CGRect(x: 0, y: 0, width: 100, height: 100), children: [])
    try setUp(withRootElement: root)

    let element = try await simulator.resolveElement(for: .frontmost)
    defer { element.close() }

    XCTAssertEqual(element.processIdentifier, 12345, "the resolved frontmost element must expose the backing app's pid")
  }

  func testResolveApplicationByPidExposesProcessIdentifier() async throws {
    // A by-pid target reads that specific app (regardless of what is frontmost), surfacing its pid.
    let root = FBAccessibilityTestElementBuilder.application(withLabel: "App", frame: CGRect(x: 0, y: 0, width: 100, height: 100), children: [])
    try setUp(withRootElement: root)

    let element = try await simulator.resolveElement(for: .application(pid: 777))
    defer { element.close() }

    XCTAssertEqual(element.processIdentifier, 777, "a by-pid resolve reads the app with that pid")
  }

  // MARK: - Concurrent access to the shared translator

  func testConcurrentResolutionsOverlapInsideTheSharedTranslator() async throws {
    try setUp(withRootElement: defaultElementTree)
    let tracker = TranslatorEntryTracker()
    fixture!.translator.resolutionEnterHook = { tracker.enter() }

    let sim = simulator!
    async let first = sim.resolveElement(for: .frontmost)
    async let second = sim.resolveElement(for: .frontmost)
    let elements = try await [first, second]
    for element in elements {
      element.close()
    }

    // The translator singleton's internal state is not synchronized, so all translator
    // work is serialized onto one queue: concurrent resolutions enter it strictly one
    // at a time, even with the first held open waiting for a peer.
    XCTAssertEqual(tracker.maxActive, 1, "resolutions enter the shared translator strictly one at a time")
  }
}

/// Counts how many resolutions are inside the translator at once. `enter()` brackets
/// the translator call: the first caller is held until a peer arrives (or the bounded
/// wait elapses), giving an overlap every chance to be observed — so a serialized
/// implementation shows `maxActive == 1` deterministically rather than by lucky timing.
private final class TranslatorEntryTracker: @unchecked Sendable {
  private let lock = NSLock()
  private let peerArrived = DispatchSemaphore(value: 0)
  private var active = 0
  private(set) var maxActive = 0

  func enter() {
    lock.lock()
    active += 1
    maxActive = max(maxActive, active)
    let sawPeer = active >= 2
    lock.unlock()
    if sawPeer {
      peerArrived.signal()
    } else {
      _ = peerArrived.wait(timeout: .now() + 2.0)
    }
    lock.lock()
    active -= 1
    lock.unlock()
  }
}
