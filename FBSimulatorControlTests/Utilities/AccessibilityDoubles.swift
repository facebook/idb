/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

import FBControlCore
import Foundation
import ObjectiveC

@testable import FBSimulatorControl

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

// MARK: - AXPTranslator Double

@objcMembers
class FBSimulatorControlTests_AXPTranslator_Double: NSObject {
  var frontmostApplicationResult: FBSimulatorControlTests_AXPTranslationObject_Double?
  var objectAtPointResult: FBSimulatorControlTests_AXPTranslationObject_Double?
  var macPlatformElementResult: FBSimulatorControlTests_AXPMacPlatformElement_Double?
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
    let result = macPlatformElementResult
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

// MARK: - AXPTranslator Swizzling

class FBAccessibilityTranslatorSwizzler: NSObject {
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

// MARK: - FBSimulator Double

private let FBiOSTargetStateBooted_Value: UInt64 = 3

@objcMembers
class FBSimulatorControlTests_FBSimulator_Double: NSObject {
  var device: FBSimulatorControlTests_SimDevice_Accessibility_Double
  var workQueue: DispatchQueue
  var asyncQueue: DispatchQueue
  var state: UInt64
  var logger: FBControlCoreLogger?
  var mockTranslationDispatcher: AnyObject?

  init(device: FBSimulatorControlTests_SimDevice_Accessibility_Double) {
    self.device = device
    self.workQueue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.tests.workqueue")
    self.asyncQueue = DispatchQueue.global(qos: .userInitiated)
    self.state = FBiOSTargetStateBooted_Value
    super.init()
  }

  func accessibilityTranslationDispatcher() -> AnyObject? {
    return mockTranslationDispatcher
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

class FBAccessibilityTestFixture: NSObject {
  private(set) var translator: FBSimulatorControlTests_AXPTranslator_Double
  private(set) var simulator: FBSimulatorControlTests_FBSimulator_Double
  var rootElement: FBSimulatorControlTests_AXPMacPlatformElement_Double?

  private override init() {
    let device = FBSimulatorControlTests_SimDevice_Accessibility_Double()
    self.simulator = FBSimulatorControlTests_FBSimulator_Double(device: device)
    self.simulator.state = FBiOSTargetStateBooted_Value
    self.translator = FBSimulatorControlTests_AXPTranslator_Double()
    super.init()
  }

  class func bootedSimulatorFixture() -> FBAccessibilityTestFixture {
    return FBAccessibilityTestFixture()
  }

  // Convenience for call sites using bootedSimulator() style
  class func bootedSimulator() -> FBAccessibilityTestFixture {
    return bootedSimulatorFixture()
  }

  func setUp() {
    FBSimulatorControlFrameworkLoader.accessibilityFrameworks.loadPrivateFrameworksOrAbort()

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

    let dispatcher = FBSimulator.createAccessibilityTranslationDispatcher(withTranslator: translator)
    simulator.mockTranslationDispatcher = dispatcher as AnyObject
  }

  func tearDown() {
    simulator.mockTranslationDispatcher = nil
    FBAccessibilityTranslatorSwizzler.uninstallMockTranslator()
  }
}
