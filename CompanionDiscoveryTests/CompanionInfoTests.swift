/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Foundation
import Testing

/// Verifies `CompanionInfo` JSON encoding/decoding.
@Suite
struct CompanionInfoTests {
  @Test
  func encodesDomainSocketWithExpectedKeys() throws {
    let info = CompanionInfo(udid: "ABC", isLocal: true, pid: 42, address: .domainSocket(path: "/tmp/x.sock"))
    let object = try jsonObject(encoding: info)
    #expect(object["udid"] as? String == "ABC")
    #expect(object["is_local"] as? Bool == true)
    #expect(object["pid"] as? Int == 42)
    #expect(object["path"] as? String == "/tmp/x.sock")
    #expect(object["host"] == nil)
    #expect(object["port"] == nil)
  }

  @Test
  func encodesTCPWithExpectedKeys() throws {
    let info = CompanionInfo(udid: "ABC", isLocal: false, pid: 7, address: .tcp(host: "localhost", port: 10882))
    let object = try jsonObject(encoding: info)
    #expect(object["host"] as? String == "localhost")
    #expect(object["port"] as? Int == 10882)
    #expect(object["is_local"] as? Bool == false)
    #expect(object["path"] == nil)
  }

  @Test
  func encodesNilPidAsExplicitNull() throws {
    // json_data_companions always emits "pid" (null when unknown).
    let info = CompanionInfo(udid: "ABC", isLocal: true, pid: nil, address: .domainSocket(path: "/tmp/x.sock"))
    let object = try jsonObject(encoding: info)
    #expect(object.keys.contains("pid"))
    #expect(object["pid"] is NSNull)
  }

  @Test
  func decodesPythonDomainSocketRecord() throws {
    let json = #"{"udid": "U1", "is_local": true, "pid": 99, "path": "/tmp/u1.sock"}"#
    let info = try JSONDecoder().decode(CompanionInfo.self, from: Data(json.utf8))
    #expect(info.udid == "U1")
    #expect(info.isLocal == true)
    #expect(info.pid == 99)
    #expect(info.address == .domainSocket(path: "/tmp/u1.sock"))
  }

  @Test
  func decodesPythonTCPRecord() throws {
    let json = #"{"udid": "U2", "is_local": false, "pid": 5, "host": "1.2.3.4", "port": 1234}"#
    let info = try JSONDecoder().decode(CompanionInfo.self, from: Data(json.utf8))
    #expect(info.address == .tcp(host: "1.2.3.4", port: 1234))
    #expect(info.isLocal == false)
  }

  @Test
  func decodesNullPid() throws {
    let json = #"{"udid": "U3", "is_local": true, "pid": null, "path": "/tmp/u3.sock"}"#
    let info = try JSONDecoder().decode(CompanionInfo.self, from: Data(json.utf8))
    #expect(info.pid == nil)
  }

  @Test
  func decodesMissingPid() throws {
    let json = #"{"udid": "U4", "is_local": true, "path": "/tmp/u4.sock"}"#
    let info = try JSONDecoder().decode(CompanionInfo.self, from: Data(json.utf8))
    #expect(info.pid == nil)
  }

  @Test
  func roundTripsArrayOfMixedAddresses() throws {
    let infos = [
      CompanionInfo(udid: "a", isLocal: true, pid: 1, address: .domainSocket(path: "/tmp/a.sock")),
      CompanionInfo(udid: "b", isLocal: false, pid: nil, address: .tcp(host: "h", port: 2)),
    ]
    let data = try JSONEncoder().encode(infos)
    let decoded = try JSONDecoder().decode([CompanionInfo].self, from: data)
    #expect(decoded == infos)
  }

  // MARK: - Helpers

  private func jsonObject(encoding info: CompanionInfo) throws -> [String: Any] {
    let data = try JSONEncoder().encode(info)
    let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return try #require(parsed)
  }
}

/// Verifies `CompanionAddress.parse(tcp:)` host:port parsing.
@Suite
struct CompanionAddressParseTests {
  @Test
  func parsesIPv4AndPort() {
    #expect(CompanionAddress.parse(tcp: "127.0.0.1:10882") == .tcp(host: "127.0.0.1", port: 10882))
  }

  @Test
  func parsesHostnameAndPort() {
    #expect(CompanionAddress.parse(tcp: "companion.example:443") == .tcp(host: "companion.example", port: 443))
  }

  @Test
  func parsesBracketedIPv6() {
    // The last colon separates the port, so a bracketed IPv6 literal is preserved.
    #expect(CompanionAddress.parse(tcp: "[::1]:10882") == .tcp(host: "::1", port: 10882))
  }

  @Test
  func rejectsMissingPort() {
    #expect(CompanionAddress.parse(tcp: "127.0.0.1") == nil)
  }

  @Test
  func rejectsNonNumericPort() {
    #expect(CompanionAddress.parse(tcp: "host:abc") == nil)
  }

  @Test
  func rejectsOutOfRangePort() {
    #expect(CompanionAddress.parse(tcp: "host:0") == nil)
    #expect(CompanionAddress.parse(tcp: "host:70000") == nil)
  }

  @Test
  func rejectsEmptyHost() {
    #expect(CompanionAddress.parse(tcp: ":10882") == nil)
  }
}
