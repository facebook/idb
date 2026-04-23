/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

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
