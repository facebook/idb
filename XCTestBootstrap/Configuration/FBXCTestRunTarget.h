/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBApplicationDescriptor;
@class FBTestLaunchConfiguration;

NS_ASSUME_NONNULL_BEGIN

/**
 A Value object with the information required to launch some XCTestRun target.
 */
@interface FBXCTestRunTarget : NSObject

/**
 The Designated Initializer

 @param testTargetName name of the test target
 @param testLaunchConfiguration test launch configuration for this test target
 @param applications array of applications that are required for the test run
 @return a new FBXCTestRunTarget Instance
 */
+ (instancetype)withName:(NSString *)testTargetName testLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration applications:(NSArray<FBApplicationDescriptor *> *)applications;

/**
 The test target name.
 */
@property (nonatomic, copy, readonly) NSString *name;

/**
 List of applications that are required for the test run.
 */
@property (nonatomic, copy, readonly) NSArray<FBApplicationDescriptor *> *applications;

/**
 Test launch configuration for this test target.
 */
@property (nonatomic, copy, readonly) FBTestLaunchConfiguration *testLaunchConfiguration;

@end

NS_ASSUME_NONNULL_END
