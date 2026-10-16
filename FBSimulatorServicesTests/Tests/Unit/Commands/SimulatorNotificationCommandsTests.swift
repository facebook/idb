/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
@testable import FBSimulatorServices
import Foundation
import Testing

@Suite
struct SimulatorNotificationCommandsTests {
  @Test
  func deliveredNotificationsFailOnALineTheyCannotDecode() throws {
    let record = #"{"bundleID":"com.foo","identifier":"one","title":"T","subtitle":"S","body":"B","threadIdentifier":"th","date":1}"#

    #expect(try DeliveredNotification.records(fromBridgeOutput: "\(record)\n\(record)").count == 2)

    // Both halves of what the guest can break: a line that is not JSON at all, and one that
    // is but does not carry a whole record. Passing over either answers with a list shorter
    // than the app's, which reads as an app that received fewer notifications than it did.
    for malformed in ["not json", #"{"bundleID":"com.foo"}"#] {
      let thrown = #expect(throws: (any Error).self) { try DeliveredNotification.records(fromBridgeOutput: "\(record)\n\(malformed)") }
      guard let thrown else { continue }
      guard let error = thrown as? SimulatorNotificationError,
        case let .undecodableDeliveredNotification(line, _) = error
      else {
        Issue.record("'\(malformed)' should fail the read; threw \(thrown)")
        continue
      }
      #expect(line == malformed)
    }
  }
}
