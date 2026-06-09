/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FBWeakFramework {

  @objc(CoreSimulator) public class var coreSimulator: FBWeakFramework {
    FBWeakFramework.framework(withPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework", requiredClassNames: ["SimDevice"], rootPermitted: false)
  }

  @objc(SimulatorKit) public class var simulatorKit: FBWeakFramework {
    // Xcode 27 moved SimulatorKit.framework from Contents/Developer/Library/PrivateFrameworks
    // to Contents/SharedFrameworks. Prefer the new location, falling back to the legacy one for
    // Xcode <= 26. xcodeFramework(withRelativePath:) resolves relative to the Developer directory.
    let sharedRelativePath = "../SharedFrameworks/SimulatorKit.framework"
    let sharedAbsolutePath = ((FBXcodeConfiguration.developerDirectory as NSString).appendingPathComponent(sharedRelativePath) as NSString).standardizingPath
    let relativePath = FileManager.default.fileExists(atPath: sharedAbsolutePath) ? sharedRelativePath : "Library/PrivateFrameworks/SimulatorKit.framework"
    return FBWeakFramework.xcodeFramework(withRelativePath: relativePath, requiredClassNames: [])
  }

  @objc(DTXConnectionServices) public class var dtxConnectionServices: FBWeakFramework {
    FBWeakFramework.xcodeFramework(withRelativePath: "../SharedFrameworks/DTXConnectionServices.framework", requiredClassNames: ["DTXConnection", "DTXRemoteInvocationReceipt"])
  }

  @objc(XCTest) public class var xcTest: FBWeakFramework {
    FBWeakFramework.xcodeFramework(withRelativePath: "Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework", requiredClassNames: ["XCTestConfiguration"])
  }

  @objc(MobileDevice) public class var mobileDevice: FBWeakFramework {
    FBWeakFramework.framework(withPath: "/System/Library/PrivateFrameworks/MobileDevice.framework", requiredClassNames: [], rootPermitted: true)
  }

  @objc(AccessibilityPlatformTranslation) public class var accessibilityPlatformTranslation: FBWeakFramework {
    FBWeakFramework.framework(withPath: "/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework", requiredClassNames: ["AXPTranslationObject"], rootPermitted: false)
  }
}
