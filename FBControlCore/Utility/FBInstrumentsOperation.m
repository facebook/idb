/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBInstrumentsOperation.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBDataConsumer.h"
#import "FBFuture.h"
#import "FBInstrumentsConfiguration.h"
#import "FBiOSTarget.h"
#import "FBTask+Helpers.h"
#import "FBTaskBuilder.h"

static const NSTimeInterval InterruptBackoffTimeout = 600.0; // When stopping instruments with SIGINT, wait this long before SIGKILLing it
static const NSTimeInterval InstrumentsStartupDelay = 15.0;  // Wait this long to ensure instruments started properly
static const NSTimeInterval InstrumentsStartupTimeout = 60.0; // Fail instruments startup after this amount of time

FBiOSTargetFutureType const FBiOSTargetFutureTypeInstruments = @"instruments";

@interface FBInstrumentsConsumer : NSObject <FBDataConsumer>

@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *hasStoppedRecording;
@property (nonatomic, strong, readonly) NSMutableArray<NSString *> *logs;
@property (nonatomic, strong, readonly) id<FBDataConsumer> consumer;

@end

@implementation FBInstrumentsConsumer

#pragma mark Initializers

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _hasStoppedRecording = FBMutableFuture.future;
  _logs = [NSMutableArray array];
  _consumer = [FBBlockDataConsumer asynchronousLineConsumerWithBlock:^(NSString *logLine) {
    if (![logLine isEqualToString:@""]) {
      [self.logs addObject:logLine];
    }
    if ([logLine containsString:@"Instruments Trace Complete"]) {
      if (![self.hasStoppedRecording hasCompleted]) {
        FBFuture *failFuture = [[FBControlCoreError
          describeFormat:@"Instruments did not start properly. Instruments logs:\n%@", [self.logs componentsJoinedByString:@"\n"]]
          failFuture];
        [self.hasStoppedRecording resolveFromFuture:failFuture];
      }
    }
  }];

  return self;
}

#pragma mark FBDataConsumer

- (void)consumeData:(NSData *)data
{
  [self.consumer consumeData:data];
}

- (void)consumeEndOfFile
{
  [self.consumer consumeEndOfFile];
}
@end

@interface FBInstrumentsOperation  ()

@property (nonatomic, strong, readonly) FBTask *task;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@end

@implementation FBInstrumentsOperation

#pragma mark Initializers

+ (FBFuture<FBInstrumentsOperation *> *)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBInstrumentsConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  // The instruments cli is unreliable and sometimes stops recording right after starting
  // To make it reliable, we retry it until it either succeeds or we timeout
  return [[FBFuture
    onQueue:target.asyncQueue resolveUntil:^ FBFuture * {
      return [self operationWithTargetInternal:target configuration:configuration logger:logger];
    }]
    timeout:InstrumentsStartupTimeout waitingFor:@"Successful instruments startup"];
}

+ (FBFuture<FBInstrumentsOperation *> *)operationWithTargetInternal:(id<FBiOSTarget>)target configuration:(FBInstrumentsConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.instruments", DISPATCH_QUEUE_SERIAL);
  NSString *fileName = [[@[configuration.instrumentName, NSUUID.UUID.UUIDString] componentsJoinedByString:@"_"] stringByAppendingPathExtension:@"trace"];
  NSString *filePath = [target.auxillaryDirectory stringByAppendingPathComponent:fileName];
  NSString *durationMilliseconds = [@(configuration.duration * 1000) stringValue];
  NSMutableArray<NSString *> *arguments = [@[@"-w", target.udid, @"-D", filePath, @"-t", configuration.instrumentName, @"-l",  durationMilliseconds, @"-v"] mutableCopy];
  if (configuration.targetApplication) {
    [arguments addObject:configuration.targetApplication];
    for (NSString *key in configuration.environment) {
      [arguments addObjectsFromArray:@[@"-e", key, configuration.environment[key]]];
    }
    [arguments addObjectsFromArray:configuration.arguments];
  }
  [logger logFormat:@"Starting instruments with arguments: %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]];
  FBInstrumentsConsumer *instrumentsConsumer = [[FBInstrumentsConsumer alloc] init];
  id<FBControlCoreLogger> instrumentsLogger = [FBControlCoreLogger loggerToConsumer:instrumentsConsumer];
  id<FBControlCoreLogger> compositeLogger = [FBControlCoreLogger compositeLoggerWithLoggers:@[logger, instrumentsLogger]];

  return [[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/instruments"]
    withArguments:arguments]
    withStdOutToLogger:compositeLogger]
    withStdErrToLogger:compositeLogger]
    start]
    // Wait a few seconds for instruments to startup. If it fails, kill it
    onQueue:target.asyncQueue fmap:^ FBFuture * (FBTask *task) {
      FBFuture *timerFuture = [[FBFuture futureWithResult:NSNull.null] delay:InstrumentsStartupDelay];
      return [[[FBFuture
        race:@[instrumentsConsumer.hasStoppedRecording, timerFuture]]
        onQueue:target.asyncQueue handleError:^ FBFuture * (NSError *error) {
          return [[task sendSignal:SIGTERM] fmapReplace:[FBFuture futureWithError:error]];
        }]
        mapReplace:task];
    }]
    // Yay instruments started properly
    onQueue:target.asyncQueue map:^ FBInstrumentsOperation * (FBTask *task) {
      [logger logFormat:@"Started Instruments %@", task];
      NSURL *traceFile = [NSURL fileURLWithPath:filePath];
      return [[FBInstrumentsOperation alloc] initWithTask:task traceFile:traceFile configuration:configuration queue:queue logger:logger];
    }];
}

- (instancetype)initWithTask:(FBTask *)task traceFile:(NSURL *)traceFile configuration:(FBInstrumentsConfiguration *)configuration queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  _traceFile = traceFile;
  _configuration = configuration;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSURL *> *)stop
{
  NSTimeInterval termTimeout = InterruptBackoffTimeout;
  return [[FBFuture
    onQueue:self.queue resolve:^{
      [self.logger logFormat:@"Terminating Instruments %@. Backoff Timeout %f", self.task, termTimeout];
      return [self.task sendSignal:SIGINT backingOfToKillWithTimeout:termTimeout];
    }]
    onQueue:self.queue map:^ NSURL * (NSNumber *exitCode) {
      [self.logger logFormat:@"Instruments exited with exitCode: %@", exitCode];
      return self.traceFile;
    }];
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeInstruments;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.task.completed mapReplace:NSNull.null];
}

@end
