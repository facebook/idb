/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorVideo.h"

#import <objc/runtime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAppleSimctlCommandExecutor.h"
#import "FBSimulatorError.h"

@interface FBSimulatorVideo ()

@property (nonatomic, copy, readonly) NSString *filePath;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *completedFuture;

- (instancetype)initWithFilePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBSimulatorVideo_SimCtl : FBSimulatorVideo

@property (nonatomic, strong, readonly) FBAppleSimctlCommandExecutor *simctlExecutor;
@property (nonatomic, strong, nullable, readwrite) FBFuture<FBProcess<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *> *recordingStarted;

- (instancetype)initWithWithSimctlExecutor:(FBAppleSimctlCommandExecutor *)simctlExecutor filePath:(NSString *)filePath  logger:(id<FBControlCoreLogger>)logger;

@end

@implementation FBSimulatorVideo

#pragma mark Initializers

+ (instancetype)videoWithSimctlExecutor:(FBAppleSimctlCommandExecutor *)simctlExecutor filePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger
{
  return [[FBSimulatorVideo_SimCtl alloc] initWithWithSimctlExecutor:simctlExecutor filePath:filePath logger:logger];
}

- (instancetype)initWithFilePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _filePath = filePath;
  _logger = logger;
  _queue = dispatch_queue_create("com.facebook.simulatorvideo.simctl", DISPATCH_QUEUE_SERIAL);

  _completedFuture = FBMutableFuture.future;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSNull *> *)startRecording
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBFuture<NSNull *> *)stopRecording
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBiOSTargetOperation

- (FBFuture<NSNull *> *)completed
{
  return [self.completedFuture onQueue:self.queue respondToCancellation:^{
    return [self stopRecording];
  }];
}

@end

@implementation FBSimulatorVideo_SimCtl

- (instancetype)initWithWithSimctlExecutor:(FBAppleSimctlCommandExecutor *)simctlExecutor filePath:(NSString *)filePath logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithFilePath:filePath logger:logger];
  if (!self) {
    return nil;
  }

  _simctlExecutor = simctlExecutor;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)startRecording
{
  // Fail early if there's a task running.
  if (self.recordingStarted) {
    return [[FBSimulatorError
      describe:@"Cannot Start Recording, there is already an recording task running"]
      failFuture];
  }

  self.recordingStarted = [[self
    simctlVersionNumber]
    onQueue:self.queue fmap:^(NSDecimalNumber *simctlVersion) {
      // Earlier versions use --type=codec instead of --type, so we need to switch on the version of simctl
      NSArray<NSString *> *recordVideoParameters = @[@"--type=mp4"];
      if ([simctlVersion isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"681.14"]]) {
        recordVideoParameters = @[@"--codec=h264", @"--force"];
      }

      NSArray<NSString *> *ioCommandArguments = [[@[@"recordVideo"]
        arrayByAddingObjectsFromArray:recordVideoParameters]
        arrayByAddingObject:self.filePath];

      return [[[[[self.simctlExecutor
        taskBuilderWithCommand:@"io" arguments:ioCommandArguments]
        withStdOutToLogger:self.logger]
        withStdErrToLogger:self.logger]
        withTaskLifecycleLoggingTo:self.logger]
        start];
    }];

  return [self.recordingStarted mapReplace:NSNull.null];
}

static NSTimeInterval const recordingTaskWaitTimeout = 10.0;

- (FBFuture<NSNull *> *)stopRecording
{
  // Fail early if there's no task running.
  FBFuture<FBProcess<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *> *recordingStarted = self.recordingStarted;
  if (!recordingStarted) {
    return [[FBSimulatorError
      describe:@"Cannot Stop Recording, there is no recording task started"]
      failFuture];
  }
  FBProcess<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *recordingTask = recordingStarted.result;
  if (!recordingTask) {
    return [[FBSimulatorError
      describe:@"Cannot Stop Recording, the recording task hasn't started"]
      failFuture];
  }

  // Grab the task and see if it died already.
  if (recordingTask.statLoc.hasCompleted) {
    [self.logger logFormat:@"Stop Recording requested, but it's completed with output '%@' '%@', perhaps the video is damaged", recordingTask.stdOut, recordingTask.stdErr];
    return FBFuture.empty;
  }

  // Stop for real be interrupting the task itself.
  FBFuture<NSNull *> *completed = [[[[recordingTask
    sendSignal:SIGINT backingOffToKillWithTimeout:recordingTaskWaitTimeout logger:self.logger]
    logCompletion:self.logger withPurpose:@"The video recording task terminated"]
    onQueue:self.queue fmap:^(NSNumber *result) {
      self.recordingStarted = nil;
      return [FBSimulatorVideo_SimCtl confirmFileHasBeenWritten:self.filePath queue:self.queue logger:self.logger];
    }]
    onQueue:self.queue handleError:^(NSError *error) {
      [self.logger logFormat:@"Failed confirm video file been written %@", error];
      return [FBFuture futureWithResult:NSNull.null];
    }];

  [self.completedFuture resolveFromFuture:completed];

  return completed;
}

#pragma mark Private

static NSTimeInterval const SimctlResolveFileTimeout = 10;

// simctl, may exit before the underlying video file has been written out to disk.
// This is unfortunate as we can't guarantee that video file is valid until this happens.
// Therefore, we must check (with some timeout) for the existence of the file on disk.
// It's not simply enough to check that the file exists, we must also check that it has a nonzero size.
// The reason for this is that simctl itself (since Xcode 10) isn't doing the writing, this is instead delegated to SimStreamProcessorService.
// Since this writing is asynchronous with simctl, it's possible that it isn't written out when simctl has terminated.
+ (FBFuture<NSNull *> *)confirmFileHasBeenWritten:(NSString *)filePath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[FBFuture
    onQueue:queue resolveWhen:^{
      NSDictionary<NSString *, id> *fileAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:filePath error:nil];
      NSUInteger fileSize = [fileAttributes[NSFileSize] unsignedIntegerValue];
      if (fileSize > 0) {
        [logger logFormat:@"simctl has written out the video to %@ with file size %lu", filePath, fileSize];
        return YES;
      }
      return NO;
    }]
    timeout:SimctlResolveFileTimeout waitingFor:@"simctl to write file to %@", filePath];
}

- (FBFuture<NSDecimalNumber *> *)simctlVersionNumber
{
  return [[[[[[FBProcessBuilder
    withLaunchPath:@"/usr/bin/what"
    arguments:@[@"/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl"]]
    withStdOutInMemoryAsString]
    withStdErrToDevNull]
    runUntilCompletionWithAcceptableExitCodes:nil]
    onQueue:self.queue fmap:^(FBProcess<NSNull *, NSString *, NSNull *> *task) {
      NSString *output = task.stdOut;
      NSString *pattern = @"CoreSimulator-([0-9\\.]+)";
      NSRegularExpression* regex = [NSRegularExpression
        regularExpressionWithPattern:pattern
        options:0
        error:nil];

      NSArray* matches = [regex
        matchesInString:output
        options:0
        range:NSMakeRange(0, output.length)];

      // Some versions can output information twice, pick the first one
      if (matches.count < 1) {
        [self.logger logFormat:@"Couldn't find simctl version from: %@, return 0.0", output];
        return [FBFuture futureWithResult:NSDecimalNumber.zero];
      }
      NSTextCheckingResult *match = matches[0];
      NSString *result = [output substringWithRange:[match rangeAtIndex:1]];

      return [FBFuture futureWithResult:[NSDecimalNumber decimalNumberWithString:result]];
    }]
    onQueue:self.queue handleError:^(NSError *error) {
      [self.logger logFormat:@"Abnormal exit of 'what' process %@, assuming version 0.0", error];
      return [FBFuture futureWithResult:NSDecimalNumber.zero];
    }];
}

@end
