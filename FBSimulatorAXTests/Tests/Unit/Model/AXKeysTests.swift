/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorAX
import Foundation
import Testing

/// `AXKeys` raw values are the JSON keys idb emits and the cli's `--key` names, so each spelling is pinned.
@Suite
struct AXKeysTests {
  @Test
  func axKeyWireValues() {
    let expected: [AXKeys: String] = [
      .label: "AXLabel",
      .frame: "AXFrame",
      .value: "AXValue",
      .uniqueID: "AXUniqueId",
      .type: "type",
      .title: "title",
      .frameDict: "frame",
      .help: "help",
      .enabled: "enabled",
      .customActions: "custom_actions",
      .role: "role",
      .roleDescription: "role_description",
      .subrole: "subrole",
      .contentRequired: "content_required",
      .pid: "pid",
      .traits: "traits",
      .expanded: "expanded",
      .placeholder: "placeholder",
      .hidden: "hidden",
      .focused: "focused",
      .isRemote: "is_remote",
      .interactable: "interactable",
      .occludedBy: "occluded_by",
    ]
    // Pinned over `allCases` rather than against a count, so a case added without a pinned wire value
    // fails here instead of silently going unchecked.
    #expect(Set(AXKeys.allCases) == Set(expected.keys), "every AXKeys case must have its wire value pinned")
    for (key, wireValue) in expected {
      #expect(key.rawValue == wireValue, "\(key) must serialize under its pinned wire key")
    }
  }

  // The default set is the schema emitted when no keys are requested; it must stay exactly these 16, so
  // that adding a key never changes the bytes of a read that did not ask for it.
  @Test
  func defaultKeySetMembership() {
    #expect(
      AXKeys.defaultSet == [
        .label, .frame, .value, .uniqueID, .type, .title, .frameDict, .help,
        .enabled, .customActions, .role, .roleDescription, .subrole,
        .contentRequired, .pid, .traits,
      ]
    )
    #expect(AXKeys.defaultSet.count == 16)
    // Every case that is not in the default set is opt-in, derived rather than listed, so a new key is
    // covered by this the moment it exists.
    let optIn = Set(AXKeys.allCases).subtracting(AXKeys.defaultSet)
    #expect(optIn == [.expanded, .placeholder, .hidden, .focused, .isRemote, .interactable, .occludedBy])
    #expect(AXKeys.defaultSet.isDisjoint(with: optIn), "the opt-in keys must stay out of the default set")
  }
}
