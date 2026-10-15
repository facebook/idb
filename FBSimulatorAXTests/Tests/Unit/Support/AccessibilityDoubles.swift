/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import AccessibilityPlatformTranslation
import AppKit
import FBControlCore
@testable import FBSimulatorAX
import FBSimulatorBridgeProtocol
@testable import FBSimulatorControl
import Foundation
import ObjectiveC

// MARK: - AXPTranslationObject Double

// The doubles below stand in for `AXPTranslator` and its object graph, which production
// code reaches through an `unsafeBitCast` and therefore messages through the Objective-C
// runtime. Only the substituted surface is `@objc`; the fixture and call-recording members
// are read from Swift by the tests themselves and stay invisible to Objective-C.

class AXPTranslationObjectDouble: NSObject, AXTranslationReference {
  @objc var bridgeDelegateToken: String!
  @objc var pid: pid_t = 12345
  @objc var objectID: UInt64 = 0

  convenience init(pid: pid_t, objectID: UInt64) {
    self.init()
    self.pid = pid
    self.objectID = objectID
  }
}

// MARK: - AXPMacPlatformElement Double

@objc
class AXPMacPlatformElementDouble: NSObject {
  private let _label: String?
  private let _identifier: String?
  private let _role: String?
  private let _frame: NSRect
  private let _enabled: Bool
  private let _required: Bool
  private let _actionNames: [String]
  private let _customActionNames: [String]
  private let _customActionResult: Bool
  private let _children: [AXPMacPlatformElementDouble]
  private var _translation: AXPTranslationObjectDouble
  private(set) var performedCustomActions: [String] = []
  @objc private(set) var accessedProperties = NSMutableSet()
  /// The names of each multiple-attribute request, in order.
  private(set) var multipleAttributeRequests: [[String]] = []

  init(
    label: String?,
    identifier: String?,
    role: String?,
    frame: NSRect,
    enabled: Bool,
    actionNames: [String]?,
    customActionNames: [String] = [],
    customActionResult: Bool = true,
    children: [AXPMacPlatformElementDouble]?
  ) {
    _label = label
    _identifier = identifier
    _role = role
    _frame = frame
    _enabled = enabled
    _required = false
    _actionNames = actionNames ?? []
    _customActionNames = customActionNames
    _customActionResult = customActionResult
    _children = children ?? []
    _translation = AXPTranslationObjectDouble()
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
    return _customActionNames.map { name in
      NSAccessibilityCustomAction(name: name) { [weak self] in
        guard let self else { return false }
        performedCustomActions.append(name)
        return _customActionResult
      }
    }
  }

  @objc var accessibilityChildren: [Any]? {
    accessedProperties.add("accessibilityChildren")
    return _children
  }

  @objc override func accessibilityActionNames() -> [NSAccessibility.Action] {
    accessedProperties.add("accessibilityActionNames")
    return _actionNames.map { NSAccessibility.Action(rawValue: $0) }
  }

  @objc var translation: AXPTranslationObjectDouble {
    get {
      accessedProperties.add("translation")
      return _translation
    }
    set {
      _translation = newValue
    }
  }

  /// Invoked inside every press, on the thread performing it.
  var pressHook: (() -> Void)?

  @objc func accessibilityPerformPress() -> Bool {
    pressHook?()
    return true
  }
}

// Attributes the double does not model (placeholder/expanded/hidden/focused) are inert — none are
// in the default key set.
extension AXPMacPlatformElementDouble: AXPlatformElement {
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
  func axCustomActionNames() -> [String] {
    (accessibilityCustomActions ?? []).compactMap { ($0 as? NSAccessibilityCustomAction)?.name }
  }
  func axActionNames() -> [String] { accessibilityActionNames().map { $0.rawValue } }
  func axTraits() -> [String]? { nil }
  func axChildren() -> [AXPlatformElement] {
    (accessibilityChildren ?? []).compactMap { $0 as? AXPlatformElement }
  }
  /// Answers as the real element does, one entry per attribute with a value, without touching the single
  /// accessors, so a test can tell a batched read from a per-attribute one.
  func axMultipleAttributes(_ names: [String]) -> [String: Any] {
    accessedProperties.add("accessibilityMultipleAttributes")
    multipleAttributeRequests.append(names)
    var values: [String: Any] = [
      "AXFrame": NSValue(rect: _frame),
      "AXEnabled": NSNumber(value: _enabled),
      "AXRequired": NSNumber(value: _required),
      "AXChildren": _children,
    ]
    values["AXDescription"] = _label
    values["AXIdentifier"] = _identifier
    values["AXRole"] = _role
    return values.filter { names.contains($0.key) }
  }
  var axTranslationPid: pid_t { translation.pid }
  var axTranslationReference: AXTranslationReference? { translation }
  func axSetBridgeDelegateToken(_ token: String?) { translation.bridgeDelegateToken = token }
}

extension AXPMacPlatformElementDouble {
  /// The element's descendants, depth first, starting with itself.
  var subtree: [AXPMacPlatformElementDouble] {
    [self] + _children.flatMap(\.subtree)
  }

  /// What the accessibility service answers a multiple-attribute request for this element with: the values
  /// the double models, in the translator's vocabulary, with its children named by their translations.
  var translatorAnswer: [BridgeAXTranslatorAttribute: Any] {
    var values: [BridgeAXTranslatorAttribute: Any] = [
      .frame: NSValue(rect: _frame),
      .isEnabled: NSNumber(value: _enabled),
      .children: _children.map(\.translation),
    ]
    values[.label] = _label
    values[.identifier] = _identifier
    values[.role] = BridgeAXTranslatorRole.allCases.first { "AX\($0.name)" == _role }.map { NSNumber(value: $0.rawValue) }
    return values
  }
}

// Only press is exercised (via `AccessibilityElement.tap()`); scroll and set-value are inert.
extension AXPMacPlatformElementDouble: AXWritableElement {
  func axPerformPress() -> Bool { accessibilityPerformPress() }
  func axPerformCustomAction(named name: String) -> Bool {
    guard
      let action = (accessibilityCustomActions ?? [])
        .compactMap({ $0 as? NSAccessibilityCustomAction })
        .first(where: { $0.name == name })
    else {
      return false
    }
    return invokeAccessibilityCustomAction(action)
  }
  func axScroll(_ direction: AccessibilityScrollDirection) {}
  func axSetValue(_ value: Any?) {}
}

// MARK: - Snapshot-backed AXPlatformElement Double

/// Presents a decoded snapshot as a translator element, so a translator read can be driven from the same
/// attribute-dictionary fixtures the guest-backed suites use. Attributes the snapshot does not carry read
/// as the translator's defaults.
final class AXSnapshotPlatformElementDouble: AXPlatformElement {
  private let snapshot: AXElementSnapshot

  init(_ snapshot: AXElementSnapshot) {
    self.snapshot = snapshot
  }

  func axFrame() -> NSRect { snapshot.frame }
  func axRole() -> String? { snapshot.role }
  func axLabel() -> String? { snapshot.label }
  func axValue() -> Any? { snapshot.stringValue }
  func axIdentifier() -> String? { snapshot.identifier }
  func axTitle() -> String? { snapshot.title }
  func axHelp() -> String? { snapshot.help }
  func axRoleDescription() -> String? { snapshot.roleDescription }
  func axSubrole() -> String? { snapshot.subrole }
  func axPlaceholderValue() -> String? { snapshot.placeholder }
  func axIsEnabled() -> Bool? { snapshot.isEnabled }
  func axIsRequired() -> Bool { snapshot.isRequired ?? false }
  func axIsExpanded() -> Bool { snapshot.isExpanded ?? false }
  func axIsHidden() -> Bool { snapshot.isHidden ?? false }
  func axIsFocused() -> Bool { snapshot.isFocused ?? false }
  func axCustomActionNames() -> [String] { snapshot.customActionNames ?? [] }
  func axActionNames() -> [String] { [] }
  func axTraits() -> [String]? { snapshot.traits }
  func axChildren() -> [AXPlatformElement] { snapshot.children.map(AXSnapshotPlatformElementDouble.init) }
  func axMultipleAttributes(_ names: [String]) -> [String: Any] {
    var values: [String: Any] = [
      "AXFrame": NSValue(rect: snapshot.frame),
      "AXChildren": snapshot.children.map(AXSnapshotPlatformElementDouble.init),
      "AXEnabled": NSNumber(value: snapshot.isEnabled ?? false),
      "AXRequired": NSNumber(value: snapshot.isRequired ?? false),
      "AXExpanded": NSNumber(value: snapshot.isExpanded ?? false),
      "AXHidden": NSNumber(value: snapshot.isHidden ?? false),
      "AXFocused": NSNumber(value: snapshot.isFocused ?? false),
    ]
    values["AXRole"] = snapshot.role
    values["AXDescription"] = snapshot.label
    values["AXValue"] = snapshot.stringValue
    values["AXIdentifier"] = snapshot.identifier
    values["AXTitle"] = snapshot.title
    values["AXHelp"] = snapshot.help
    values["AXRoleDescription"] = snapshot.roleDescription
    values["AXSubrole"] = snapshot.subrole
    values["AXPlaceholderValue"] = snapshot.placeholder
    return values.filter { names.contains($0.key) }
  }
  var axTranslationPid: pid_t { snapshot.pid }
  var axTranslationReference: AXTranslationReference? { nil }
  func axSetBridgeDelegateToken(_ token: String?) {}
}

// MARK: - AXTranslationTransport Double

/// Records every translator request a read sends, and answers each with the empty response — or, when it
/// does not answer, with nothing, as a transport whose wait timed out does.
final class AXTranslationTransportDouble: AXTranslationTransport, @unchecked Sendable {
  let kind = AXTranslationTransportKind.coreSimulator
  private let lock = NSLock()
  private var _requests: [AXPTranslatorRequest] = []
  private let answers: Bool
  private let resultData: NSNumber?
  private let root: AXPTranslationObjectDouble?

  /// `resultData` is what every answer carries; the empty response carries none. A root lookup is answered
  /// with `root` instead, so a read can resolve one.
  init(answers: Bool = true, resultData: NSNumber? = nil, root: AXPTranslationObjectDouble? = nil) {
    self.answers = answers
    self.resultData = resultData
    self.root = root
  }

  var requests: [AXPTranslatorRequest] {
    lock.lock()
    defer { lock.unlock() }
    return _requests
  }

  func send(_ request: AXPTranslatorRequest, timeout: TimeInterval) -> AXPTranslatorResponse? {
    lock.lock()
    _requests.append(request)
    lock.unlock()
    guard answers, let response = AXPTranslatorResponse.empty() as? AXPTranslatorResponse else {
      return nil
    }
    switch BridgeAXTranslatorRequestType(rawValue: Int(request.requestType)) {
    case .application, .frontmostApplication, .hitTest:
      // By key: the double is not the secure-coding object the property is typed as.
      response.setValue(root, forKey: "resultData")
    case .attribute, .multipleAttribute, nil:
      response.resultData = resultData
    }
    return response
  }
}

// MARK: - Raw translator transport Double

/// Answers multiple-attribute requests as the accessibility service does: from a fixture of each element's
/// values, keyed by the requested translation's object ID, carrying only the attributes asked for. Records
/// every request.
final class AXRawTranslationTransportDouble: AXTranslationTransport, @unchecked Sendable {
  let kind = AXTranslationTransportKind.bridge
  private let lock = NSLock()
  private var _requests: [AXPTranslatorRequest] = []
  private let elements: [UInt64: [BridgeAXTranslatorAttribute: Any]]

  /// An object ID the fixture has no entry for is not answered, as a timed-out send is not.
  init(elements: [UInt64: [BridgeAXTranslatorAttribute: Any]]) {
    self.elements = elements
  }

  var requests: [AXPTranslatorRequest] {
    lock.withLock { _requests }
  }

  /// The object ID each request named, in order.
  var requestedObjectIDs: [UInt64] {
    requests.compactMap { (($0 as NSObject).value(forKey: "translation") as? AXPTranslationObjectDouble)?.objectID }
  }

  /// The attributes each request asked for, in order.
  var requestedAttributes: [[Int]] {
    requests.map { (($0.parameters?["attributes"] as? [NSNumber]) ?? []).map(\.intValue) }
  }

  func send(_ request: AXPTranslatorRequest, timeout: TimeInterval) -> AXPTranslatorResponse? {
    lock.withLock { _requests.append(request) }
    guard let translation = (request as NSObject).value(forKey: "translation") as? AXPTranslationObjectDouble,
      let values = elements[translation.objectID],
      let response = AXPTranslatorResponse.empty() as? AXPTranslatorResponse
    else {
      return nil
    }
    let asked = Set(((request.parameters?["attributes"] as? [NSNumber]) ?? []).map(\.intValue))
    let answer = NSMutableDictionary()
    for (attribute, value) in values where asked.contains(attribute.rawValue) {
      answer[NSNumber(value: attribute.rawValue)] = value
    }
    response.resultData = answer
    return response
  }
}

// MARK: - AXPTranslator Double

class AXPTranslatorDouble: NSObject {
  var frontmostApplicationResult: AXPTranslationObjectDouble?
  var objectAtPointResult: AXPTranslationObjectDouble?
  var macPlatformElementResult: AXPMacPlatformElementDouble?
  /// Optional per-pid element results, keyed by the translation's pid. Lets a test
  /// return a distinct element for object-at-point hit-testing (remote content)
  /// versus the frontmost application. Falls back to `macPlatformElementResult`.
  var macPlatformElementResultsByPid: [pid_t: AXPMacPlatformElementDouble] = [:]
  /// The element for each translation the fixture's tree hands out, so an element a raw read names by its
  /// translation is the same double the tree holds.
  var elementsByObjectID: [UInt64: AXPMacPlatformElementDouble] = [:]
  /// The root lookups the fixture's accessibility service answered, in order.
  var rawLookups: [BridgeAXTranslatorRequestType] = []
  /// The point and display of each hit-test the fixture's accessibility service answered, in order.
  struct HitTest: Equatable {
    let point: CGPoint
    let displayID: UInt32
  }
  var rawHitTests: [HitTest] = []
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
  /// The `clientType` of each request to send through the bridge delegate during a frontmost resolution, as
  /// the real translator does when it reads the application's attributes. Empty sends none.
  var bridgeRequestClientTypes: [UInt64] = []

  @objc
  func frontmostApplication(withDisplayId displayId: Int32, bridgeDelegateToken token: String) -> AXPTranslationObjectDouble? {
    resolutionEnterHook?()
    methodCalls.add("frontmostApplicationWithDisplayId:\(displayId) token:\(token)")
    if frontmostApplicationDelay > 0 {
      Thread.sleep(forTimeInterval: frontmostApplicationDelay)
    }
    sendBridgeRequests(token: token)
    let result = frontmostApplicationResult
    result?.bridgeDelegateToken = token
    return result
  }

  /// What the bridge delegate answered each request in `bridgeRequestClientTypes` with, in order.
  private(set) var bridgeResponses: [AnyObject?] = []

  private func sendBridgeRequests(token: String) {
    for clientType in bridgeRequestClientTypes {
      bridgeResponses.append(
        AccessibilityTranslatorRequests.send(AccessibilityTranslatorRequests.make(clientType: clientType), through: bridgeTokenDelegate, token: token))
    }
  }

  @objc(objectAtPoint:displayId:bridgeDelegateToken:)
  func object(at point: CGPoint, displayId: Int32, bridgeDelegateToken token: String) -> AXPTranslationObjectDouble? {
    methodCalls.add("objectAtPoint:{\(String(format: "%.1f", point.x)),\(String(format: "%.1f", point.y))} displayId:\(displayId) token:\(token)")
    let result = objectAtPointResult
    result?.bridgeDelegateToken = token
    return result
  }

  @objc
  func macPlatformElement(fromTranslation translation: AXPTranslationObjectDouble) -> AXPMacPlatformElementDouble? {
    methodCalls.add("macPlatformElementFromTranslation")
    if macPlatformElementDelay > 0 {
      Thread.sleep(forTimeInterval: macPlatformElementDelay)
    }
    if let cached = cachedElementsByObjectID[translation.objectID] {
      return cached
    }
    if let element = elementsByObjectID[translation.objectID] {
      return element
    }
    let result = macPlatformElementResultsByPid[translation.pid] ?? macPlatformElementResult
    result?.translation = translation
    return result
  }

  /// Elements the translator has already built, by object ID. Returned as they are, keeping the translation —
  /// and so the token — they were built with, as the translator's element cache does.
  var cachedElementsByObjectID: [UInt64: AXPMacPlatformElementDouble] = [:]

  @objc(translationApplicationObjectForPid:)
  /// As the real translator does: asks the bridge with an application-object request that carries no
  /// translation, and so no bridge-delegate token, and answers only if the bridge did.
  func translationApplicationObject(forPid pid: pid_t) -> AXPTranslationObjectDouble? {
    methodCalls.add("translationApplicationObjectForPid:\(pid)")
    let request = AccessibilityTranslatorRequests.make(clientType: 0)
    request?.setValue(1, forKey: "requestType")
    request?.setValue(["pid": pid], forKey: "parameters")
    let response = AccessibilityTranslatorRequests.send(request, through: bridgeTokenDelegate, token: "")
    guard response?.value(forKey: "resultData") != nil else {
      return nil
    }
    let translation = AXPTranslationObjectDouble()
    translation.pid = pid
    return translation
  }
}

/// Builds, sends and reads real `AXPTranslatorRequest`s through the Objective-C runtime, as the translator
/// does: the test bundle cannot link against the private framework's classes.
enum AccessibilityTranslatorRequests {
  private typealias BridgeCallback = @convention(block) (AnyObject?) -> AnyObject?

  static func make(clientType: UInt64) -> NSObject? {
    guard let requestClass = NSClassFromString("AXPTranslatorRequest") as? NSObject.Type else {
      return nil
    }
    let request = requestClass.init()
    request.setValue(clientType, forKey: "clientType")
    return request
  }

  /// Sends `request` through the bridge-token delegate's callback for `token`, returning the response.
  @discardableResult
  static func send(_ request: NSObject?, through delegate: AnyObject?, token: String) -> AnyObject? {
    let selector = NSSelectorFromString("accessibilityTranslationDelegateBridgeCallbackWithToken:")
    guard let delegate = delegate as? NSObject, delegate.responds(to: selector),
      let block = delegate.perform(selector, with: token)?.takeUnretainedValue()
    else {
      return nil
    }
    return unsafeBitCast(block, to: BridgeCallback.self)(request)
  }

  static func clientType(of request: Any) -> UInt64? {
    ((request as AnyObject).value(forKey: "clientType") as? NSNumber)?.uint64Value
  }
}

typealias AccessibilityResponseHandler = (Any, @escaping (Any?) -> Void) -> Void

// MARK: - Resolution without a client

extension SimulatorAccessibilityCommands {
  /// Resolution as a default read would make it.
  func resolveElement(for query: AccessibilityElementQuery) async throws -> AccessibilityElement {
    try await resolveElement(for: query, clientType: AccessibilityRequestOptions().resolvedClientType)
  }
}

extension AXTranslationRequest {
  /// A request as a default read would make it, over a transport that answers nothing unless given one.
  convenience init(kind: Kind, display: AXTranslationDisplay? = nil, transport: any AXTranslationTransport = AXTranslationTransportDouble()) {
    self.init(kind: kind, display: display, clientType: AccessibilityRequestOptions().resolvedClientType, transport: transport)
  }
}

// MARK: - SimDevice Accessibility Double

class SimDeviceAccessibilityDouble: NSObject {
  @objc var name: String = ""
  @objc var UDID: NSUUID = NSUUID()
  @objc var state: UInt64 = 0
  var accessibilityResponseHandler: AccessibilityResponseHandler?
  private let requestsLock = NSLock()
  private(set) var accessibilityRequests = NSMutableArray()

  @objc
  func sendAccessibilityRequestAsync(_ request: Any, completionQueue queue: DispatchQueue, completionHandler handler: @escaping (Any?) -> Void) {
    requestsLock.withLock { accessibilityRequests.add(request) }
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

  @objc var stateString: String {
    return "Booted"
  }
}

// MARK: - AXPTranslator Swizzling

class AccessibilityTranslatorSwizzler {
  private static var installedMockTranslator: AXPTranslatorDouble?
  private static var originalSharedInstanceIMP: IMP?
  private static var swizzleInstalled = false

  class func installMockTranslator(_ mockTranslator: AXPTranslatorDouble) {
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
      return AccessibilityTranslatorSwizzler.installedMockTranslator
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

class AccessibilityTestElementBuilder {

  class func element(withLabel label: String, frame: NSRect, children: [AXPMacPlatformElementDouble]?) -> AXPMacPlatformElementDouble {
    return AXPMacPlatformElementDouble(
      label: label,
      identifier: nil,
      role: "AXButton",
      frame: frame,
      enabled: true,
      actionNames: ["AXPress"],
      children: children
    )
  }

  class func rootElement(withChildren children: [AXPMacPlatformElementDouble]) -> AXPMacPlatformElementDouble {
    return application(withLabel: "Root", frame: NSRect(x: 0, y: 0, width: 390, height: 844), children: children)
  }

  class func application(withLabel label: String, frame: NSRect, children: [AXPMacPlatformElementDouble]) -> AXPMacPlatformElementDouble {
    return AXPMacPlatformElementDouble(
      label: label,
      identifier: nil,
      role: "AXApplication",
      frame: frame,
      enabled: true,
      actionNames: nil,
      children: children
    )
  }

  class func button(withLabel label: String, identifier: String?, frame: NSRect) -> AXPMacPlatformElementDouble {
    return AXPMacPlatformElementDouble(
      label: label,
      identifier: identifier,
      role: "AXButton",
      frame: frame,
      enabled: true,
      actionNames: ["AXPress"],
      children: nil
    )
  }

  class func staticText(withLabel label: String, frame: NSRect) -> AXPMacPlatformElementDouble {
    return AXPMacPlatformElementDouble(
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

private let FBTargetStateBooted_Value: UInt64 = 3

class AccessibilityTestFixture: NSObject {
  private(set) var translator: AXPTranslatorDouble
  private(set) var device: SimDeviceAccessibilityDouble
  var rootElement: AXPMacPlatformElementDouble?

  private override init() {
    self.translator = AXPTranslatorDouble()
    self.device = SimDeviceAccessibilityDouble()
    self.device.state = FBTargetStateBooted_Value
    super.init()
  }

  class func bootedSimulator() -> AccessibilityTestFixture {
    return AccessibilityTestFixture()
  }

  /// Installs the AXPTranslator swizzle and wires the translator's results.
  /// Tests build the dispatcher separately via
  /// `Simulator.createAccessibilityTranslationDispatcher(withTranslator:translator)`
  /// once setUp returns.
  func setUp() throws {
    try SimulatorControlFrameworkLoader.accessibilityFrameworks.loadPrivateFrameworks(ControlCoreGlobalConfiguration.defaultLogger)

    let translation = AXPTranslationObjectDouble()
    translation.pid = 12345

    translator.frontmostApplicationResult = translation
    translator.objectAtPointResult = translation

    if let rootElement {
      translator.macPlatformElementResult = rootElement
    } else {
      translator.macPlatformElementResult = AccessibilityTestElementBuilder.rootElement(withChildren: [])
    }
    serveTranslatorRequests()

    AccessibilityTranslatorSwizzler.installMockTranslator(translator)
  }

  func tearDown() {
    AccessibilityTranslatorSwizzler.uninstallMockTranslator()
  }

  /// Answers multiple-attribute requests as CoreSimulatorBridge's accessibility service does, from the tree
  /// the translator currently resolves: every element below the root gets a translation of its own, and a
  /// request naming one is answered with that element's values. The root, and a remote element a hit-test
  /// resolves, keep the translation the translator's resolution hands them. Other requests go unanswered,
  /// as before.
  func serveTranslatorRequests() {
    let translator = self.translator
    // Raw reads arrive concurrently; only the bookkeeping is serialized, so a test can still observe two
    // requests in flight at once.
    let bookkeeping = NSLock()
    var nextObjectID: UInt64 = 1
    func element(named translation: AXPTranslationObjectDouble) -> AXPMacPlatformElementDouble? {
      bookkeeping.lock()
      defer { bookkeeping.unlock() }
      guard let root = translator.macPlatformElementResult else {
        return nil
      }
      for descendant in root.subtree.dropFirst() where descendant.translation.objectID == 0 {
        descendant.translation = AXPTranslationObjectDouble(pid: descendant.translation.pid, objectID: nextObjectID)
        translator.elementsByObjectID[nextObjectID] = descendant
        nextObjectID += 1
      }
      guard translation.objectID == 0 else {
        return translator.elementsByObjectID[translation.objectID]
      }
      return translator.macPlatformElementResultsByPid[translation.pid] ?? root
    }
    device.accessibilityResponseHandler = { request, respond in
      let request = request as AnyObject
      let requestType = (request.value(forKey: "requestType") as? NSNumber).flatMap { BridgeAXTranslatorRequestType(rawValue: $0.intValue) }
      let parameters = request.value(forKey: "parameters") as? NSDictionary
      // Root lookups answer with the translations the translator double would have returned.
      let lookup: AXPTranslationObjectDouble?
      switch requestType {
      case .frontmostApplication:
        // As the translator double's own frontmost resolution: observable, and as slow as it is told to be.
        translator.resolutionEnterHook?()
        if translator.frontmostApplicationDelay > 0 {
          Thread.sleep(forTimeInterval: translator.frontmostApplicationDelay)
        }
        lookup = translator.frontmostApplicationResult
      case .hitTest:
        let point = (parameters?[BridgeAXTranslatorRequestType.pointParameterKey] as? NSValue)?.pointValue ?? .zero
        let displayID = (parameters?[BridgeAXTranslatorRequestType.displayIDParameterKey] as? NSNumber)?.uint32Value ?? 0
        bookkeeping.withLock { translator.rawHitTests.append(AXPTranslatorDouble.HitTest(point: point, displayID: displayID)) }
        lookup = translator.objectAtPointResult
      case .application:
        lookup = (parameters?[BridgeAXTranslatorRequestType.pidParameterKey] as? NSNumber).map {
          AXPTranslationObjectDouble(pid: $0.int32Value, objectID: 0)
        }
      case .attribute, .multipleAttribute, nil:
        lookup = nil
      }
      if let requestType, requestType != .attribute, requestType != .multipleAttribute {
        bookkeeping.withLock { translator.rawLookups.append(requestType) }
        let response = AXPTranslatorResponse.empty() as? AXPTranslatorResponse
        // By key: the double is not the secure-coding object the property is typed as.
        response?.setValue(lookup, forKey: "resultData")
        respond(lookup == nil ? nil : response)
        return
      }
      guard requestType == .multipleAttribute,
        let translation = request.value(forKey: "translation") as? AXPTranslationObjectDouble,
        let element = element(named: translation),
        let response = AXPTranslatorResponse.empty() as? AXPTranslatorResponse
      else {
        respond(nil)
        return
      }
      let asked = Set(((request.value(forKey: "parameters") as? NSDictionary)?["attributes"] as? [NSNumber] ?? []).map(\.intValue))
      let answer = NSMutableDictionary()
      for (attribute, value) in element.translatorAnswer where asked.contains(attribute.rawValue) {
        answer[NSNumber(value: attribute.rawValue)] = value
      }
      response.resultData = answer
      respond(response)
    }
  }
}
