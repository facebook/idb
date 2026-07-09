/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import Metal
import XCTest

final class FBSimulatorFramebufferTests: FBSimulatorControlTestCase {

  // Commented out: causes target-level timeout (too slow with other tests)
  // func testRecordsVideoForSimulatorApp() {
  //   guard MTLCreateSystemDefaultDevice() != nil else {
  //     NSLog("Skipping running -[\(type(of: self)) \(#function)] since Metal is not supported on this Hardware")
  //     return
  //   }
  //   let bootConfig = bootConfiguration
  //   guard let simulator = assertObtainsBootedSimulator(
  //     withConfiguration: simulatorConfiguration,
  //     bootConfiguration: bootConfig
  //   ) else { return }
  //
  //   let filePath = (NSTemporaryDirectory() as NSString)
  //     .appendingPathComponent(UUID().uuidString)
  //     .appending(".mp4")
  //   var error: NSError?
  //   var success: Any? = simulator.startRecording(toFile: filePath).await(&error)
  //   XCTAssertNil(error)
  //   XCTAssertNotNil(success)
  //
  //   success = simulator.stopRecording().await(&error)
  //   XCTAssertNil(error)
  //   XCTAssertNotNil(success)
  // }
}
