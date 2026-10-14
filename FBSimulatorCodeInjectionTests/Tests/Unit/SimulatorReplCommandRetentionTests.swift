/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorCodeInjection
@testable import FBSimulatorControl
import Testing

@Suite("Simulator code injection command retention")
struct SimulatorReplCommandRetentionTests {
  @Test("Resolving the code injection commands does not retain the simulator")
  func resolvingTheCodeInjectionCommandsDoesNotRetainTheSimulator() {
    #expect(simulatorSurvives { _ = $0.codeInjection } == false)
  }
}
