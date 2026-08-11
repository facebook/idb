/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Backend-neutral walk over an `XC_kAXXC*` attribute-dictionary tree, plus the marker matcher and
/// frame-centre geometry that run over the walk's result. Both XCUI-grade backends emit this node
/// shape — the `testmanagerd` remote-automation session and the `axbridge` guest reader — so the tree
/// walk, marker matching, and frame-centre geometry live here, in a type neither backend owns, rather
/// than on one backend that the other has to reach into. Per-node serialization is delegated to
/// `FBAXNodeSerializer`.
enum FBAXTreeWalk {

  /// Serializes an attribute-dictionary tree (as emitted by either XCUI-grade backend) into the
  /// schema, building an `FBAXPlatformElement` tree and running the shared recursive serializer. Each
  /// element is tagged with the owning app's real pid, discovered during the tree read.
  ///
  /// The result is unfiltered. `FBAccessibilityElementFilter.apply(to:)` narrows it afterwards, so a
  /// caller that wants the whole tree as well as the reported subset — a coverage calculation, say —
  /// can have both from one walk.
  static func describeAllElements(fromTree tree: [String: Any], keys: Set<FBAXKeys>, nestedFormat: Bool, pid: pid_t) -> [FBAccessibilityDocumentElement] {
    let root = buildPlatformElementTree(from: tree, pid: pid)
    return FBAXNodeSerializer.recursiveDescription(
      fromElement: root,
      token: "",
      nestedFormat: nestedFormat,
      keys: keys,
      collector: nil,
      seenPids: nil
    )
  }

  /// The bounds a whole-tree read's frames are relative to, taken from the root node's own frame — for
  /// an application read the root is the application element, which spans the screen. `nil` when the
  /// root reports no usable frame, so an unknown screen is reported as unknown rather than as zero.
  ///
  /// Reads the frame through the same element type the serializer uses, so this cannot disagree with
  /// the frames on the elements it describes.
  static func screenInfo(fromTree tree: [String: Any]) -> FBAccessibilityScreenInfo? {
    let root = FBRemoteAutomationPlatformElement(attributes: tree, children: [], pid: 0)
    let frame = root.axFrame()
    guard frame.width > 0, frame.height > 0 else {
      return nil
    }
    return FBAccessibilityScreenInfo(width: Double(frame.width), height: Double(frame.height))
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
  static func matchingElement(inElements elements: [FBAccessibilityDocumentElement], markerValue: String, key: FBAXSearchableKey) -> FBAccessibilityDocumentElement? {
    elements.first { element in
      guard let value = element.searchableValue(for: key) else {
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
  static func resolveMarker(inElements elements: [FBAccessibilityDocumentElement], markerValue: String, key: FBAXSearchableKey) -> MarkerResolution {
    var matched = false
    for element in elements {
      guard let value = element.searchableValue(for: key), value.contains(markerValue) else {
        continue
      }
      matched = true
      // A rectangle with no area is not somewhere a caller can be aimed at, and it is not rare: an
      // element whose frame never reached the wire is normalized to a zero rectangle on the way in, so it
      // arrives with all four components present and would otherwise resolve to the origin. Treated as no
      // usable frame, alongside a frame that is absent outright — the same thing said two ways.
      guard let frame = element.frame ?? nil,
        let x = frame.x, let y = frame.y, let width = frame.width, let height = frame.height,
        width > 0, height > 0
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
  static func frameCenter(inElements elements: [FBAccessibilityDocumentElement], markerValue: String, key: FBAXSearchableKey) -> (x: Double, y: Double)? {
    guard case let .resolved(x, y) = resolveMarker(inElements: elements, markerValue: markerValue, key: key) else {
      return nil
    }
    return (x, y)
  }
}
