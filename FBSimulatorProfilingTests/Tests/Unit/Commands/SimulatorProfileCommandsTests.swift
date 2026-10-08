/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorProfiling
import Foundation
import Testing

@Suite("Memory graph path")
struct SimulatorProfileCommandsTests {

  @Test("A relative path resolves against the host's working directory")
  func relative() {
    let expected = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("graph.memgraph").standardizedFileURL.path
    #expect(SimulatorProfileCommands.graphPath(for: "graph") == expected)
  }

  @Test("An absolute path with the extension is kept as is")
  func absolute() {
    #expect(SimulatorProfileCommands.graphPath(for: "/tmp/graph.memgraph") == "/tmp/graph.memgraph")
  }
}
