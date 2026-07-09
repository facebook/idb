/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Testing

/// Locks in the filesystem conventions for each companion version: v1 shares the
/// Python `idb` client's locations, v2 lives under a separate directory.
@Suite
struct CompanionPathsTests {
  @Test
  func v1UsesSharedIdbLocations() {
    let paths = CompanionPaths(version: .v1)
    #expect(paths.baseDirectory == "/tmp/idb")
    #expect(paths.stateFile == "/tmp/idb/state")
    #expect(paths.logsDirectory == "/tmp/idb/logs")
    #expect(paths.companionSocketPath(forUDID: "ABCD") == "/tmp/idb/ABCD_companion.sock")
    #expect(paths.logFilePath(forUDID: "ABCD") == "/tmp/idb/logs/ABCD")
  }

  @Test
  func v2UsesSeparateIdb2Locations() {
    let paths = CompanionPaths(version: .v2)
    #expect(paths.baseDirectory == "/tmp/idb2")
    #expect(paths.stateFile == "/tmp/idb2/state")
    #expect(paths.logsDirectory == "/tmp/idb2/logs")
    #expect(paths.companionSocketPath(forUDID: "ABCD") == "/tmp/idb2/ABCD_companion.sock")
    #expect(paths.logFilePath(forUDID: "ABCD") == "/tmp/idb2/logs/ABCD")
  }

  @Test
  func defaultsToV1() {
    #expect(CompanionPaths().baseDirectory == CompanionPaths(version: .v1).baseDirectory)
  }

  @Test
  func companionBinaryIsVersionAware() {
    #expect(CompanionPaths(version: .v1).defaultCompanionExecutable == "/usr/local/bin/idb_companion")
    #expect(CompanionPaths(version: .v2).defaultCompanionExecutable == "/usr/local/bin/idb2")
  }
}
