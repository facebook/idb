/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery

/// Selects the client TLS identity to present when connecting to a companion, or
/// nil when the connection should be plaintext.
///
/// TLS applies only to a TCP companion whose `tls` mode is `.metaIdentity` and for
/// which the registered `CompanionTLSProvider` supplies a client identity. A Unix
/// domain socket, `.disabled`, or a missing provider/identity is plaintext. This
/// mirrors the choice `CompanionClient` makes for the JSON-RPC transport (present
/// the identity; the peer is not verified), keeping the two transports consistent.
///
/// Kept as a pure function of its inputs — the provider is injected rather than
/// read from the `CompanionTLS.provider` global — so the selection is unit-testable
/// without touching process-wide state or the filesystem.
func replClientTLSIdentity(
  for address: CompanionAddress,
  tls: CompanionClientTLS,
  provider: CompanionTLSProvider?
) -> CompanionTLSIdentity? {
  guard case .tcp = address, tls == .metaIdentity else {
    return nil
  }
  return provider?.clientIdentity()
}
