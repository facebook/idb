/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Testing

/// Tests the pure companion-routing decision: an explicit companion always wins,
/// and local discovery is offered only when the platform supports it.
@Suite
struct CompanionRouteTests {

  @Test
  func explicitCompanionRoutesToTCP() {
    #expect(planCompanionRoute(companion: "127.0.0.1:10882", localAllowed: true) == .tcp("127.0.0.1:10882"))
  }

  @Test
  func explicitCompanionWinsEvenWhenLocalIsUnavailable() {
    // The TCP path is the only one available off macOS, and it is still honored.
    #expect(planCompanionRoute(companion: "host:1", localAllowed: false) == .tcp("host:1"))
  }

  @Test
  func noCompanionDiscoversLocallyWhenAllowed() {
    #expect(planCompanionRoute(companion: nil, localAllowed: true) == .discoverLocal)
  }

  @Test
  func noCompanionIsUnavailableWhenLocalDisallowed() {
    // e.g. Linux: no local idb_companion, so only an explicit companion works.
    #expect(planCompanionRoute(companion: nil, localAllowed: false) == .localUnavailable)
  }
}
