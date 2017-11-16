/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBTestLaunchConfiguration;
@class FBTestRunnerConfiguration;
@protocol FBiOSTarget;
@protocol FBFileManager;
@protocol FBCodesignProvider;

/**
 A Protocol for preparing iOS for running an XCTest.
 */
@protocol FBXCTestPreparationStrategy

/**
 Creates and returns a Strategy strategyWith given paramenters.
 Will use default implementations of the File Manager and Codesign.

 @param testLaunchConfiguration configuration used to launch test.
 @param workingDirectory directory used to prepare all bundles.
 @return A new FBSimulatorTestRunStrategy Instance.
 */
+ (instancetype)strategyWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                                   workingDirectory:(NSString *)workingDirectory;

/**
 Prepares FBTestRunnerConfiguration

 @param iosTarget iOS target used to prepare test
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return FBTestRunnerConfiguration configuration used to start test
 */
- (FBTestRunnerConfiguration *)prepareTestWithIOSTarget:(id<FBiOSTarget>)iosTarget error:(NSError **)error;

@end
