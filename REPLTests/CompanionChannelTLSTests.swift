/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Testing

@Suite
struct CompanionChannelTLSTests {
  private let identity = CompanionTLSIdentity(combinedPEMPath: "/tmp/idb-repl-test.pem")

  @Test
  func domainSocketIsAlwaysPlaintext() {
    #expect(
      replClientTLSIdentity(
        for: .domainSocket(path: "/tmp/x.sock"),
        tls: .metaIdentity,
        provider: FakeCompanionTLSProvider(identity: identity)) == nil)
  }

  @Test
  func tcpWithDisabledTLSIsPlaintext() {
    #expect(
      replClientTLSIdentity(
        for: .tcp(host: "companion.example", port: 10882),
        tls: .disabled,
        provider: FakeCompanionTLSProvider(identity: identity)) == nil)
  }

  @Test
  func tcpWithoutProviderIsPlaintext() {
    #expect(
      replClientTLSIdentity(
        for: .tcp(host: "companion.example", port: 10882),
        tls: .metaIdentity,
        provider: nil) == nil)
  }

  @Test
  func tcpWithProviderReturningNoIdentityIsPlaintext() {
    #expect(
      replClientTLSIdentity(
        for: .tcp(host: "companion.example", port: 10882),
        tls: .metaIdentity,
        provider: FakeCompanionTLSProvider(identity: nil)) == nil)
  }

  @Test
  func tcpWithMetaIdentityPresentsProviderIdentity() {
    #expect(
      replClientTLSIdentity(
        for: .tcp(host: "companion.example", port: 10882),
        tls: .metaIdentity,
        provider: FakeCompanionTLSProvider(identity: identity)) == identity)
  }
}

/// A provider that returns a fixed identity (or none) for exercising the selection.
private struct FakeCompanionTLSProvider: CompanionTLSProvider {
  let identity: CompanionTLSIdentity?
  func clientIdentity() -> CompanionTLSIdentity? { identity }
  func serverIdentity() -> CompanionTLSIdentity? { identity }
}
