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
 Reads a .xctestrun file from a given path and provides access to its properties.
 */
@interface FBXCTestRunConfiguration : NSObject

/**
 The designated initializer

 @param testRunConfigurationPath path to .xctestrun file
 @return a new FBXCTestRunConfigurationReader Instance
 */
+ (instancetype)withTestRunConfigurationAtPath:(NSString *)testRunConfigurationPath;

/**
 The path to the test host application.
 */
@property (nonatomic, copy, readonly, nullable) NSString *testHostPath;

/*
 The path to the test bundle.
 */
@property (nonatomic, copy, readonly, nullable) NSString *testBundlePath;

/**
 The application launch arguments.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

/*
 The application launch environment variables.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;

/*
 Skip these tests. Format: "className/methodName"
 */
@property (nonatomic, copy, readonly) NSSet<NSString *> *testsToSkip;

/*
 Run only these tests. Format: "className/methodName"
 */
@property (nonatomic, copy, readonly) NSSet<NSString *> *testsToRun;

/**
 @param error If there is an error, upon return contains an NSError object that describes the problem.
 @return prepared test run configuration if the operation succeeds, otherwise nil.
 */
- (nullable instancetype)buildWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
