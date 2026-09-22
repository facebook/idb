/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@testable import SimulatorFrameworkBridgeSupport
import Testing

struct PrivacyServiceTests {
  @Test func invalidRequestsNeverMutate() {
    for (action, arguments) in [
      ("check", ["app", "camera"]), ("approve", []), ("approve", ["app"]),
      ("revoke", ["", "photos"]),
      ("approve", ["app", "camera", "unknown"]), ("revoke", ["app", ""]),
    ] {
      var called = false
      let code = FBPrivacyService.execute(action: action, arguments: arguments) { _, _, _ in
        called = true
        return nil
      }
      #expect(code == 1)
      #expect(!called)
    }
  }

  @Test func approvalMapsAllServicesAndDeduplicatesWithoutChangingBundleID() {
    var calls = 0
    let code = FBPrivacyService.execute(action: "approve", arguments: ["com.example.app", "camera", "microphone", "photos", "contacts", "camera"]) { bundleID, services, approved in
      calls += 1
      #expect(bundleID == "com.example.app")
      #expect(services == ["kTCCServiceCamera", "kTCCServiceMicrophone", "kTCCServicePhotos", "kTCCServiceAddressBook"])
      #expect(approved)
      return nil
    }
    #expect(code == 0)
    #expect(calls == 1)
  }

  @Test func selectiveResetAndRuntimeFailurePropagate() {
    var calls = 0
    let code = FBPrivacyService.execute(action: "revoke", arguments: ["app", "photos"]) { bundleID, services, approved in
      calls += 1
      #expect(bundleID == "app")
      #expect(services == ["kTCCServicePhotos"])
      #expect(!approved)
      return "daemon rejected reset"
    }
    #expect(code == 1)
    #expect(calls == 1)
  }
}
