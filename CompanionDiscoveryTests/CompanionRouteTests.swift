/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Testing

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
  func noCompanionSelectsRemoteWhenLocalDisallowed() {
    #expect(planCompanionRoute(companion: nil, localAllowed: false) == .selectRemote)
  }

  @Test
  func environmentCompanionWinsOverRegistry() throws {
    let address = try selectRemoteCompanion(
      environmentCompanion: "environment.example:1234",
      companions: [tcpCompanion(udid: "registry", host: "registry.example", port: 5678)],
      udid: "registry")

    #expect(address == .tcp(host: "environment.example", port: 1234))
  }

  @Test
  func invalidEnvironmentCompanionIsNotIgnored() {
    #expect(throws: RemoteCompanionSelectionError.invalidEnvironmentCompanion("not-an-address")) {
      try selectRemoteCompanion(
        environmentCompanion: "not-an-address",
        companions: [tcpCompanion(udid: "target", host: "registry.example", port: 5678)],
        udid: "target")
    }
  }

  @Test
  func emptyEnvironmentCompanionIsNotIgnored() {
    #expect(throws: RemoteCompanionSelectionError.invalidEnvironmentCompanion("")) {
      try selectRemoteCompanion(
        environmentCompanion: "",
        companions: [tcpCompanion(udid: "target", host: "registry.example", port: 5678)],
        udid: "target")
    }
  }

  @Test
  func udidSelectsMatchingTCPCompanion() throws {
    let address = try selectRemoteCompanion(
      environmentCompanion: nil,
      companions: [
        tcpCompanion(udid: "other", host: "other.example", port: 1234),
        tcpCompanion(udid: "target", host: "target.example", port: 5678),
      ],
      udid: "target")

    #expect(address == .tcp(host: "target.example", port: 5678))
  }

  @Test
  func udidNeverSelectsDifferentCompanion() {
    #expect(throws: RemoteCompanionSelectionError.noCompanions(udid: "missing")) {
      try selectRemoteCompanion(
        environmentCompanion: nil,
        companions: [tcpCompanion(udid: "other", host: "other.example", port: 1234)],
        udid: "missing")
    }
  }

  @Test
  func soleTCPCompanionIsSelectedWithoutUDID() throws {
    let address = try selectRemoteCompanion(
      environmentCompanion: nil,
      companions: [
        CompanionInfo(udid: "local", isLocal: true, pid: 1, address: .domainSocket(path: "/tmp/local.sock")),
        tcpCompanion(udid: "remote", host: "remote.example", port: 1234),
      ],
      udid: nil)

    #expect(address == .tcp(host: "remote.example", port: 1234))
  }

  @Test
  func multipleTCPCompanionsRequireSelection() {
    let first = tcpCompanion(udid: "first", host: "first.example", port: 1234)
    let second = tcpCompanion(udid: "second", host: "second.example", port: 5678)

    #expect(
      throws: RemoteCompanionSelectionError.ambiguousCompanions(
        udid: nil,
        candidates: [first, second])
    ) {
      try selectRemoteCompanion(
        environmentCompanion: nil,
        companions: [second, first],
        udid: nil)
    }
  }

  @Test
  func domainSocketsAreUnavailableRemotely() {
    #expect(throws: RemoteCompanionSelectionError.noCompanions(udid: nil)) {
      try selectRemoteCompanion(
        environmentCompanion: nil,
        companions: [
          CompanionInfo(udid: "local", isLocal: true, pid: 1, address: .domainSocket(path: "/tmp/local.sock"))
        ],
        udid: nil)
    }
  }

  @Test
  func noCompanionErrorNamesEverySetupOption() {
    let description = RemoteCompanionSelectionError.noCompanions(udid: nil).description

    #expect(description.contains("--companion"))
    #expect(description.contains("IDB_COMPANION"))
    #expect(description.contains("/tmp/idb/state"))
    #expect(description.contains("idb connect"))
  }

  private func tcpCompanion(udid: String, host: String, port: Int) -> CompanionInfo {
    CompanionInfo(udid: udid, isLocal: false, pid: nil, address: .tcp(host: host, port: port))
  }
}
