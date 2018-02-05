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
