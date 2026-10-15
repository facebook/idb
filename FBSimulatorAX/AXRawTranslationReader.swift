/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency internal import AccessibilityPlatformTranslation
import AppKit
import FBSimulatorBridgeProtocol
import FBSimulatorControl
import Foundation

/// Reads translator elements with one multiple-attribute request each, sent straight over the read's
/// transport and decoded here, rather than through `AXPMacPlatformElement`.
///
/// The platform element answers the same request but adds requests of its own: whether the element is
/// remote, and its subrole and role when it falls back to computing a role description. Asking for those
/// attributes in the one request and applying the platform element's rules to the answer reads the same
/// values in a single round trip. Those rules, as AppKit applies them:
/// - the role is the translator's role numbering named as AppKit names it, and `AXGroup` for a remote element;
/// - the role description is the application's own when it gives a non-empty one; otherwise empty for a
///   generic element, and AppKit's description of the role and subrole for anything else.
///
/// Attributes the translator has no number for — title, required, hidden — are not fetched: the platform
/// element answers its batched request without them too.
struct AXRawTranslationReader {
  let transport: any AXTranslationTransport
  let clientType: AXClientType
  let timeout: TimeInterval
  let collector: AccessibilityProfilingCollector
  let token: String

  /// Reads `root` and, as deep as `plan` asks, its descendants. An element listed among its own
  /// descendants — an application can answer with a cycle — is not read again below itself. An element
  /// listed more than once elsewhere, as a scroll view lists its scroll bar, is read at each place, as the
  /// platform element reads it.
  func read(_ root: AXTranslationReference, plan: AXReadPlan) -> AXElementSnapshot {
    var ancestors = Set<Identity>()
    return read(root, plan: plan, ancestors: &ancestors)
  }

  private struct Identity: Hashable {
    let pid: pid_t
    let objectID: UInt64
  }

  private func read(_ translation: AXTranslationReference, plan: AXReadPlan, ancestors: inout Set<Identity>) -> AXElementSnapshot {
    let identity = Identity(pid: translation.pid, objectID: translation.objectID)
    ancestors.insert(identity)
    defer { ancestors.remove(identity) }
    translation.bridgeDelegateToken = token
    let readsChildren = plan.depth.descendant != nil
    let answer = self.answer(for: translation, asking: Self.attributes(for: plan, readingChildren: readsChildren))
    let decoded = Decoded(answer, plan: plan)

    var children: [AXElementSnapshot] = []
    if let depth = plan.depth.descendant {
      let childPlan = AXReadPlan(attributes: plan.attributes, depth: depth)
      for child in decoded.children where !ancestors.contains(Identity(pid: child.pid, objectID: child.objectID)) {
        children.append(read(child, plan: childPlan, ancestors: &ancestors))
      }
    }
    return AXElementSnapshot(
      frame: decoded.frame,
      pid: translation.pid,
      handle: .translation(translation),
      role: decoded.role,
      label: decoded.label,
      value: AccessibilityAttributeValue(decoded.value),
      stringValue: decoded.value as? String,
      identifier: decoded.identifier,
      title: nil,
      help: decoded.help,
      isEnabled: decoded.isEnabled,
      customActionNames: decoded.customActionNames,
      roleDescription: decoded.roleDescription,
      subrole: decoded.subrole,
      isRequired: plan.attributes.contains(.required) ? false : nil,
      traits: decoded.traits,
      isExpanded: decoded.isExpanded,
      placeholder: decoded.placeholder,
      isHidden: plan.attributes.contains(.hidden) ? false : nil,
      isFocused: decoded.isFocused,
      children: children
    )
  }

  /// The translator's answer for `attributes` of one element; nil when it could not read the element or
  /// did not answer in time, which reads as an element with no values.
  private func answer(for translation: AXTranslationReference, asking attributes: [BridgeAXTranslatorAttribute]) -> BridgeAXTranslatorAnswer? {
    let response = send(
      .multipleAttribute, translation: translation,
      parameters: [BridgeAXTranslatorRequestType.attributesParameterKey: attributes.map { NSNumber(value: $0.rawValue) }])
    return BridgeAXTranslatorAnswer(resultData: response?.resultData)
  }

  // MARK: - Roots

  /// The element a read starts from.
  enum Root {
    case frontmostApplication(displayID: UInt32)
    case application(pid: pid_t)
    /// `point` in the display's hosted coordinates: already unrotated.
    case point(CGPoint, displayID: UInt32)
  }

  /// The translation of `root`, in the one request the translator would send for it; nil when nothing is
  /// there or no answer came in time.
  func resolve(_ root: Root) -> AXTranslationReference? {
    let response: AXPTranslatorResponse? =
      switch root {
      case let .frontmostApplication(displayID):
        send(
          .frontmostApplication, translation: AXPTranslationObject(),
          parameters: [BridgeAXTranslatorRequestType.displayIDParameterKey: NSNumber(value: displayID)])
      case let .application(pid):
        send(.application, translation: nil, parameters: [BridgeAXTranslatorRequestType.pidParameterKey: NSNumber(value: pid)])
      case let .point(point, displayID):
        send(
          .hitTest, translation: AXPTranslationObject(),
          parameters: [
            BridgeAXTranslatorRequestType.pointParameterKey: NSValue(point: point),
            BridgeAXTranslatorRequestType.displayIDParameterKey: NSNumber(value: displayID),
          ])
      }
    return response?.resultData as? AXTranslationReference
  }

  private func send(
    _ type: BridgeAXTranslatorRequestType, translation: AXTranslationReference?, parameters: [String: Any]
  ) -> AXPTranslatorResponse? {
    guard let request = AXPTranslatorRequest.request(withTranslation: translation) as? AXPTranslatorRequest else {
      return nil
    }
    request.requestType = UInt64(type.rawValue)
    request.clientType = clientType.rawValue
    request.parameters = parameters
    let start = CFAbsoluteTimeGetCurrent()
    let response = transport.send(request, timeout: timeout)
    collector.recordRequest(type: request.requestType, duration: CFAbsoluteTimeGetCurrent() - start, answered: response != nil)
    return response
  }

  /// The translator attributes a plan needs, in one list. Role and role description take the attributes
  /// their rules read along with them.
  static func attributes(for plan: AXReadPlan, readingChildren: Bool) -> [BridgeAXTranslatorAttribute] {
    var attributes: [BridgeAXTranslatorAttribute] = [.frame]
    func add(_ more: BridgeAXTranslatorAttribute...) {
      for attribute in more where !attributes.contains(attribute) {
        attributes.append(attribute)
      }
    }
    for attribute in AXReadPlan.Attribute.allCases where plan.attributes.contains(attribute) {
      switch attribute {
      case .role: add(.role, .isRemoteElement)
      case .label: add(.label)
      case .value: add(.value)
      case .identifier: add(.identifier)
      case .help: add(.help)
      case .enabled: add(.isEnabled)
      case .roleDescription: add(.roleDescription, .role, .subrole, .isRemoteElement)
      case .subrole: add(.subrole)
      case .traits: add(.traits)
      case .expanded: add(.expanded)
      case .placeholder: add(.placeholderValue)
      case .focused: add(.isFocused)
      case .customActions: add(.customActions)
      case .title, .required, .hidden, .hittability, .explainedBy: break
      }
    }
    if readingChildren {
      add(.children)
    }
    return attributes
  }

  /// One element's planned values, converted from the translator's answer as AppKit converts them.
  struct Decoded {
    var frame: NSRect = .zero
    var children: [AXTranslationReference] = []
    var role: String?
    var label: String?
    var value: Any?
    var identifier: String?
    var help: String?
    var isEnabled: Bool?
    var roleDescription: String?
    var subrole: String?
    var traits: [String]?
    var isExpanded: Bool?
    var placeholder: String?
    var isFocused: Bool?
    var customActionNames: [String]?

    init(_ answer: BridgeAXTranslatorAnswer?, plan: AXReadPlan) {
      func planned(_ attribute: AXReadPlan.Attribute) -> Bool {
        plan.attributes.contains(attribute)
      }
      func flag(_ attribute: AXReadPlan.Attribute, _ translated: BridgeAXTranslatorAttribute) -> Bool? {
        guard planned(attribute) else { return nil }
        return (answer?[translated] as? NSNumber)?.boolValue ?? false
      }

      frame = (answer?[.frame] as? NSValue)?.rectValue ?? .zero
      children = ((answer?[.children] as? [Any]) ?? []).compactMap { $0 as? AXTranslationReference }
      let isRemote = (answer?[.isRemoteElement] as? NSNumber)?.boolValue ?? false
      let translatedRole = Self.role(answer?[.role], isRemote: isRemote)
      let translatedSubrole = (answer?[.subrole] as? NSNumber)
        .flatMap { BridgeAXTranslatorSubrole(rawValue: $0.intValue) }
        .map { "AX\($0.name)" }

      if planned(.role) { role = translatedRole }
      if planned(.label) { label = answer?[.label] as? String }
      if planned(.value) { value = answer?[.value] }
      if planned(.identifier) { identifier = answer?[.identifier] as? String }
      if planned(.help) { help = answer?[.help] as? String }
      isEnabled = flag(.enabled, .isEnabled)
      if planned(.roleDescription) {
        roleDescription = Self.roleDescription(
          answer?[.roleDescription] as? String, role: translatedRole, subrole: translatedSubrole)
      }
      if planned(.subrole) { subrole = translatedSubrole }
      if planned(.traits) { traits = (answer?[.traits] as? NSNumber).map { AXExtractTraits($0.uint64Value) } }
      isExpanded = flag(.expanded, .expanded)
      if planned(.placeholder) { placeholder = answer?[.placeholderValue] as? String }
      isFocused = flag(.focused, .isFocused)
      if planned(.customActions) {
        customActionNames = ((answer?[.customActions] as? [Any]) ?? []).compactMap {
          ($0 as? NSDictionary)?["AXPCustomActionName"] as? String
        }
      }
    }

    /// The role as AppKit names it. A remote element is a group: the platform element reports what it
    /// hosts as a group of the content another process draws.
    static func role(_ raw: Any?, isRemote: Bool) -> String? {
      guard let number = raw as? NSNumber, let role = BridgeAXTranslatorRole(rawValue: number.intValue) else {
        return nil
      }
      return isRemote ? NSAccessibility.Role.group.rawValue : "AX\(role.name)"
    }

    /// The application's own description when it gives a non-empty one; otherwise empty for a generic
    /// element and AppKit's description of the role and subrole for anything else. An empty string from
    /// the application counts as none.
    static func roleDescription(_ raw: String?, role: String?, subrole: String?) -> String? {
      if let raw, !raw.isEmpty {
        return raw
      }
      guard let role else {
        return raw
      }
      if role == "AX\(BridgeAXTranslatorRole.genericElement.name)" {
        return ""
      }
      return NSAccessibility.Role(rawValue: role).description(with: subrole.map(NSAccessibility.Subrole.init(rawValue:)))
    }
  }
}
