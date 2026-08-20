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
  /// Not in `defaultSet`, and it should stay out. `isVisible` and `visiblePoint` cannot be looked up: the
  /// application hit-tests the element to answer them, so requesting them for a whole tree makes it
  /// hit-test every node. The cost is per node and much larger than the extra bytes suggest.
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
  /// It hit-tests an element's centre and then has to recognise whether the element that answered is a
  /// relative of the target or a stranger. Both halves need fields: the centre comes from the frame, and
  /// the recognition compares what the two reads can both see. A field present on one side and absent on
  /// the other never matches, so a relative reads as a stranger and a label inside its own button gets
  /// reported as *covered by* something — a confident, wrong answer. Requesting them together is what
  /// keeps the comparison symmetric.
  public static let occluderIdentityKeys: Set<FBAXKeys> = [.interactable, .frameDict, .type, .uniqueID, .label]

  /// Every key this reader can answer.
  ///
  /// Derived from `allCases` rather than listed, so a key added to the enum joins it automatically. A
  /// hand-written set would drift the moment someone added one, and drift silently — the caller asking
  /// for everything is the least likely to notice a missing field.
  ///
  /// **Costs more than the default set, and not only in bytes.** It includes `interactable` and
  /// `occludedBy`, which widen the attributes the guest fetches per element, and `occludedBy` makes the
  /// guest hit-test the centre of every element it judges unreachable. On a large tree that is a real
  /// per-element cost, so this is for a caller that wants a complete dump and has accepted paying for it
  /// — not a better default.
  public static let everything: Set<FBAXKeys> = Set(allCases)

  /// The token a caller passes instead of naming every key: `--key all`.
  ///
  /// Reserved rather than a case of the enum, because it is not a key — it does not name a field, and a
  /// node never carries it. Kept here so the spelling lives beside the vocabulary it expands to.
  public static let everythingToken = "all"

  /// Every value `--key` accepts: the token, then the keys themselves.
  ///
  /// Derived here rather than assembled at the command line, so a front end cannot list a set that has
  /// drifted from the one `requested(_:)` actually parses.
  public static var allArgumentStrings: [String] { [everythingToken] + allCases.map(\.rawValue) }

  /// Whether a `--key` value is one this vocabulary accepts, token included.
  public static func acceptsArgument(_ raw: String) -> Bool {
    raw == everythingToken || FBAXKeys(rawValue: raw) != nil
  }

  /// The keys a caller asked for, expanding `all` and dropping anything unrecognised.
  ///
  /// `all` wins over anything alongside it: a caller who asked for everything and one specific key wants
  /// everything, and intersecting the two would answer with less than either request on its own.
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
