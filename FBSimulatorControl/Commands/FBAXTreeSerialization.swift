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
    let childNodes = (node[FBAXWire.Node.children.rawValue] as? [[String: Any]]) ?? []
    let children = childNodes.map { buildPlatformElementTree(from: $0, pid: pid) }
    return FBRemoteAutomationPlatformElement(attributes: node, children: children, pid: pid)
  }

  /// The first serialized element whose `key` value contains `markerValue`, used by
  /// describe-by-marker. Substring, matching `FBAccessibilityElementQuery.marker` — the accessibility
  /// backend walks the live tree and matches the same way, so a marker resolves to the same element
  /// whichever backend serves the read.
  static func matchingElement(inElements elements: [FBJSONValue], markerValue: String, key: FBAXSearchableKey) -> FBJSONValue? {
    elements.first { element in
      guard case let .object(fields) = element, case let .string(value)? = fields[key.rawValue] else {
        return false
      }
      return value.contains(markerValue)
    }
  }

  /// The outcome of resolving a marker to a point to interact with. Separates a marker that matched an
  /// element with no usable on-screen frame (off-screen or still settling — nowhere to tap) from one
  /// that matched nothing: before, both collapsed to a `nil` centre and read as "not found".
  enum MarkerResolution: Equatable {
    /// No serialized element's `key` value contains the marker.
    case notFound
    /// A matching element exists, but none has a usable frame.
    case offScreen
    /// The marker matched an element with a usable frame; its centre point.
    case resolved(x: Double, y: Double)
  }

  /// Resolves `markerValue` to the centre of the first matching element that has a usable frame (the
  /// same substring match as `matchingElement`), reporting whether a match without a usable frame
  /// existed so a caller can tell an off-screen element apart from an absent one.
  static func resolveMarker(inElements elements: [FBJSONValue], markerValue: String, key: FBAXSearchableKey) -> MarkerResolution {
    func number(_ value: FBJSONValue?) -> Double? {
      switch value {
      case let .double(number): return number
      case let .int(number): return Double(number)
      default: return nil
      }
    }
    var matched = false
    for element in elements {
      guard case let .object(fields) = element,
        case let .string(value)? = fields[key.rawValue], value.contains(markerValue)
      else {
        continue
      }
      matched = true
      guard case let .object(frame)? = fields[FBAXKeys.frameDict.rawValue],
        let x = number(frame["x"]), let y = number(frame["y"]),
        let width = number(frame["width"]), let height = number(frame["height"])
      else {
        continue
      }
      return .resolved(x: x + width / 2, y: y + height / 2)
    }
    return matched ? .offScreen : .notFound
  }

  /// The centre of the first matching element with a usable frame, or `nil` when the marker matches
  /// nothing *or* every match is off-screen. A `resolveMarker` wrapper for the `wait` poll, which
  /// treats both nil cases alike (keep polling); tap/set-value call `resolveMarker` directly to tell an
  /// off-screen match from a genuine miss.
  static func frameCenter(inElements elements: [FBJSONValue], markerValue: String, key: FBAXSearchableKey) -> (x: Double, y: Double)? {
    guard case let .resolved(x, y) = resolveMarker(inElements: elements, markerValue: markerValue, key: key) else {
      return nil
    }
    return (x, y)
  }
}
