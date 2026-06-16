/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

final class FBSimulatorVideoTests: XCTestCase {

  // MARK: - recordVideoArguments(forSimctlVersion:)

  func testRecordVideoArgumentsBelowThresholdUsesType() {
    let arguments = FBSimulatorVideoSimCtlSupport.recordVideoArguments(forSimctlVersion: NSDecimalNumber(string: "681.13"))
    XCTAssertEqual(arguments, ["--type=mp4"])
  }

  func testRecordVideoArgumentsAtThresholdUsesCodec() {
    let arguments = FBSimulatorVideoSimCtlSupport.recordVideoArguments(forSimctlVersion: NSDecimalNumber(string: "681.14"))
    XCTAssertEqual(arguments, ["--codec=h264", "--force"])
  }

  func testRecordVideoArgumentsAboveThresholdUsesCodec() {
    let arguments = FBSimulatorVideoSimCtlSupport.recordVideoArguments(forSimctlVersion: NSDecimalNumber(string: "994.1"))
    XCTAssertEqual(arguments, ["--codec=h264", "--force"])
  }

  func testRecordVideoArgumentsForZeroVersionUsesType() {
    let arguments = FBSimulatorVideoSimCtlSupport.recordVideoArguments(forSimctlVersion: .zero)
    XCTAssertEqual(arguments, ["--type=mp4"])
  }

  func testRecordVideoArgumentsForMuchOlderVersionUsesType() {
    let arguments = FBSimulatorVideoSimCtlSupport.recordVideoArguments(forSimctlVersion: NSDecimalNumber(string: "100"))
    XCTAssertEqual(arguments, ["--type=mp4"])
  }

  // MARK: - parseSimctlVersion(fromWhatOutput:)

  func testParseSimctlVersionFromRealisticWhatOutput() throws {
    let output = """
      /Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl:
              PROJECT:CoreSimulator-994.1
              Pproject:CoreSimulator-994.1
      """
    let version = try XCTUnwrap(FBSimulatorVideoSimCtlSupport.parseSimctlVersion(fromWhatOutput: output))
    XCTAssertEqual(version.compare(NSDecimalNumber(string: "994.1")), .orderedSame)
  }

  func testParseSimctlVersionWithThresholdVersion() throws {
    let version = try XCTUnwrap(FBSimulatorVideoSimCtlSupport.parseSimctlVersion(fromWhatOutput: "CoreSimulator-681.14"))
    XCTAssertEqual(version.compare(NSDecimalNumber(string: "681.14")), .orderedSame)
  }

  func testParseSimctlVersionReturnsFirstMatch() throws {
    let output = "CoreSimulator-700.0 then later CoreSimulator-800.0"
    let version = try XCTUnwrap(FBSimulatorVideoSimCtlSupport.parseSimctlVersion(fromWhatOutput: output))
    XCTAssertEqual(version.compare(NSDecimalNumber(string: "700.0")), .orderedSame)
  }

  func testParseSimctlVersionWithoutTokenReturnsNil() {
    XCTAssertNil(FBSimulatorVideoSimCtlSupport.parseSimctlVersion(fromWhatOutput: "no version token here"))
  }

  func testParseSimctlVersionFromEmptyOutputReturnsNil() {
    XCTAssertNil(FBSimulatorVideoSimCtlSupport.parseSimctlVersion(fromWhatOutput: ""))
  }
}
