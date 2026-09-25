/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@_implementationOnly import SimulatorFrameworkBridgeSupport
import XCTest

final class PhotoLibraryServiceTests: XCTestCase {

  func testUnknownActionReturnsFailure() {
    XCTAssertEqual(FBPhotoLibraryService.handlePhotoLibraryAction(action: "delete"), 1)
    XCTAssertEqual(FBPhotoLibraryService.handlePhotoLibraryAction(action: ""), 1)
    XCTAssertEqual(FBPhotoLibraryService.handlePhotoLibraryAction(action: "add"), 1)
  }
}
