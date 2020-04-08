/*
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

const NSTimeInterval DefaultInstrumentsOperationDuration = 60 * 60 * 4;
const NSTimeInterval DefaultInstrumentsTerminateTimeout = 600.0;
const NSTimeInterval DefaultInstrumentsLaunchErrorTimeout = 15.0;
const NSTimeInterval DefaultInstrumentsLaunchRetryTimeout = 360.0;

FBiOSTargetFutureType const FBiOSTargetFutureTypeInstruments = @"instruments";

@interface FBInstrumentsConsumer : NSObject <FBDataConsumer>

@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *hasStoppedRecording;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *hasStartedLoadingTemplate;
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
  _hasStartedLoadingTemplate = FBMutableFuture.future;
  _logs = [NSMutableArray array];
  _consumer = [FBBlockDataConsumer asynchronousLineConsumerWithBlock:^(NSString *logLine) {
    if (![logLine isEqualToString:@""]) {
      [self.logs addObject:logLine];
    }
    if ([logLine containsString:@"Loading template"]) {
      [self.hasStartedLoadingTemplate resolveWithResult:NSNull.null];
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
    timeout:configuration.timings.launchRetryTimeout waitingFor:@"successful instruments startup"];
}

+ (FBFuture<FBInstrumentsOperation *> *)operationWithTargetInternal:(id<FBiOSTarget>)target configuration:(FBInstrumentsConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.instruments", DISPATCH_QUEUE_SERIAL);
  NSString *traceDir = [target.auxillaryDirectory stringByAppendingPathComponent:[@"instruments-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
  NSError *innerError = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:traceDir withIntermediateDirectories:NO attributes:nil error:&innerError]) {
    return [[FBControlCoreError describeFormat:@"Failed to create instruments trace output directory: %@", innerError] failFuture];
  }
  NSString *traceFile = [traceDir stringByAppendingPathComponent:@"trace.trace"];

  NSString *durationMilliseconds = [@(configuration.timings.operationDuration * 1000) stringValue];
  NSMutableArray<NSString *> *arguments = [NSMutableArray new];
  if ([[configuration toolArguments] count] > 0) {
    [arguments addObjectsFromArray:[configuration toolArguments]];
  }
  [arguments addObjectsFromArray:@[@"-w", target.udid, @"-D", traceFile, @"-t", configuration.templateName, @"-l",  durationMilliseconds, @"-v"]];

  if (configuration.targetApplication && [configuration.targetApplication length] > 0) {
    [arguments addObject:configuration.targetApplication];
    for (NSString *key in configuration.appEnvironment) {
      [arguments addObjectsFromArray:@[@"-e", key, configuration.appEnvironment[key]]];
    }
    [arguments addObjectsFromArray:configuration.appArguments];
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
    onQueue:target.asyncQueue fmap:^ FBFuture * (FBTask *task) {
      return [instrumentsConsumer.hasStartedLoadingTemplate
        onQueue:target.asyncQueue fmap:^ FBFuture * (id _) {
        [logger logFormat:@"Waiting for %f seconds for instruments to start properly", configuration.timings.launchErrorTimeout];
        // Instruments profiling started correctly if timer expires before 'hasStoppedRecording' resolves.
        // This is necessary because instruments doesn't print anything when profiling has begun.
        // We detect a failure by checking for 'Instruments Trace Completed' output before launchErrorTimeout.
        FBFuture *timerFuture = [FBFuture.empty delay:configuration.timings.launchErrorTimeout];
        return [[[FBFuture
          race:@[instrumentsConsumer.hasStoppedRecording, timerFuture]]
          onQueue:target.asyncQueue handleError:^ FBFuture * (NSError *error) {
            return [[task sendSignal:SIGTERM] chainReplace:[FBFuture futureWithError:error]];
          }]
          mapReplace:task];
        }];
    }]
    // Yay instruments started properly
    onQueue:target.asyncQueue map:^ FBInstrumentsOperation * (FBTask *task) {
      [logger logFormat:@"Started instruments %@", task];

      return [[FBInstrumentsOperation alloc] initWithTask:task traceDir:[NSURL fileURLWithPath:traceFile] configuration:configuration queue:queue logger:logger];
    }];
}

- (instancetype)initWithTask:(FBTask *)task traceDir:(NSURL *)traceDir configuration:(FBInstrumentsConfiguration *)configuration queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  _traceDir = traceDir;
  _configuration = configuration;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSURL *> *)stop
{
  return [[FBFuture
    onQueue:self.queue resolve:^{
      [self.logger logFormat:@"Terminating instruments %@. Backoff Timeout %f", self.task, self.configuration.timings.terminateTimeout];
      return [self.task sendSignal:SIGINT backingOffToKillWithTimeout:self.configuration.timings.terminateTimeout logger:self.logger];
    }] chainReplace:[[self.task exitCode]
    onQueue:self.queue fmap:^FBFuture<NSURL *> *(NSNumber *exitCode) {
      if ([exitCode isEqualToNumber:@(0)]) {
        return [FBFuture futureWithResult:self.traceDir];
      } else {
        return [[FBControlCoreError describeFormat:@"Instruments exited with failure - status: %@", exitCode] failFuture];
      }
    }]
  ];
}

+ (FBFuture<NSURL *> *)postProcess:(NSArray<NSString *> *)arguments traceDir:(NSURL *)traceDir queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  if (!arguments || arguments.count == 0) {
    return [FBFuture futureWithResult:traceDir];
  }
  NSURL *outputTraceFile = [[traceDir URLByDeletingLastPathComponent] URLByAppendingPathComponent:arguments[2]];
  NSMutableArray<NSString *> *launchArguments = [@[arguments[1], traceDir.path, @"-o", outputTraceFile.path] mutableCopy];
  if (arguments.count > 3) {
    [launchArguments addObjectsFromArray:[arguments subarrayWithRange:(NSRange){3, [arguments count] - 3}]];
  }

  [logger logFormat:@"Starting post processing | Launch path: %@ | Arguments: %@", arguments[0], [FBCollectionInformation oneLineDescriptionFromArray:launchArguments]];
  return [[[[[[[[FBTaskBuilder
    withLaunchPath:arguments[0]]
    withArguments:launchArguments]
    withStdInConnected]
    withStdOutToLogger:logger]
    withStdErrToLogger:logger]
    withAcceptableTerminationStatusCodes:[NSSet setWithObject:@0]]
    runUntilCompletion]
    onQueue:queue map:^(id _) {
      return outputTraceFile;
    }];
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeInstruments;
}

- (FBFuture<NSNull *> *)completed
{
  return [[[self.task.completed
    mapReplace:NSNull.null]
    shieldCancellation]
    onQueue:self.queue respondToCancellation:^{
      return [[self stop] mapReplace:NSNull.null];
    }];
}

@end
