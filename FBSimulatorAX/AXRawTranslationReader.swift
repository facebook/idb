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
/// Attributes the translator has no number for — title, required, hidden, custom actions — are not fetched:
/// the platform element answers its batched request without them too.
struct AXRawTranslationReader {
  let transport: any AXTranslationTransport
  let clientType: AXClientType
  let timeout: TimeInterval
  let collector: AccessibilityProfilingCollector
  let token: String
  /// The element actions on a snapshot go through, built locally from its translation.
  let handle: (AXTranslationReference) -> AXWritableElement?

  /// Reads `root` and, as deep as `plan` asks, its descendants. An element reached a second time — an
  /// application can list an element among its own descendants — is not read again.
  func read(_ root: AXTranslationReference, plan: AXReadPlan) -> AXElementSnapshot {
    var visited = Set<Identity>()
    return read(root, plan: plan, visited: &visited)
  }

  private struct Identity: Hashable {
    let pid: pid_t
    let objectID: UInt64
  }

  private func read(_ translation: AXTranslationReference, plan: AXReadPlan, visited: inout Set<Identity>) -> AXElementSnapshot {
    visited.insert(Identity(pid: translation.pid, objectID: translation.objectID))
    translation.bridgeDelegateToken = token
    let readsChildren = plan.depth.descendant != nil
    let answer = self.answer(for: translation, asking: Self.attributes(for: plan, readingChildren: readsChildren))
    let decoded = Decoded(answer, plan: plan)

    var children: [AXElementSnapshot] = []
    if let depth = plan.depth.descendant {
      let childPlan = AXReadPlan(attributes: plan.attributes, depth: depth)
      for child in decoded.children where !visited.contains(Identity(pid: child.pid, objectID: child.objectID)) {
        children.append(read(child, plan: childPlan, visited: &visited))
      }
    }
    return AXElementSnapshot(
      frame: decoded.frame,
      pid: translation.pid,
      handle: handle(translation),
      role: decoded.role,
      label: decoded.label,
      value: AccessibilityAttributeValue(decoded.value),
      stringValue: decoded.value as? String,
      identifier: decoded.identifier,
      title: nil,
      help: decoded.help,
      isEnabled: decoded.isEnabled,
      customActionNames: plan.attributes.contains(.customActions) ? [] : nil,
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
    guard let request = AXPTranslatorRequest.request(withTranslation: translation) as? AXPTranslatorRequest else {
      return nil
    }
    request.requestType = UInt64(BridgeAXTranslatorRequestType.multipleAttribute.rawValue)
    request.clientType = clientType.rawValue
    request.parameters = [
      BridgeAXTranslatorRequestType.attributesParameterKey: attributes.map { NSNumber(value: $0.rawValue) }
    ]
    let start = CFAbsoluteTimeGetCurrent()
    let response = transport.send(request, timeout: timeout)
    collector.addXPCCallDuration(CFAbsoluteTimeGetCurrent() - start)
    return BridgeAXTranslatorAnswer(resultData: response?.resultData)
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
      case .title, .required, .hidden, .customActions, .hittability, .explainedBy: break
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
