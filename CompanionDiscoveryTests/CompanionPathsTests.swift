/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Testing

/// Locks in the filesystem conventions shared with the Python `idb` client.
@Suite
struct CompanionPathsTests {
  @Test
  func usesSharedIdbLocations() {
    #expect(CompanionPaths.baseDirectory == "/tmp/idb")
    #expect(CompanionPaths.stateFile == "/tmp/idb/state")
    #expect(CompanionPaths.logsDirectory == "/tmp/idb/logs")
  }

  @Test
  func companionSocketPathMatchesConvention() {
    #expect(CompanionPaths.companionSocketPath(forUDID: "ABCD") == "/tmp/idb/ABCD_companion.sock")
  }

  @Test
  func logFilePathMatchesConvention() {
    #expect(CompanionPaths.logFilePath(forUDID: "ABCD") == "/tmp/idb/logs/ABCD")
  }
}
