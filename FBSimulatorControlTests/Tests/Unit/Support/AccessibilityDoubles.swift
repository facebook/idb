/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import ObjectiveC

// MARK: - AXPTranslationObject Double

// The doubles below stand in for `AXPTranslator` and its object graph, which production
// code reaches through an `unsafeBitCast` and therefore messages through the Objective-C
// runtime. Only the substituted surface is `@objc`; the fixture and call-recording members
// are read from Swift by the tests themselves and stay invisible to Objective-C.

class FBSimulatorControlTests_AXPTranslationObject_Double: NSObject {
  @objc var bridgeDelegateToken: String?
  @objc var pid: pid_t = 12345
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

// Attributes the double does not model (placeholder/expanded/hidden/focused) are inert — none are
// in the default key set.
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
  func axIsEnabled() -> Bool? { isAccessibilityEnabled }
  func axIsRequired() -> Bool { isAccessibilityRequired }
  func axIsExpanded() -> Bool { false }
  func axIsHidden() -> Bool { false }
  func axIsFocused() -> Bool { false }
  // This double stands in for the legacy `AXPMacPlatformElement`, which has no counterpart for any of
  // these, so declining to answer is what the real backend does too.
  func axIsHittable() -> Bool? { nil }
  func axHittablePoint() -> CGPoint? { nil }
  func axCentrePoint() -> CGPoint? { nil }
  func axIsUserInteractionEnabled() -> Bool? { nil }
  func axExplainedBy() -> FBAXPlatformElement? { nil }
  func axCustomActionNames() -> [String] {
    (accessibilityCustomActions ?? []).compactMap { ($0 as? NSAccessibilityCustomAction)?.name }
  }
  func axActionNames() -> [String] { accessibilityActionNames().map { $0.rawValue } }
  func axTraits() -> [String]? { nil }
  func axChildren() -> [FBAXPlatformElement] {
    (accessibilityChildren ?? []).compactMap { $0 as? FBAXPlatformElement }
  }
  var axTranslationPid: pid_t { translation.pid }
  func axSetBridgeDelegateToken(_ token: String?) { translation.bridgeDelegateToken = token }
}

// Only press is exercised (via `FBAccessibilityElement.tap()`); scroll and set-value are inert.
extension FBSimulatorControlTests_AXPMacPlatformElement_Double: FBAXWritableElement {
  func axPerformPress() -> Bool { accessibilityPerformPress() }
  func axScroll(_ direction: FBAccessibilityScrollDirection) {}
  func axSetValue(_ value: Any?) {}
}

// MARK: - AXPTranslator Double

class FBSimulatorControlTests_AXPTranslator_Double: NSObject {
  var frontmostApplicationResult: FBSimulatorControlTests_AXPTranslationObject_Double?
  var objectAtPointResult: FBSimulatorControlTests_AXPTranslationObject_Double?
  var macPlatformElementResult: FBSimulatorControlTests_AXPMacPlatformElement_Double?
  /// Optional per-pid element results, keyed by the translation's pid. Lets a test
  /// return a distinct element for object-at-point hit-testing (remote content)
  /// versus the frontmost application. Falls back to `macPlatformElementResult`.
  var macPlatformElementResultsByPid: [pid_t: FBSimulatorControlTests_AXPMacPlatformElement_Double] = [:]
  /// Wall time burned inside the two calls the dispatcher times, so a test can assert a floor on the
  /// acquisition phases rather than merely non-negative. Zero by default.
  var frontmostApplicationDelay: TimeInterval = 0
  var macPlatformElementDelay: TimeInterval = 0
  @objc weak var bridgeTokenDelegate: AnyObject?
  private(set) var methodCalls = NSMutableArray()
  /// Invoked at the top of each frontmost resolution, on the thread driving it. Lets a
  /// test observe — or deliberately hold open — the window in which a resolution is
  /// inside the shared translator, so overlap between concurrent resolutions is testable.
  var resolutionEnterHook: (() -> Void)?

  @objc
  func frontmostApplication(withDisplayId displayId: Int32, bridgeDelegateToken token: String) -> FBSimulatorControlTests_AXPTranslationObject_Double? {
    resolutionEnterHook?()
    methodCalls.add("frontmostApplicationWithDisplayId:\(displayId) token:\(token)")
    if frontmostApplicationDelay > 0 {
      Thread.sleep(forTimeInterval: frontmostApplicationDelay)
    }
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

  @objc
  func macPlatformElement(fromTranslation translation: FBSimulatorControlTests_AXPTranslationObject_Double) -> FBSimulatorControlTests_AXPMacPlatformElement_Double? {
    methodCalls.add("macPlatformElementFromTranslation")
    if macPlatformElementDelay > 0 {
      Thread.sleep(forTimeInterval: macPlatformElementDelay)
    }
    let result = macPlatformElementResultsByPid[translation.pid] ?? macPlatformElementResult
    result?.translation = translation
    return result
  }

  @objc(translationApplicationObjectForPid:)
  func translationApplicationObject(forPid pid: pid_t) -> FBSimulatorControlTests_AXPTranslationObject_Double? {
    methodCalls.add("translationApplicationObjectForPid:\(pid)")
    let translation = FBSimulatorControlTests_AXPTranslationObject_Double()
    translation.pid = pid
    return translation
  }

  func resetTracking() {
    methodCalls.removeAllObjects()
  }
}

typealias FBAccessibilityResponseHandler = (Any, @escaping (Any?) -> Void) -> Void

// MARK: - SimDevice Accessibility Double

class FBSimulatorControlTests_SimDevice_Accessibility_Double: NSObject {
  @objc var name: String = ""
  @objc var UDID: NSUUID = NSUUID()
  @objc var state: UInt64 = 0
  var accessibilityResponseHandler: FBAccessibilityResponseHandler?
  private(set) var accessibilityRequests = NSMutableArray()

  @objc
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

  @objc var stateString: String {
    return "Booted"
  }
}

// MARK: - AXPTranslator Swizzling

class FBAccessibilityTranslatorSwizzler {
  private static var installedMockTranslator: FBSimulatorControlTests_AXPTranslator_Double?
  private static var originalSharedInstanceIMP: IMP?
  private static var swizzleInstalled = false

  class func installMockTranslator(_ mockTranslator: FBSimulatorControlTests_AXPTranslator_Double) {
    precondition(!swizzleInstalled, "Mock translator already installed. Call uninstall first.")

    installedMockTranslator = mockTranslator

    guard let axpTranslatorClass: AnyClass = objc_getClass("AXPTranslator") as? AnyClass else {
      fatalError("AXPTranslator class not found. Ensure AccessibilityPlatformTranslation framework is loaded.")
    }

    guard let originalMethod = class_getClassMethod(axpTranslatorClass, NSSelectorFromString("sharedInstance")) else {
      fatalError("+[AXPTranslator sharedInstance] method not found")
    }

    originalSharedInstanceIMP = method_getImplementation(originalMethod)

    let mockBlock: @convention(block) (AnyObject) -> AnyObject? = { _ in
      return FBAccessibilityTranslatorSwizzler.installedMockTranslator
    }
    let mockIMP = imp_implementationWithBlock(mockBlock)
    method_setImplementation(originalMethod, mockIMP)

    swizzleInstalled = true
  }

  class func uninstallMockTranslator() {
    guard swizzleInstalled else { return }

    guard let axpTranslatorClass: AnyClass = objc_getClass("AXPTranslator") as? AnyClass else { return }
    guard let originalMethod = class_getClassMethod(axpTranslatorClass, NSSelectorFromString("sharedInstance")) else { return }

    if let originalIMP = originalSharedInstanceIMP {
      method_setImplementation(originalMethod, originalIMP)
    }

    installedMockTranslator = nil
    originalSharedInstanceIMP = nil
    swizzleInstalled = false
  }
}

// MARK: - Element Builder

class FBAccessibilityTestElementBuilder {

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

  class func bootedSimulator() -> FBAccessibilityTestFixture {
    return FBAccessibilityTestFixture()
  }

  /// Installs the AXPTranslator swizzle and wires the translator's results.
  /// Tests build the dispatcher separately via
  /// `FBSimulator.createAccessibilityTranslationDispatcher(withTranslator:translator)`
  /// once setUp returns.
  func setUp() throws {
    try FBSimulatorControlFrameworkLoader.accessibilityFrameworks.loadPrivateFrameworks(FBControlCoreGlobalConfiguration.defaultLogger)

    let translation = FBSimulatorControlTests_AXPTranslationObject_Double()
    translation.pid = 12345

    translator.frontmostApplicationResult = translation
    translator.objectAtPointResult = translation

    if let rootElement {
      translator.macPlatformElementResult = rootElement
    } else {
      translator.macPlatformElementResult = FBAccessibilityTestElementBuilder.rootElement(withChildren: [])
    }

    FBAccessibilityTranslatorSwizzler.installMockTranslator(translator)
  }

  func tearDown() {
    FBAccessibilityTranslatorSwizzler.uninstallMockTranslator()
  }
}
