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
