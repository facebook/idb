/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

@class FBDiagnostic;
@class FBProcessInfo;

/**
 Fixtures for Tests.
 */
@interface FBControlCoreFixtures : NSObject

/**
 A File Path to the first photo.
 */
+ (NSString *)photo0Path;

/**
 A File Path to sample system log.
 */
+ (NSString *)simulatorSystemLogPath;

/**
 A File Path to the WebDriverAgent Element Tree of Springboard.
 */
+ (NSString *)treeJSONPath;

/**
 A Crash of a System Simulator Service.
 */
+ (NSString *)assetsdCrashPathWithCustomDeviceSet;

/**
 A Crash of an app in a default Simulator Device Set.
 */
+ (NSString *)appCrashPathWithDefaultDeviceSet;

/**
 A Crash of an app with a custom Simulator Device Set.
 */
+ (NSString *)appCrashPathWithCustomDeviceSet;

/**
 A Crash of an agent with a custom Simulator Device Set.
 */
+ (NSString *)agentCrashPathWithCustomDeviceSet;

/**
 All of the above, in a directory
 */
+ (NSString *)bundleResource;

@end

@interface XCTestCase (FBControlCoreFixtures)

/**
 A System Log.
 */
- (FBDiagnostic *)simulatorSystemLog;

/**
 A Diagnostic for the WebDriverAgent Element Tree of Springboard.
 */
- (FBDiagnostic *)treeJSONDiagnostic;

/**
 A Diagnostic of a PNG.
 */
- (FBDiagnostic *)photoDiagnostic;

/**
 A Process.
 */
- (FBProcessInfo *)launchCtlProcess;

@end
