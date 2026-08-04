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
