/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <FBControlCore/FBWeakFramework.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A set of definiitons for Frameworks that can be loaded weakly.
 Some of these are dependent on Xcode (they are contained within Xcode.app) and others are installed or available at the system level.
 Headers for the relevant classes/functions within these Frameworks are available within the PrivateFrameworks directory at the root of this project.
 */
@interface FBWeakFramework (ApplePrivateFrameworks)

/**
 CoreSimulator is the foundational framework for managing Simulators.
 */
@property (nonatomic, strong, readonly, class) FBWeakFramework *CoreSimulator;

/**
 SimulatorKit builds on top of CoreSimulator and is bundled with Xcode.
 It is used by Simulator.app for functionality involving touch interaction and framebuffers.
 */
@property (nonatomic, strong, readonly, class) FBWeakFramework *SimulatorKit;

/**
 DTXConnectionServices is a client library of the 'testmanagerd' daemon.
 It is used by XCTestBoostrap for connecting to and arbitrating test sessions with a Simulator/Device.
 */
@property (nonatomic, strong, readonly, class) FBWeakFramework *DTXConnectionServices;

/**
 The host-side Framework for XCTest. This is not the same as the XCTest Framework that is running on the iOS Simulator/Device.
 To avoid ambiguity with XCTest Framework naming, the classes that are used from this Framework are in the 'XCTestPrivate' PrivateHeader dump.
 */
@property (nonatomic, strong, readonly, class) FBWeakFramework *XCTest;

/**
 The main Framework that is used for talking to iOS Devices. Installed at the System level since macOS itself relies on it, not just Xcode.
 Heavily CoreFoundation based, likely because MobileDevice is also available on Windows (due to the porting of iTunes there).
 */
@property (nonatomic, strong, readonly, class) FBWeakFramework *MobileDevice;

/**
 A macOS Private Framework for transforming iOS Accessibility element definitions to their macOS equivalents.
 */
@property (nonatomic, strong, readonly, class) FBWeakFramework *AccessibilityPlatformTranslation;

@end

NS_ASSUME_NONNULL_END
