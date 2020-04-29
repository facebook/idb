/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBXCTestReporter;

typedef NS_ENUM(NSUInteger, FBIDBTestOperationState) {
  //Test has not started running
  FBIDBTestOperationStateNotRunning,
  //Test has completed
  FBIDBTestOperationStateTerminatedNormally,
  //Test has terminated before completing. probably crashed
  FBIDBTestOperationStateTerminatedAbnormally,
  //Test is running
  FBIDBTestOperationStateRunning
};

/**
 The long-running test operation class
 */
@interface FBIDBTestOperation : NSObject <FBiOSTargetContinuation>

- (instancetype)initWithConfiguration:(id<FBJSONSerializable>)configuration resultBundlePath:(nullable NSString *)resultBundlePath coveragePath:(nullable NSString *)coveragePath binaryPath:(nullable NSString *)binaryPath reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger completed:(FBFuture<NSNull *> *)completed queue:(dispatch_queue_t)queue;

/**
 The Execution State.
 */
@property (nonatomic, assign, readonly) FBIDBTestOperationState state;

/**
 The logger to log to during the test operation.
 */
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

/**
 The queue to serialize on
*/
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

/**
 The path to the result bundle
*/
@property (nonatomic, nullable, copy, readonly) NSString *resultBundlePath;

/**
 The reporter to report to.
*/
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;

/**
 The path to the coverage file
*/
@property (nonatomic, nullable, copy, readonly) NSString *coveragePath;

/**
 The path to the app binary
*/
@property (nonatomic, nullable, copy, readonly) NSString *binaryPath;

@end

NS_ASSUME_NONNULL_END
