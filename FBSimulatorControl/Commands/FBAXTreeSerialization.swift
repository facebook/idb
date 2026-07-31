/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Backend-neutral serialization of an `XC_kAXXC*` attribute-dictionary tree into the shared
/// accessibility schema. Both XCUI-grade backends emit this node shape — the `testmanagerd`
/// remote-automation session and the `axbridge` guest reader — so the tree→element serialization,
/// marker matching, and frame-centre geometry live here, in a type neither backend owns, rather than
/// on one backend that the other has to reach into.
enum FBAXTreeSerialization {

  /// The bounds every whole-tree read is taken under, shared by both XCUI-grade backends so their
  /// output is comparable: a tree read over one backend truncates at the same point as the other.
  /// The guest reader is *told* these rather than keeping its own copy, so there is one authority for
  /// how much tree a read returns.
  static let maxReadDepth = 50
  static let maxReadNodes = 3000

  /// Appended to read-failure errors. An empty tree/element almost always means the target app's
  /// in-process accessibility server never started — that requires `ApplicationAccessibilityEnabled`
  /// (`com.apple.Accessibility`) to have been set *before* the app launched. The flag is consumed at
  /// launch (a live read clears it), so it is an unreliable proxy to gate on up front; the guidance is
  /// surfaced only when a read genuinely comes back empty rather than blocking the read path.
  static let accessibilityHint = "If reads consistently return nothing, the app's accessibility server is likely not running: set ApplicationAccessibilityEnabled (com.apple.Accessibility) before the app launches — e.g. `xcrun simctl spawn <UDID> defaults write com.apple.Accessibility ApplicationAccessibilityEnabled -bool true` — then relaunch the app."

  /// Serializes an attribute-dictionary tree (as emitted by either XCUI-grade backend) into the
  /// schema, building an `FBAXPlatformElement` tree and running the shared recursive serializer. Each
  /// element is tagged with the owning app's real pid, discovered during the tree read.
  static func describeAllElements(fromTree tree: [String: Any], keys: Set<FBAXKeys>, nestedFormat: Bool, pid: pid_t, filter: FBAccessibilityElementFilter = .all) -> [FBJSONValue] {
    let root = buildPlatformElementTree(from: tree, pid: pid)
    return FBSimulatorAccessibilitySerializer.recursiveDescription(
      fromElement: root,
      token: "",
      nestedFormat: nestedFormat,
      keys: keys,
      collector: nil,
      coverageGrid: nil,
      seenPids: nil,
      filter: filter
    )
  }

  /// Recursively builds an `FBRemoteAutomationPlatformElement` from a nested attribute-dictionary
  /// node, tagging every node with the owning application's pid.
  static func buildPlatformElementTree(from node: [String: Any], pid: pid_t) -> FBRemoteAutomationPlatformElement {
    let childNodes = (node[FBRemoteAutomationAXAttribute.children] as? [[String: Any]]) ?? []
    let children = childNodes.map { buildPlatformElementTree(from: $0, pid: pid) }
    return FBRemoteAutomationPlatformElement(attributes: node, children: children, pid: pid)
  }

  /// The first serialized element whose `key` value equals `markerValue`, used by describe-by-marker.
  static func matchingElement(inElements elements: [FBJSONValue], markerValue: String, key: FBAXSearchableKey) -> FBJSONValue? {
    elements.first { element in
      guard case let .object(fields) = element, case let .string(value)? = fields[key.rawValue] else {
        return false
      }
      return value == markerValue
    }
  }

  /// The centre of the frame of the first serialized element whose `key` value equals `markerValue`.
  /// Shared by the marker-driven operations (tap, wait, set-value).
  static func frameCenter(inElements elements: [FBJSONValue], markerValue: String, key: FBAXSearchableKey) -> (x: Double, y: Double)? {
    func number(_ value: FBJSONValue?) -> Double? {
      switch value {
      case let .double(number): return number
      case let .int(number): return Double(number)
      default: return nil
      }
    }
    for element in elements {
      guard case let .object(fields) = element,
        case let .string(value)? = fields[key.rawValue], value == markerValue,
        case let .object(frame)? = fields[FBAXKeys.frameDict.rawValue],
        let x = number(frame["x"]), let y = number(frame["y"]),
        let width = number(frame["width"]), let height = number(frame["height"])
      else {
        continue
      }
      return (x + width / 2, y + height / 2)
    }
    return nil
  }
}
