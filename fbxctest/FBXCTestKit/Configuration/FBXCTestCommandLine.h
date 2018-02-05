/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Represents the Command Line for fbxctest.
 */
@interface FBXCTestCommandLine : NSObject

/**
 Creates and loads a configuration from arguments.

 @param arguments the Arguments to the fbxctest process
 @param environment environment additions for the process under test.
 @param workingDirectory the Working Directory to use.
 @param error an error out for any error that occurs
 @return a new test run configuration.
 */
+ (nullable instancetype)commandLineFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory error:(NSError **)error;

/**
 Creates and loads a configuration from arguments.

 @param arguments the Arguments to the fbxctest process
 @param environment environment additions for the process under test.
 @param workingDirectory the Working Directory to use.
 @Param timeout the timeout of the test.
 @param error an error out for any error that occurs
 @return a new test run configuration.
 */
+ (nullable instancetype)commandLineFromArguments:(NSArray<NSString *> *)arguments processUnderTestEnvironment:(NSDictionary<NSString *, NSString *> *)environment workingDirectory:(NSString *)workingDirectory timeout:(NSTimeInterval)timeout error:(NSError **)error;

/**
 The Designated Inititalizer

 @param configuration the configuration for the test run.
 @param destination the destination to run against.
 */
+ (instancetype)commandLineWithConfiguration:(FBXCTestConfiguration *)configuration destination:(FBXCTestDestination *)destination;

#pragma mark Properties

/**
 The Test Configuration
 */
@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;

/**
 The Destination
 */
@property (nonatomic, strong, readonly) FBXCTestDestination *destination;

@end

NS_ASSUME_NONNULL_END
