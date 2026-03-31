// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import XCTest

@testable import FBSimulatorControl

final class FBSimulatorApplicationDescriptorTests: FBSimulatorControlTestCase {

  func testCreatesSampleApplication() {
    let application = self.tableSearchApplication()
    XCTAssertEqual(application.identifier, "com.example.apple-samplecode.TableSearch")
    XCTAssertEqual(application.binary!.architectures, Set([FBBinaryArchitecture(rawValue: "i386"), FBBinaryArchitecture(rawValue: "x86_64")]))
  }
}
