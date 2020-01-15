/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBBootManager.h"

#import "FBIDBTestOperation.h"

@interface FBIDBTestOperation ()

@property (nonatomic, strong, readonly) id<FBJSONSerializable> configuration;

@end

@implementation FBIDBTestOperation

@synthesize completed = _completed;

- (instancetype)initWithConfiguration:(id<FBJSONSerializable>)configuration resultBundlePath:(NSString *)resultBundlePath reporter:(FBConsumableXCTestReporter *)reporter logBuffer:(id<FBConsumableBuffer>)logBuffer completed:(FBFuture<NSNull *> *)completed queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _resultBundlePath = resultBundlePath;
  _reporter = reporter;
  _logBuffer = logBuffer;
  _completed = completed;
  _queue = queue;

  return self;
}

- (FBIDBTestManagerState)state
{
  if (self.completed) {
    if (self.completed.error) {
      return FBIDBTestManagerStateTerminatedAbnormally;
    } else {
      return self.completed.hasCompleted ? FBIDBTestManagerStateTerminatedNormally : FBIDBTestManagerStateRunning;
    }
  } else {
    return FBIDBTestManagerStateNotRunning;
  }
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Test Run (%@)", self.configuration.jsonSerializableRepresentation];
}

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeTestOperation;
}

@end
