/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

extension FBWeakFramework {

  @objc(CoreSimulator) public class var coreSimulator: FBWeakFramework {
    return FBWeakFramework.framework(withPath: "/Library/Developer/PrivateFrameworks/CoreSimulator.framework", requiredClassNames: ["SimDevice"], rootPermitted: false)
  }

  @objc(SimulatorKit) public class var simulatorKit: FBWeakFramework {
    return FBWeakFramework.xcodeFramework(withRelativePath: "Library/PrivateFrameworks/SimulatorKit.framework", requiredClassNames: [])
  }

  @objc(DTXConnectionServices) public class var dtxConnectionServices: FBWeakFramework {
    return FBWeakFramework.xcodeFramework(withRelativePath: "../SharedFrameworks/DTXConnectionServices.framework", requiredClassNames: ["DTXConnection", "DTXRemoteInvocationReceipt"])
  }

  @objc(XCTest) public class var xcTest: FBWeakFramework {
    return FBWeakFramework.xcodeFramework(withRelativePath: "Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework", requiredClassNames: ["XCTestConfiguration"])
  }

  @objc(MobileDevice) public class var mobileDevice: FBWeakFramework {
    return FBWeakFramework.framework(withPath: "/System/Library/PrivateFrameworks/MobileDevice.framework", requiredClassNames: [], rootPermitted: true)
  }

  @objc(AccessibilityPlatformTranslation) public class var accessibilityPlatformTranslation: FBWeakFramework {
    return FBWeakFramework.framework(withPath: "/System/Library/PrivateFrameworks/AccessibilityPlatformTranslation.framework", requiredClassNames: ["AXPTranslationObject"], rootPermitted: false)
  }
}
