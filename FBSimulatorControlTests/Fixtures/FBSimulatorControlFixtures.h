/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;
@class FBDiagnostic;
@class FBProcessInfo;
@class FBSimulatorApplication;

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
 An Application for the built in Mobile Safari.
 */
- (FBSimulatorApplication *)safariApplication;

/**
 An App Launch for the built in Mobile Safari.
 */
- (FBApplicationLaunchConfiguration *)safariAppLaunch;

/**
 A build of Apple's 'Table Search' Sample Application.
 Source is available at: https://developer.apple.com/library/ios/samplecode/TableSearch_UISearchController/Introduction/Intro.html#//apple_ref/doc/uid/TP40014683
 */
- (FBSimulatorApplication *)tableSearchApplication;

/**
 A build of Apple's 'Table Search' Sample Application.
 Source is available at: https://developer.apple.com/library/ios/samplecode/TableSearch_UISearchController/Introduction/Intro.html#//apple_ref/doc/uid/TP40014683
 */
- (FBApplicationLaunchConfiguration *)tableSearchAppLaunch;

/**
 An Agent Launch Config. Not to be used to launch agents for real.
 */
- (FBAgentLaunchConfiguration *)agentLaunch1;

/**
 An App Launch Config. Not to be used to launch applications for real.
 */
- (FBApplicationLaunchConfiguration *)appLaunch1;

/**
 Another App Launch Config. Not to be used to launch applications for real.
 */
- (FBApplicationLaunchConfiguration *)appLaunch2;

/**
 A Process Info. Does not represent a real process.
 */
- (FBProcessInfo *)processInfo1;

/**
 Another Process Info. Does not represent a real process.
 */
- (FBProcessInfo *)processInfo2;

/**
 Another Process Info, like 'processInfo2a' but with a different pid. Does not represent a real process.
 */
- (FBProcessInfo *)processInfo2a;

/**
 An Application Test xctest bundle
 */
- (NSString *)applicationTestBundlePath;

@end
