/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import AppKit
import FBControlCore
import Foundation

/// Reference-typed accumulator for the process ids seen during a serialization
/// traversal. Shared with the remote-content phase so processes already present
/// in the main tree are skipped during grid hit-testing.
final class SeenPIDs {
  private var pids: Set<pid_t> = []
  func insert(_ pid: pid_t) { pids.insert(pid) }
  func contains(_ pid: pid_t) -> Bool { pids.contains(pid) }
}

/// Serializes an `AXPMacPlatformElement` tree into the typed JSON emitted by the
/// accessibility commands. The values mirror the old SimulatorBridge implementation
/// for downstream compatibility.
///
/// Driven entirely from Swift (`FBAXTranslationRequest` and its remote-content
/// code), so it is a plain Swift namespace returning `FBJSONValue`. Each attribute
/// is turned into its `FBJSONValue` case at the read site, where its Swift type is
/// statically known, so no scalar is round-tripped through an untyped `NSNumber`.
/// `axValue()` is the one exception — it is genuinely `Any` — and is the only value
/// classified via `FBJSONValue(foundation:)`.
enum FBSimulatorAccessibilitySerializer {

  private static let axPrefix = "AX"
  private static let discoveryMethodRecursive = "recursive"
  private static let discoveryMethodPointGrid = "point_grid"

  // MARK: - Entry points

  static func recursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    filter: FBAccessibilityElementFilter = .all
  ) -> [FBJSONValue] {
    element.axSetBridgeDelegateToken(token)
    let dictionaries: [[String: FBJSONValue]]
    if nestedFormat {
      dictionaries = nestedRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, filter: filter)
    } else {
      dictionaries = flatRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, filter: filter)
    }
    return dictionaries.map { .object($0) }
  }

  static func formattedDescription(
    ofElement element: FBAXPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?
  ) -> FBJSONValue {
    element.axSetBridgeDelegateToken(token)
    if nestedFormat {
      // A single element (describe-point) is always the target — never filtered.
      return .object(nestedRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: nil, filter: .all).first ?? [:])
    }
    return .object(accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: nil, discoveryMethod: discoveryMethodRecursive))
  }

  // The values here mirror the old SimulatorBridge implementation for downstream
  // compatibility.
  static func accessibilityDictionary(
    forElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    discoveryMethod: String
  ) -> [String: FBJSONValue] {
    // The token must always be set so that the right callback is called.
    element.axSetBridgeDelegateToken(token)

    let elementPid = element.axTranslationPid
    seenPids?.insert(elementPid)

    collector?.incrementElementCount()

    var values: [String: FBJSONValue] = [:]

    func string(_ value: String?) -> FBJSONValue {
      value.map(FBJSONValue.string) ?? .null
    }

    // Includes a key only when requested, incrementing the profiling counter and
    // reading the value lazily so attribute access is tracked exactly as the ObjC
    // macro did.
    func include(_ key: FBAXKeys, _ value: @autoclosure () -> FBJSONValue) {
      guard keys.contains(key) else {
        return
      }
      collector?.incrementAttributeFetchCount(forKey: key.rawValue)
      values[key.rawValue] = value()
    }

    // Frame is always computed since it is used by multiple keys and the coverage grid.
    collector?.incrementAttributeFetchCount(forKey: FBAXKeys.frame.rawValue)
    let frame = element.axFrame()

    // Role is used by multiple keys and needs processing. Check Role first to
    // assign rawRole, then Type can derive from it.
    var role: String?
    var rawRole: String?
    if keys.contains(.role) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.role.rawValue)
      rawRole = element.axRole()
      values[FBAXKeys.role.rawValue] = string(rawRole)
    }
    if keys.contains(.type) {
      if rawRole == nil {
        collector?.incrementAttributeFetchCount(forKey: FBAXKeys.type.rawValue)
        rawRole = element.axRole()
      }
      // accessibilityRole may be prefixed with "AX"; strip it to match the
      // SimulatorBridge implementation.
      if let rawRole, rawRole.hasPrefix(axPrefix) {
        role = String(rawRole.dropFirst(2))
      } else {
        role = rawRole
      }
    }

    // Mark frame in coverage grid (for non-Application elements).
    if let coverageGrid {
      if rawRole == nil {
        collector?.incrementAttributeFetchCount(forKey: nil)
        rawRole = element.axRole()
      }
      let isApplication = rawRole == "AXApplication" || rawRole == "Application"
      if !isApplication {
        coverageGrid.markFilled(with: frame)
      }
    }

    // Legacy values that mirror SimulatorBridge.
    include(.label, string(element.axLabel()))
    if keys.contains(.frame) {
      values[FBAXKeys.frame.rawValue] = .string(NSStringFromRect(frame))
    }
    include(.value, FBJSONValue(foundation: element.axValue()))
    include(.uniqueID, string(element.axIdentifier()))

    // Synthetic values.
    if keys.contains(.type) {
      values[FBAXKeys.type.rawValue] = string(role)
    }

    // New values.
    include(.title, string(element.axTitle()))
    if keys.contains(.frameDict) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.frameDict.rawValue)
      values[FBAXKeys.frameDict.rawValue] = .object([
        "x": .double(Double(frame.origin.x)),
        "y": .double(Double(frame.origin.y)),
        "width": .double(Double(frame.size.width)),
        "height": .double(Double(frame.size.height)),
      ])
    }
    include(.help, string(element.axHelp()))
    include(.enabled, .bool(element.axIsEnabled()))
    include(.customActions, .array(element.axCustomActionNames().map(FBJSONValue.string)))
    include(.roleDescription, string(element.axRoleDescription()))
    include(.subrole, string(element.axSubrole()))
    include(.contentRequired, .bool(element.axIsRequired()))
    include(.pid, .int(Int64(element.axTranslationPid)))
    if keys.contains(.traits) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.traits.rawValue)
      values[FBAXKeys.traits.rawValue] = element.axTraits().map { .array($0.map(FBJSONValue.string)) } ?? .null
    }
    include(.expanded, .bool(element.axIsExpanded()))
    include(.placeholder, string(element.axPlaceholderValue()))
    include(.hidden, .bool(element.axIsHidden()))
    include(.focused, .bool(element.axIsFocused()))
    include(.isRemote, .string(discoveryMethod))

    return values
  }

  // MARK: - Recursion

  // Non-hierarchical (flat) output: frames are relative to the root, as in SimulatorBridge.
  private static func flatRecursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    filter: FBAccessibilityElementFilter
  ) -> [[String: FBJSONValue]] {
    var values: [[String: FBJSONValue]] = []
    if passes(element, filter: filter) {
      values.append(accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, discoveryMethod: discoveryMethodRecursive))
    }
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      values.append(contentsOf: flatRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, filter: filter))
    }
    return values
  }

  // Returns the element as a single nested node, or — when it is filtered out — its kept descendants
  // hoisted, for the caller to splice into the nearest kept ancestor.
  private static func nestedRecursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    filter: FBAccessibilityElementFilter
  ) -> [[String: FBJSONValue]] {
    var childrenValues: [[String: FBJSONValue]] = []
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      childrenValues.append(contentsOf: nestedRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, filter: filter))
    }
    guard passes(element, filter: filter) else {
      return childrenValues
    }
    var values = accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, discoveryMethod: discoveryMethodRecursive)
    values["children"] = .array(childrenValues.map { .object($0) })
    return [values]
  }

  // MARK: - Filter

  /// Actionable `XCUIElementType`/role names (the "AX" prefix stripped) kept by `.interactable`.
  private static let interactableRoles: Set<String> = [
    "Button", "Cell", "TextField", "SecureTextField", "SearchField", "Switch", "Toggle", "Link",
    "MenuItem", "Slider", "CheckBox", "RadioButton", "SegmentedControl", "Stepper", "PopUpButton",
    "Picker", "PickerWheel", "Tab", "Key", "DisclosureTriangle",
  ]

  /// Whether an element is kept under `filter`. `.interactable` keeps elements carrying a label, an
  /// identifier, or an actionable role — dropping unlabeled structural containers.
  private static func passes(_ element: FBAXPlatformElement, filter: FBAccessibilityElementFilter) -> Bool {
    switch filter {
    case .all:
      return true
    case .interactable:
      if let label = element.axLabel(), !label.isEmpty { return true }
      if let identifier = element.axIdentifier(), !identifier.isEmpty { return true }
      if let role = element.axRole() {
        let normalized = role.hasPrefix(axPrefix) ? String(role.dropFirst(axPrefix.count)) : role
        if interactableRoles.contains(normalized) { return true }
      }
      return false
    }
  }
}
