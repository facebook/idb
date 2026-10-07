/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBAXCore
import FBControlCore
import FBSimulatorBridgeProtocol

package typealias AXWire = BridgeAXWire

extension BridgeAXWire.Node {
  /// The attribute list a read must request to serialize `keys`, or nil when that is exactly the default
  /// list. The traits bitmask is decoded per node inside the application, so it is dropped from the list
  /// when `keys` does not report `traits`.
  ///
  /// Nil rather than "the default list" so the caller can omit the request field entirely, keeping a
  /// default read byte-identical to one from a host that predates the field.
  package static func fetchList(for keys: Set<AXKeys>) -> [String]? {
    var list = defaultFetchList
    if !keys.contains(.traits) {
      list.removeAll { $0 == xcTraits.rawValue }
    }
    if keys.contains(.interactable) || keys.contains(.occludedBy) {
      list += interactableAttributes.map(\.rawValue)
    }
    return list == defaultFetchList ? nil : list
  }

  /// The node a marker's searched key reads, for the keys a write can assert on — or nil when this
  /// wire carries no such attribute.
  ///
  /// Only three of the searchable keys name something the guest fetches, because the rest are host-side
  /// derivations the host-side platform element answers nil for over this wire in the first place.
  /// A marker on one of those still writes; it just goes unasserted.
  package init?(assertableSearchKey key: AXSearchableKey) {
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
