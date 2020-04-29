/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBTestOperation.h"

@interface FBIDBTestOperation ()

@property (nonatomic, strong, readonly) id<FBJSONSerializable> configuration;

@end

@implementation FBIDBTestOperation

@synthesize completed = _completed;

- (instancetype)initWithConfiguration:(id<FBJSONSerializable>)configuration resultBundlePath:(NSString *)resultBundlePath coveragePath:(NSString *)coveragePath  binaryPath:(nullable NSString *)binaryPath reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger completed:(FBFuture<NSNull *> *)completed queue:(dispatch_queue_t)queue
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _resultBundlePath = resultBundlePath;
  _coveragePath = coveragePath;
  _binaryPath = binaryPath;
  _reporter = reporter;
  _logger = logger;
  _completed = completed;
  _queue = queue;

  return self;
}

- (FBIDBTestOperationState)state
{
  if (self.completed) {
    if (self.completed.error) {
      return FBIDBTestOperationStateTerminatedAbnormally;
    } else {
      return self.completed.hasCompleted ? FBIDBTestOperationStateTerminatedNormally : FBIDBTestOperationStateRunning;
    }
  } else {
    return FBIDBTestOperationStateNotRunning;
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
