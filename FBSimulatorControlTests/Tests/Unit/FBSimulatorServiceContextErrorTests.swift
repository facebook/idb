/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorServiceContextErrorTests: XCTestCase {

  func testNoFullXcodeSelectedMessageIsStable() {
    // This message is user-facing (idb / sime2e surface it when no full Xcode is selected); pin it.
    XCTAssertEqual(
      FBSimulatorServiceContextError.noFullXcodeSelected.errorDescription,
      "No full Xcode developer directory is selected. Select one with `xcode-select -s` or set DEVELOPER_DIR."
    )
  }

  func testServiceContextUnavailableComposesUnderlyingReason() {
    let error = FBSimulatorServiceContextError.serviceContextUnavailable(
      developerDirectory: "/Applications/Xcode.app/Contents/Developer",
      reason: "the underlying boom"
    )
    XCTAssertEqual(
      error.errorDescription,
      "Could not create a SimServiceContext for developer directory '/Applications/Xcode.app/Contents/Developer': the underlying boom"
    )
  }

  func testServiceContextUnavailableWithoutReasonOmitsSuffix() {
    let error = FBSimulatorServiceContextError.serviceContextUnavailable(
      developerDirectory: "/dev/dir",
      reason: nil
    )
    XCTAssertEqual(error.errorDescription, "Could not create a SimServiceContext for developer directory '/dev/dir'")
  }

  func testDescriptionMirrorsErrorDescription() {
    let error = FBSimulatorServiceContextError.deviceSetPathResolutionFailed(path: "/tmp/set", reason: "No such file or directory")
    XCTAssertEqual(error.description, error.errorDescription)
  }
}
