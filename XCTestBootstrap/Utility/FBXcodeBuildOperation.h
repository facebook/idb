/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/FBXCTestCommands.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestLaunchConfiguration;

@protocol FBiOSTarget;

/**
 An Xcode Build Operation.
 */
@interface FBXcodeBuildOperation : NSObject <FBXCTestOperation>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param target the target to build an operation for.
 @param configuration the configuration to use.
 @param xcodeBuildPath the path to xcodebuild.
 @param testRunFilePath the path to the xcodebuild.xctestrun file
 @return a build operation.
 */
+ (instancetype)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBTestLaunchConfiguration *)configuration xcodeBuildPath:(NSString *)xcodeBuildPath testRunFilePath:(NSString *)testRunFilePath;

#pragma mark Public Methods

/**
 Terminates all reparented xcodebuild processes.

 @param target the target to obtain processes for.
 @param processFetcher the process fetcher.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
+ (BOOL)terminateReparentedXcodeBuildProcessesForTarget:(id<FBiOSTarget>)target processFetcher:(FBProcessFetcher *)processFetcher error:(NSError **)error;

/**
 Runs the reciever, returning when the Task has completed or when the timeout is hit.
 If the timeout is reached, the process will not be automatically terminated.

 @param timeout the the maximum time to evaluate the task.
 @return the reciever, for chaining.
 */
- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
