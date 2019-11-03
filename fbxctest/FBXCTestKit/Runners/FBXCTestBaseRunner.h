/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

NS_ASSUME_NONNULL_BEGIN

@class FBXCTestCommandLine;
@class FBXCTestContext;

/**
 The base runner for fbxctest, dispatches a configuration to the appropriate runner.
 */
@interface FBXCTestBaseRunner : NSObject <FBXCTestRunner>

#pragma mark Initializers

/**
 The Designated Initializer

 @param commandLine the configuration from the commandline.
 @param context the context to run with.
 */
+ (instancetype)testRunnerWithCommandLine:(FBXCTestCommandLine *)commandLine context:(FBXCTestContext *)context;

@end

NS_ASSUME_NONNULL_END
