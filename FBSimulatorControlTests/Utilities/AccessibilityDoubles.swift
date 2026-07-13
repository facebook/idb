/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation

// MARK: - AXPTranslationObject Double

@objcMembers
class FBSimulatorControlTests_AXPTranslationObject_Double: NSObject {
  var bridgeDelegateToken: String?
  var pid: pid_t = 12345
}

// MARK: - AXPMacPlatformElement Double

@objc
class FBSimulatorControlTests_AXPMacPlatformElement_Double: NSObject {
  private let _label: String?
  private let _identifier: String?
  private let _role: String?
  private let _frame: NSRect
  private let _enabled: Bool
  private let _required: Bool
  private let _actionNames: [String]
  private let _children: [FBSimulatorControlTests_AXPMacPlatformElement_Double]
  private var _translation: FBSimulatorControlTests_AXPTranslationObject_Double
  @objc private(set) var accessedProperties = NSMutableSet()

  init(
    label: String?,
    identifier: String?,
    role: String?,
    frame: NSRect,
    enabled: Bool,
    actionNames: [String]?,
    children: [FBSimulatorControlTests_AXPMacPlatformElement_Double]?
  ) {
    _label = label
    _identifier = identifier
    _role = role
    _frame = frame
    _enabled = enabled
    _required = false
    _actionNames = actionNames ?? []
    _children = children ?? []
    _translation = FBSimulatorControlTests_AXPTranslationObject_Double()
    super.init()
  }

  // MARK: - Tracked Accessibility Properties

  @objc var accessibilityLabel: String? {
    accessedProperties.add("accessibilityLabel")
    return _label
  }

  @objc var accessibilityIdentifier: String? {
    accessedProperties.add("accessibilityIdentifier")
    return _identifier
  }

  @objc var accessibilityValue: Any? {
    accessedProperties.add("accessibilityValue")
    return nil
  }

  @objc var accessibilityTitle: String? {
    accessedProperties.add("accessibilityTitle")
    return nil
  }

  @objc var accessibilityHelp: String? {
    accessedProperties.add("accessibilityHelp")
    return nil
  }

  @objc var accessibilityRole: NSAccessibility.Role? {
    accessedProperties.add("accessibilityRole")
    if let role = _role {
      return NSAccessibility.Role(rawValue: role)
    }
    return nil
  }

  @objc var accessibilityRoleDescription: String? {
    accessedProperties.add("accessibilityRoleDescription")
    return nil
  }

  @objc var accessibilitySubrole: NSAccessibility.Subrole? {
    accessedProperties.add("accessibilitySubrole")
    return nil
  }

  @objc var accessibilityFrame: NSRect {
    accessedProperties.add("accessibilityFrame")
    return _frame
  }

  @objc var isAccessibilityEnabled: Bool {
    accessedProperties.add("accessibilityEnabled")
    return _enabled
  }

  @objc var isAccessibilityRequired: Bool {
    accessedProperties.add("accessibilityRequired")
    return _required
  }

  @objc var accessibilityCustomActions: [Any]? {
    accessedProperties.add("accessibilityCustomActions")
    return nil
  }

  @objc var accessibilityChildren: [Any]? {
    accessedProperties.add("accessibilityChildren")
    return _children
  }

  @objc override func accessibilityActionNames() -> [NSAccessibility.Action] {
    accessedProperties.add("accessibilityActionNames")
    return _actionNames.map { NSAccessibility.Action(rawValue: $0) }
  }

  @objc var translation: FBSimulatorControlTests_AXPTranslationObject_Double {
    get {
      accessedProperties.add("translation")
      return _translation
    }
    set {
      _translation = newValue
    }
  }

  @objc func accessibilityPerformPress() -> Bool {
    return true
  }
}

// Conforms the element double to the production seam. Each accessor routes through
// the existing tracked properties so `accessedProperties` behavior is unchanged.
// Attributes the double does not model (placeholder/expanded/hidden/focused) and
// actions it does not perform (scroll/setValue) are inert — none are in the default
// key set, so the unit suites never exercise them.
extension FBSimulatorControlTests_AXPMacPlatformElement_Double: FBAXPlatformElement {
  func axFrame() -> NSRect { accessibilityFrame }
  func axRole() -> String? { accessibilityRole?.rawValue }
  func axLabel() -> String? { accessibilityLabel }
  func axValue() -> Any? { accessibilityValue }
  func axIdentifier() -> String? { accessibilityIdentifier }
  func axTitle() -> String? { accessibilityTitle }
  func axHelp() -> String? { accessibilityHelp }
  func axRoleDescription() -> String? { accessibilityRoleDescription }
  func axSubrole() -> String? { accessibilitySubrole?.rawValue }
  func axPlaceholderValue() -> String? { nil }
  func axIsEnabled() -> Bool { isAccessibilityEnabled }
  func axIsRequired() -> Bool { isAccessibilityRequired }
  func axIsExpanded() -> Bool { false }
  func axIsHidden() -> Bool { false }
  func axIsFocused() -> Bool { false }
  func axCustomActionNames() -> [String] {
    (accessibilityCustomActions ?? []).compactMap { ($0 as? NSAccessibilityCustomAction)?.name }
  }
  func axActionNames() -> [String] { accessibilityActionNames().map { $0.rawValue } }
  func axTraits() -> [String]? { nil }
  func axChildren() -> [FBAXPlatformElement] {
    (accessibilityChildren ?? []).compactMap { $0 as? FBAXPlatformElement }
  }
  func axPerformPress() -> Bool { accessibilityPerformPress() }
  func axScroll(_ direction: FBAccessibilityScrollDirection) {}
  func axSetValue(_ value: Any?) {}
  var axTranslationPid: pid_t { translation.pid }
  func axSetBridgeDelegateToken(_ token: String?) { translation.bridgeDelegateToken = token }
}

// MARK: - AXPTranslator Double

@objcMembers
class FBSimulatorControlTests_AXPTranslator_Double: NSObject {
  var frontmostApplicationResult: FBSimulatorControlTests_AXPTranslationObject_Double?
  var objectAtPointResult: FBSimulatorControlTests_AXPTranslationObject_Double?
  var macPlatformElementResult: FBSimulatorControlTests_AXPMacPlatformElement_Double?
  /// Optional per-pid element results, keyed by the translation's pid. Lets a test
  /// return a distinct element for object-at-point hit-testing (remote content)
  /// versus the frontmost application. Falls back to `macPlatformElementResult`.
  var macPlatformElementResultsByPid: [pid_t: FBSimulatorControlTests_AXPMacPlatformElement_Double] = [:]
  weak var bridgeTokenDelegate: AnyObject?
  private(set) var methodCalls = NSMutableArray()

  func frontmostApplication(withDisplayId displayId: Int32, bridgeDelegateToken token: String) -> FBSimulatorControlTests_AXPTranslationObject_Double? {
    methodCalls.add("frontmostApplicationWithDisplayId:\(displayId) token:\(token)")
    let result = frontmostApplicationResult
    result?.bridgeDelegateToken = token
    return result
  }

  @objc(objectAtPoint:displayId:bridgeDelegateToken:)
  func object(at point: CGPoint, displayId: Int32, bridgeDelegateToken token: String) -> FBSimulatorControlTests_AXPTranslationObject_Double? {
    methodCalls.add("objectAtPoint:{\(String(format: "%.1f", point.x)),\(String(format: "%.1f", point.y))} displayId:\(displayId) token:\(token)")
    let result = objectAtPointResult
    result?.bridgeDelegateToken = token
    return result
  }

  func macPlatformElement(fromTranslation translation: FBSimulatorControlTests_AXPTranslationObject_Double) -> FBSimulatorControlTests_AXPMacPlatformElement_Double? {
    methodCalls.add("macPlatformElementFromTranslation")
    let result = macPlatformElementResultsByPid[translation.pid] ?? macPlatformElementResult
    result?.translation = translation
    return result
  }

  func resetTracking() {
    methodCalls.removeAllObjects()
  }
}

// MARK: - Accessibility Response Handler

typealias FBAccessibilityResponseHandler = (Any, @escaping (Any?) -> Void) -> Void

// MARK: - SimDevice Accessibility Double

@objcMembers
class FBSimulatorControlTests_SimDevice_Accessibility_Double: NSObject {
  var name: String = ""
  var UDID: NSUUID = NSUUID()
  var state: UInt64 = 0
  var accessibilityResponseHandler: FBAccessibilityResponseHandler?
  private(set) var accessibilityRequests = NSMutableArray()

  func sendAccessibilityRequestAsync(_ request: Any, completionQueue queue: DispatchQueue, completionHandler handler: @escaping (Any?) -> Void) {
    accessibilityRequests.add(request)
    if let responseHandler = accessibilityResponseHandler {
      responseHandler(request) { response in
        queue.async {
          handler(response)
        }
      }
    } else {
      queue.async {
        handler(nil)
      }
    }
  }

  func resetAccessibilityTracking() {
    accessibilityRequests.removeAllObjects()
  }

  var stateString: String {
    return "Booted"
  }
}

// MARK: - Element Builder

class FBAccessibilityTestElementBuilder: NSObject {

  class func element(withLabel label: String, frame: NSRect, children: [FBSimulatorControlTests_AXPMacPlatformElement_Double]?) -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    return FBSimulatorControlTests_AXPMacPlatformElement_Double(
      label: label,
      identifier: nil,
      role: "AXButton",
      frame: frame,
      enabled: true,
      actionNames: ["AXPress"],
      children: children
    )
  }

  class func rootElement(withChildren children: [FBSimulatorControlTests_AXPMacPlatformElement_Double]) -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    return application(withLabel: "Root", frame: NSRect(x: 0, y: 0, width: 390, height: 844), children: children)
  }

  class func application(withLabel label: String, frame: NSRect, children: [FBSimulatorControlTests_AXPMacPlatformElement_Double]) -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    return FBSimulatorControlTests_AXPMacPlatformElement_Double(
      label: label,
      identifier: nil,
      role: "AXApplication",
      frame: frame,
      enabled: true,
      actionNames: nil,
      children: children
    )
  }

  class func button(withLabel label: String, identifier: String?, frame: NSRect) -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    return FBSimulatorControlTests_AXPMacPlatformElement_Double(
      label: label,
      identifier: identifier,
      role: "AXButton",
      frame: frame,
      enabled: true,
      actionNames: ["AXPress"],
      children: nil
    )
  }

  class func staticText(withLabel label: String, frame: NSRect) -> FBSimulatorControlTests_AXPMacPlatformElement_Double {
    return FBSimulatorControlTests_AXPMacPlatformElement_Double(
      label: label,
      identifier: nil,
      role: "AXStaticText",
      frame: frame,
      enabled: true,
      actionNames: nil,
      children: nil
    )
  }
}

// MARK: - Test Fixture

private let FBiOSTargetStateBooted_Value: UInt64 = 3

class FBAccessibilityTestFixture: NSObject {
  private(set) var translator: FBSimulatorControlTests_AXPTranslator_Double
  private(set) var device: FBSimulatorControlTests_SimDevice_Accessibility_Double
  var rootElement: FBSimulatorControlTests_AXPMacPlatformElement_Double?

  private override init() {
    self.translator = FBSimulatorControlTests_AXPTranslator_Double()
    self.device = FBSimulatorControlTests_SimDevice_Accessibility_Double()
    self.device.state = FBiOSTargetStateBooted_Value
    super.init()
  }

  class func bootedSimulatorFixture() -> FBAccessibilityTestFixture {
    return FBAccessibilityTestFixture()
  }

  // Convenience for call sites using bootedSimulator() style
  class func bootedSimulator() -> FBAccessibilityTestFixture {
    return bootedSimulatorFixture()
  }

  /// Wires the opaque translator double's results. Tests inject it directly into
  /// a dispatcher, so no private framework load or singleton swizzle is needed.
  func setUp() {
    let translation = FBSimulatorControlTests_AXPTranslationObject_Double()
    translation.pid = 12345

    translator.frontmostApplicationResult = translation
    translator.objectAtPointResult = translation

    if let rootElement {
      translator.macPlatformElementResult = rootElement
    } else {
      translator.macPlatformElementResult = FBAccessibilityTestElementBuilder.rootElement(withChildren: [])
    }

  }

  func tearDown() {}
}
