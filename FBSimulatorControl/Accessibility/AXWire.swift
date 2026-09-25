/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import SimulatorFrameworkBridgeProtocol

typealias AXWire = BridgeAXWire

extension BridgeAXWire.Node {
  /// The attribute list a read must request to serialize `keys`, or nil when the default list already
  /// carries everything needed.
  ///
  /// Nil rather than "the default list" so the caller can omit the request field entirely, keeping a
  /// default read byte-identical to one from a host that predates the field.
  static func fetchList(for keys: Set<AXKeys>) -> [String]? {
    guard keys.contains(.interactable) || keys.contains(.occludedBy) else {
      return nil
    }
    return defaultFetchList + interactableAttributes.map(\.rawValue)
  }

  /// The node a marker's searched key reads, for the keys a write can assert on — or nil when this
  /// wire carries no such attribute.
  ///
  /// Only three of the searchable keys name something the guest fetches, because the rest are host-side
  /// derivations the host-side platform element answers nil for over this wire in the first place.
  /// A marker on one of those still writes; it just goes unasserted.
  init?(assertableSearchKey key: AXSearchableKey) {
    switch key {
    case .label:
      self = .label
    case .value:
      self = .value
    case .uniqueID:
      self = .identifier
    case .title, .role, .roleDescription, .subrole, .help, .placeholder:
      return nil
    }
  }
}
