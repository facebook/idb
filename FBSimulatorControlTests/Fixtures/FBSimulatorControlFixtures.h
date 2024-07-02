/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@class FBApplicationLaunchConfiguration;
@class FBBundleDescriptor;
@class FBProcessInfo;
@class FBProcessSpawnConfiguration;
@class FBTestLaunchConfiguration;

typedef NS_ENUM(NSUInteger, FBApplicationLaunchMode);

NS_ASSUME_NONNULL_BEGIN

/**
 Fixtures for Tests.
 */
@interface FBSimulatorControlFixtures : NSObject

/**
 A File Path to the first photo.
 */
+ (NSString *)photo0Path;

/**
 A File Path to the second photo.
 */
+ (NSString *)photo1Path;

/**
 A File Path to the first video.
 */
+ (NSString *)video0Path;

@end

/**
 Fetching Fixtures, causing test failures if they cannot be obtained.
 */
@interface XCTestCase (FBSimulatorControlFixtures)

/**
 A XCTest launch configuration with injection inside TableSearch.app.
 */
- (FBTestLaunchConfiguration *)testLaunchTableSearch;

/**
 A XCTest launch configuration with injection inside Safari.app.
 */
- (FBTestLaunchConfiguration *)testLaunchSafari;

/**
 An App Launch for the built in Mobile Safari.
 */
- (FBApplicationLaunchConfiguration *)safariAppLaunch;

/**
 An App Launch for the built in Mobile Safari in a given mode
 */
- (FBApplicationLaunchConfiguration *)safariAppLaunchWithMode:(FBApplicationLaunchMode)launchMode;

/**
 A build of Apple's 'Table Search' Sample Application.
 Source is available at: https://developer.apple.com/library/ios/samplecode/TableSearch_UISearchController/Introduction/Intro.html#//apple_ref/doc/uid/TP40014683
 */
- (FBBundleDescriptor *)tableSearchApplication;

/**
 A build of Apple's 'Table Search' Sample Application.
 Source is available at: https://developer.apple.com/library/ios/samplecode/TableSearch_UISearchController/Introduction/Intro.html#//apple_ref/doc/uid/TP40014683
 */
- (FBApplicationLaunchConfiguration *)tableSearchAppLaunch;

/**
 An Agent Launch Config. Not to be used to launch agents for real.
 */
- (FBProcessSpawnConfiguration *)agentLaunch1;

/**
 An iOS Unit Test XCTest Target.
 Will check that the bundle is codesigned, and sign it if is not.

 @return Unit Test Bundle Descriptor.
 */
- (nullable FBBundleDescriptor *)iOSUnitTestBundle;

@end

NS_ASSUME_NONNULL_END
