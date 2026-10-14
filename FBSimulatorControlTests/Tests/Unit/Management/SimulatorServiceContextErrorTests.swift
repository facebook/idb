/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import Foundation
import Testing

@Suite
struct SimulatorServiceContextErrorTests {

  @Test
  func noFullXcodeSelectedMessageIsStable() {
    // User-facing message; pinned verbatim.
    #expect(
      SimulatorServiceContextError.noFullXcodeSelected.errorDescription == "No full Xcode developer directory is selected. Select one with `xcode-select -s` or set DEVELOPER_DIR."
    )
  }

  @Test
  func serviceContextUnavailableComposesUnderlyingReason() {
    let error = SimulatorServiceContextError.serviceContextUnavailable(
      developerDirectory: "/Applications/Xcode.app/Contents/Developer",
      reason: "the underlying boom"
    )
    #expect(
      error.errorDescription == "Could not create a SimServiceContext for developer directory '/Applications/Xcode.app/Contents/Developer': the underlying boom"
    )
  }

  @Test
  func serviceContextUnavailableWithoutReasonOmitsSuffix() {
    let error = SimulatorServiceContextError.serviceContextUnavailable(
      developerDirectory: "/dev/dir",
      reason: nil
    )
    #expect(error.errorDescription == "Could not create a SimServiceContext for developer directory '/dev/dir'")
  }

  @Test
  func descriptionMirrorsErrorDescription() {
    let error = SimulatorServiceContextError.deviceSetPathResolutionFailed(path: "/tmp/set", reason: "No such file or directory")
    #expect(error.description == error.errorDescription)
  }
}
