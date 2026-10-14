/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorCodeInjection
@testable import FBSimulatorControl
import Testing

@Suite("Simulator REPL command retention")
struct SimulatorReplCommandRetentionTests {
  @Test("Resolving the REPL commands does not retain the simulator")
  func resolvingTheReplCommandsDoesNotRetainTheSimulator() {
    #expect(simulatorSurvives { _ = $0.repl } == false)
  }
}
