/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Keys for accessibility element dictionaries.
///
/// The raw values are the on-the-wire JSON keys (and the CLI `--key` names);
/// they are pinned by golden tests and must not change.
public enum FBAXKeys: String, Sendable, CaseIterable {
  case label = "AXLabel"
  case frame = "AXFrame"
  case value = "AXValue"
  case uniqueID = "AXUniqueId"
  case type = "type"
  case title = "title"
  case frameDict = "frame"
  case help = "help"
  case enabled = "enabled"
  case customActions = "custom_actions"
  case role = "role"
  case roleDescription = "role_description"
  case subrole = "subrole"
  case contentRequired = "content_required"
  case pid = "pid"
  case traits = "traits"
  case expanded = "expanded"
  case placeholder = "placeholder"
  case hidden = "hidden"
  case focused = "focused"
  case isRemote = "is_remote"
  /// Whether the element can be acted on, and why not when it cannot.
  ///
  /// Not in `defaultSet`: `isVisible` and `visiblePoint` cannot be looked up — the application
  /// hit-tests the element to answer them — so requesting them for a whole tree hit-tests every node.
  ///
  /// Only the guest lanes are affected. `axIsHittable()` returns nil on the translator lane, which has no
  /// equivalent attributes, so the verdict is null there and nothing extra is fetched.
  case interactable = "interactable"
  /// Names the element covering an occluded element's centre, under `interactable`'s `occluded` reason.
  /// The only key that costs extra round trips — one hit-test per occluded element — so it is separate
  /// from `interactable` rather than folded into it, and implies it.
  case occludedBy = "occluded_by"

  /// What `occluded_by` needs serialized to do its work.
  ///
  /// The hit-test aims at the frame's centre, then compares serialized fields on both sides to
  /// recognise whether the answering element is a relative of the target or a stranger. A field absent
  /// on either side never matches, so these must be requested together.
  public static let occluderIdentityKeys: Set<FBAXKeys> = [.interactable, .frameDict, .type, .uniqueID, .label]

  /// Every key this reader can answer. Derived from `allCases`, so a key added to the enum joins
  /// automatically.
  ///
  /// Includes `interactable` and `occludedBy`, which are costly — see those keys.
  public static let everything: Set<FBAXKeys> = Set(allCases)

  /// The token a caller passes instead of naming every key: `--key all`. Not a case of the enum: it
  /// names no field, and a node never carries it.
  public static let everythingToken = "all"

  /// Every value `--key` accepts: the token, then the keys themselves.
  public static var allArgumentStrings: [String] { [everythingToken] + allCases.map(\.rawValue) }

  /// Whether a `--key` value is one this vocabulary accepts, token included.
  public static func acceptsArgument(_ raw: String) -> Bool {
    raw == everythingToken || FBAXKeys(rawValue: raw) != nil
  }

  /// The keys a caller asked for, expanding `all` and dropping anything unrecognised. `all` wins over
  /// any keys listed alongside it.
  public static func requested(_ raw: [String]) -> Set<FBAXKeys> {
    raw.contains(everythingToken) ? everything : Set(raw.compactMap(FBAXKeys.init(rawValue:)))
  }

  /// Default set of keys returned when no specific keys are requested.
  public static let defaultSet: Set<FBAXKeys> = [
    .label, .frame, .value, .uniqueID, .type, .title, .frameDict, .help,
    .enabled, .customActions, .role, .roleDescription, .subrole,
    .contentRequired, .pid, .traits,
  ]
}

/// Subset of `FBAXKeys` whose values are strings, suitable for element search matching.
public enum FBAXSearchableKey: String, Sendable {
  case label = "AXLabel"
  case uniqueID = "AXUniqueId"
  case value = "AXValue"
  case title = "title"
  case role = "role"
  case roleDescription = "role_description"
  case subrole = "subrole"
  case help = "help"
  case placeholder = "placeholder"

  /// The `FBAXKeys` whose serialized field a marker match reads. A marker is matched over the
  /// *serialized* element, so the searched key must be among the keys a tree is serialized with;
  /// unioning this into the read key set makes a marker resolve the same way regardless of the
  /// requested key set — notably `.placeholder`, which `FBAXKeys.defaultSet` omits.
  public var serializationKey: FBAXKeys {
    switch self {
    case .label: return .label
    case .uniqueID: return .uniqueID
    case .value: return .value
    case .title: return .title
    case .role: return .role
    case .roleDescription: return .roleDescription
    case .subrole: return .subrole
    case .help: return .help
    case .placeholder: return .placeholder
    }
  }
}

/// The direction of an accessibility scroll action.
public enum FBAccessibilityScrollDirection: Sendable {
  case up
  case down
  case left
  case right
  case visible
}
