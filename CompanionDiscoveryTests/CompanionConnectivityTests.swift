/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import Darwin
import Foundation
import Testing

/// Tests the domain-socket liveness probe used to decide whether to reuse an
/// existing companion.
@Suite
struct CompanionConnectivityTests {
  @Test
  func falseWhenPathDoesNotExist() {
    #expect(CompanionConnectivity.isDomainSocketBound(path: TestSupport.shortSocketPath()) == false)
  }

  @Test
  func falseForRegularFile() throws {
    let path = TestSupport.shortSocketPath()
    defer { unlink(path) }
    try "not a socket".write(toFile: path, atomically: true, encoding: .utf8)
    #expect(CompanionConnectivity.isDomainSocketBound(path: path) == false)
  }

  @Test
  func trueForListeningSocket() {
    let path = TestSupport.shortSocketPath()
    let fd = TestSupport.makeListeningSocket(at: path)
    defer {
      close(fd)
      unlink(path)
    }
    #expect(CompanionConnectivity.isDomainSocketBound(path: path) == true)
  }

  @Test
  func falseAfterSocketClosedAndUnlinked() {
    let path = TestSupport.shortSocketPath()
    let fd = TestSupport.makeListeningSocket(at: path)
    close(fd)
    unlink(path)
    #expect(CompanionConnectivity.isDomainSocketBound(path: path) == false)
  }
}
