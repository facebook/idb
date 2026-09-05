/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Walks an axbridge `XC_kAXXC*` attribute-dictionary tree and provides marker matching and
/// frame-centre geometry. Per-node serialization is delegated to
/// `FBAXNodeSerializer`.
enum FBAXTreeWalk {

  /// Serializes an attribute-dictionary tree into the schema, tagging each element with `pid`. The
  /// result is unfiltered so a caller can keep both the whole walk and the reported subset.
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
    let root = FBAXBridgePlatformElement(attributes: tree, children: [], pid: 0)
    let frame = root.axFrame()
    guard frame.width > 0, frame.height > 0 else {
      return nil
    }
    return FBAccessibilityScreenInfo(width: Double(frame.width), height: Double(frame.height))
  }

  /// Recursively builds an `FBAXBridgePlatformElement` from a nested attribute-dictionary
  /// node, tagging every node with the owning application's pid.
  static func buildPlatformElementTree(from node: [String: Any], pid: pid_t) -> FBAXBridgePlatformElement {
    let childNodes = (node[FBAXWire.Node.children.rawValue] as? [[String: Any]]) ?? []
    let children = childNodes.map { buildPlatformElementTree(from: $0, pid: pid) }
    return FBAXBridgePlatformElement(attributes: node, children: children, pid: pid)
  }

  /// The first element whose `key` value contains `markerValue`, via `FBAccessibilityMatch` so a marker
  /// and `--match` agree on what "contains" means.
  static func matchingElement(
    inElements elements: [FBAccessibilityDocumentElement],
    markerValue: String,
    key: FBAXSearchableKey,
    ignoresCase: Bool = false
  ) -> FBAccessibilityDocumentElement? {
    // An empty marker is not a search — every value contains it — so it resolves to the first element
    // carrying the key at all. `FBAccessibilityMatch` refuses to represent that, so it is spelled out
    // rather than quietly becoming "no match".
    guard let match = FBAccessibilityMatch(value: markerValue, key: key, ignoresCase: ignoresCase) else {
      return elements.first { $0.searchableValue(for: key) != nil }
    }
    return elements.first { match.matches($0.searchableValue(for: key)) }
  }

  /// The outcome of resolving a marker to a point: a match with no usable frame is distinguished from no
  /// match.
  enum MarkerResolution: Equatable {
    /// No serialized element's `key` value contains the marker.
    case notFound
    /// A matching element exists, but none has a usable frame.
    case offScreen
    /// The marker matched an element with a usable frame; its centre point.
    case resolved(x: Double, y: Double)
  }

  /// Resolves `markerValue` to the centre of the first matching element that has a usable frame,
  /// reporting whether a match without a usable frame existed so a caller can tell an off-screen
  /// element apart from an absent one. Matches through the same `FBAccessibilityMatch` predicate as
  /// `matchingElement`, so the asserted element and the tapped point cannot disagree.
  static func resolveMarker(
    inElements elements: [FBAccessibilityDocumentElement],
    markerValue: String,
    key: FBAXSearchableKey,
    ignoresCase: Bool = false
  ) -> MarkerResolution {
    var matched = false
    let match = FBAccessibilityMatch(value: markerValue, key: key, ignoresCase: ignoresCase)
    for element in elements {
      if let match {
        guard let value = element.searchableValue(for: key), match.matches(value) else {
          continue
        }
      } else {
        // An empty marker matches the first element carrying the key, as `matchingElement` does.
        guard element.searchableValue(for: key) != nil else {
          continue
        }
      }
      matched = true
      // A zero-area frame counts as no frame: an element whose frame never reached the wire is normalized
      // to zero on the way in and would otherwise resolve to the origin.
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
  static func frameCenter(
    inElements elements: [FBAccessibilityDocumentElement],
    markerValue: String,
    key: FBAXSearchableKey,
    ignoresCase: Bool = false
  ) -> (x: Double, y: Double)? {
    guard case let .resolved(x, y) = resolveMarker(inElements: elements, markerValue: markerValue, key: key, ignoresCase: ignoresCase) else {
      return nil
    }
    return (x, y)
  }
}
