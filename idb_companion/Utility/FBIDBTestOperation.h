/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBConsumableXCTestReporter;

typedef NS_ENUM(NSUInteger, FBIDBTestManagerState) {
  //Test has not started running
  FBIDBTestManagerStateNotRunning,
  //Test has completed
  FBIDBTestManagerStateTerminatedNormally,
  //Test has terminated before completing. probably crashed
  FBIDBTestManagerStateTerminatedAbnormally,
  //Test is running
  FBIDBTestManagerStateRunning
};

/**
 The long-running test operation class
 */
@interface FBIDBTestOperation : NSObject <FBiOSTargetContinuation>

- (instancetype)initWithConfiguration:(id<FBJSONSerializable>)configuration resultBundlePath:(nullable NSString *)resultBundlePath reporter:(FBConsumableXCTestReporter *)reporter logBuffer:(id<FBConsumableBuffer>)logBuffer completed:(FBFuture<NSNull *> *)completed queue:(dispatch_queue_t)queue;

/**
 The Execution State.
 */
@property (nonatomic, assign, readonly) FBIDBTestManagerState state;

/**
 The Log Buffer of the test operation.
 */
@property (nonatomic, strong, readonly) id<FBConsumableBuffer> logBuffer;

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
@property (nonatomic, strong, readonly) FBConsumableXCTestReporter *reporter;

@end

NS_ASSUME_NONNULL_END
