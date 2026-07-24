/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/// How a CLI should reach a companion, decided from the connection options and
/// whether the current platform supports discovering a local companion. Kept free
/// of I/O so the routing logic can be unit-tested directly (see `CompanionRouteTests`).
public enum CompanionRoute: Equatable {
  /// Connect directly to the companion at this `host:port` (still to be parsed),
  /// bypassing discovery. Corresponds to an explicit `--companion`.
  case tcp(String)
  /// Discover a running companion, or start one on demand.
  case discoverLocal
  /// Local discovery is unavailable on this platform, so only a TCP companion can
  /// be used.
  case localUnavailable
}

/// Whether local companion discovery is available on this platform. Local
/// discovery spawns and connects to a local `idb_companion`, which exists only on
/// macOS; on any other platform a companion must be reached over TCP. This is the
/// single place the platform distinction lives, so every CLI shares it.
#if os(macOS)
public let localCompanionDiscoverySupported = true
#else
public let localCompanionDiscoverySupported = false
#endif

/// Chooses how a CLI should reach a companion. An explicit `--companion host:port`
/// always wins; otherwise local discovery is used where it is available and
/// reported unavailable where it is not (e.g. Linux, which has no local
/// `idb_companion`). `localAllowed` defaults to the platform capability but can be
/// overridden in tests.
public func planCompanionRoute(
  companion: String?,
  localAllowed: Bool = localCompanionDiscoverySupported
) -> CompanionRoute {
  if let companion {
    return .tcp(companion)
  }
  return localAllowed ? .discoverLocal : .localUnavailable
}
