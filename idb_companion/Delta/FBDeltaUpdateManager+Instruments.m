/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDeltaUpdateManager+Instruments.h"

#import "FBIDBError.h"

static const NSTimeInterval MaximumInstrumentTime = 60 * 60 * 4; // 4 Hours.

@implementation FBInstrumentsDelta

- (instancetype)initWithLogOutput:(NSString *)logOutput traceFile:(NSURL *)traceFile
{
  self = [self init];
  if (!self) {
    return nil;
  }

  _logOutput = logOutput;
  _traceFile = traceFile;

  return self;
}

@end

@implementation FBDeltaUpdateManager (Instruments)

#pragma mark Initializers

+ (FBInstrumentsManager *)instrumentsManagerWithTarget:(id<FBiOSTarget>)target
{
  return [self
    managerWithTarget:target
    name:@"instruments"
    expiration:@(MaximumInstrumentTime)
    capacity:@1
    logger:target.logger
    create:^ FBFuture<FBInstrumentsOperation *> * (FBInstrumentsConfiguration *configuration) {
      id<FBConsumableBuffer> logBuffer = FBDataBuffer.consumableBuffer;
      id<FBControlCoreLogger> logger = [[FBControlCoreLogger loggerToConsumer:logBuffer] withDateFormatEnabled:YES];
      return [target startInstrument:configuration logger:logger];
    }
    delta:^ FBFuture<FBInstrumentsDelta *> * (FBInstrumentsOperation *operation, NSString *identifier, BOOL *done) {
      id logger = operation.logger;
      id<FBConsumableBuffer> logBuffer = (id<FBConsumableBuffer>) [logger consumer];
      NSString *logOutput = [logBuffer consumeCurrentString];
      FBInstrumentsDelta *delta = [[FBInstrumentsDelta alloc] initWithLogOutput:logOutput traceFile:operation.traceFile];
      return [FBFuture futureWithResult:delta];
    }];
}

+ (FBFuture<NSURL *> *)postProcess:(NSArray<NSString *> *)arguments traceFile:(NSURL *)traceFile queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  if (!arguments || arguments.count == 0) {
    return [FBFuture futureWithResult:traceFile];
  }
  NSURL *outputTraceFile = [[traceFile URLByDeletingLastPathComponent] URLByAppendingPathComponent:arguments[2]];
  NSMutableArray<NSString *> *launchArguments = [@[arguments[1], traceFile.path, @"-o", outputTraceFile.path] mutableCopy];
  if (arguments.count > 3) {
    [launchArguments addObjectsFromArray:[arguments subarrayWithRange:(NSRange){3, [arguments count] - 3}]];
  }

  [logger logFormat:@"Starting post processing | Launch path: %@ | Arguments: %@", arguments[0], [FBCollectionInformation oneLineDescriptionFromArray:launchArguments]];
  return [[[[[[[FBTaskBuilder
    withLaunchPath:arguments[0]]
    withArguments:launchArguments]
    withStdOutToLogger:logger]
    withStdErrToLogger:logger]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    runUntilCompletion]
    onQueue:queue map:^(id _) {
      return outputTraceFile;
    }];
}

+ (FBFuture<FBInstrumentsDelta *> *)postProcess:(NSArray<NSString *> *)arguments delta:(FBInstrumentsDelta *)delta queue:(dispatch_queue_t)queue
{
  id<FBConsumableBuffer> logBuffer = FBDataBuffer.consumableBuffer;
  id<FBControlCoreLogger> logger = [FBControlCoreLogger loggerToConsumer:logBuffer];
  return [[self
    postProcess:arguments traceFile:delta.traceFile queue:queue logger:logger]
    onQueue:queue map:^(NSURL *result) {
      return [[FBInstrumentsDelta alloc] initWithLogOutput:logBuffer.consumeCurrentString traceFile:result];
    }];
}

@end
