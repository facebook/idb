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

/// Serializes a runtime platform-element tree into the JSON-ready dictionaries
/// emitted by the accessibility commands. The values mirror the old
/// SimulatorBridge implementation for downstream compatibility.
///
/// Driven entirely from Swift (`FBAXTranslationRequest` and its remote-content
/// code), so it is a plain Swift namespace returning Swift collections.
enum FBSimulatorAccessibilitySerializer {

  private static let axPrefix = "AX"
  private static let discoveryMethodRecursive = "recursive"
  private static let discoveryMethodPointGrid = "point_grid"

  // MARK: - Helpers

  private static func ensureJSONSerializable(_ object: Any?) -> Any {
    guard let object else {
      return NSNull()
    }
    if JSONSerialization.isValidJSONObject([object]) {
      return object
    }
    return String(describing: object)
  }

  // MARK: - Entry points

  static func recursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    maxDepth: UInt = 0
  ) -> [[String: Any]] {
    element.axSetBridgeDelegateToken(token)
    if nestedFormat {
      return [nestedRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, depth: 0, maxDepth: maxDepth)]
    }
    return flatRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, depth: 0, maxDepth: maxDepth)
  }

  static func formattedDescription(
    ofElement element: FBAXPlatformElement,
    token: String,
    nestedFormat: Bool,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    maxDepth: UInt = 0
  ) -> [String: Any] {
    element.axSetBridgeDelegateToken(token)
    if nestedFormat {
      return nestedRecursiveDescription(fromElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: nil, depth: 0, maxDepth: maxDepth)
    }
    return accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: nil, discoveryMethod: discoveryMethodRecursive)
  }

  /// RocketSim addition: whether recursion may descend past `depth` into child elements.
  /// A `maxDepth` of 0 is unlimited; 1 serializes only the root element.
  private static func mayDescend(from depth: UInt, maxDepth: UInt) -> Bool {
    maxDepth == 0 || depth + 1 < maxDepth
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
  ) -> [String: Any] {
    // The token must always be set so that the right callback is called.
    element.axSetBridgeDelegateToken(token)

    let elementPid = element.axTranslationPid
    seenPids?.insert(elementPid)

    collector?.incrementElementCount()

    var values: [String: Any] = [:]

    // Includes a key (with JSON serialization) only when requested, incrementing
    // the profiling counter and reading the value lazily so attribute access is
    // tracked exactly as the ObjC macro did.
    func include(_ key: FBAXKeys, _ value: @autoclosure () -> Any?) {
      guard keys.contains(key) else {
        return
      }
      collector?.incrementAttributeFetchCount(forKey: key.rawValue)
      values[key.rawValue] = ensureJSONSerializable(value())
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
      values[FBAXKeys.role.rawValue] = ensureJSONSerializable(rawRole)
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
    include(.label, element.axLabel())
    if keys.contains(.frame) {
      values[FBAXKeys.frame.rawValue] = NSStringFromRect(frame)
    }
    include(.value, element.axValue())
    include(.uniqueID, element.axIdentifier())

    // Synthetic values.
    if keys.contains(.type) {
      values[FBAXKeys.type.rawValue] = ensureJSONSerializable(role)
    }

    // New values.
    include(.title, element.axTitle())
    if keys.contains(.frameDict) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.frameDict.rawValue)
      values[FBAXKeys.frameDict.rawValue] = [
        "x": frame.origin.x,
        "y": frame.origin.y,
        "width": frame.size.width,
        "height": frame.size.height,
      ]
    }
    include(.help, element.axHelp())
    include(.enabled, element.axIsEnabled())
    include(.customActions, element.axCustomActionNames())
    include(.roleDescription, element.axRoleDescription())
    include(.subrole, element.axSubrole())
    include(.contentRequired, element.axIsRequired())
    include(.pid, element.axTranslationPid)
    if keys.contains(.traits) {
      collector?.incrementAttributeFetchCount(forKey: FBAXKeys.traits.rawValue)
      values[FBAXKeys.traits.rawValue] = element.axTraits() ?? NSNull()
    }
    include(.expanded, element.axIsExpanded())
    include(.placeholder, element.axPlaceholderValue())
    include(.hidden, element.axIsHidden())
    include(.focused, element.axIsFocused())
    include(.isRemote, discoveryMethod)

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
    depth: UInt = 0,
    maxDepth: UInt = 0
  ) -> [[String: Any]] {
    var values: [[String: Any]] = []
    values.append(accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, discoveryMethod: discoveryMethodRecursive))
    guard mayDescend(from: depth, maxDepth: maxDepth) else {
      return values
    }
    for child in element.axChildren() {
      child.axSetBridgeDelegateToken(token)
      values.append(contentsOf: flatRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, depth: depth + 1, maxDepth: maxDepth))
    }
    return values
  }

  private static func nestedRecursiveDescription(
    fromElement element: FBAXPlatformElement,
    token: String,
    keys: Set<FBAXKeys>,
    collector: FBAccessibilityProfilingCollector?,
    coverageGrid: FBAccessibilityCoverageGrid?,
    seenPids: SeenPIDs?,
    depth: UInt = 0,
    maxDepth: UInt = 0
  ) -> [String: Any] {
    var values = accessibilityDictionary(forElement: element, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, discoveryMethod: discoveryMethodRecursive)
    var childrenValues: [[String: Any]] = []
    if mayDescend(from: depth, maxDepth: maxDepth) {
      for child in element.axChildren() {
        child.axSetBridgeDelegateToken(token)
        childrenValues.append(nestedRecursiveDescription(fromElement: child, token: token, keys: keys, collector: collector, coverageGrid: coverageGrid, seenPids: seenPids, depth: depth + 1, maxDepth: maxDepth))
      }
    }
    values["children"] = childrenValues
    return values
  }
}
