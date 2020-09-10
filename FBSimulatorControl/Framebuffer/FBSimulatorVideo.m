/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorVideo.h"

#import <objc/runtime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAppleSimctlCommandExecutor.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulatorError.h"
#import "FBVideoEncoderConfiguration.h"
#import "FBVideoEncoderSimulatorKit.h"

@interface FBSimulatorVideo ()

@property (nonatomic, strong, readonly) FBVideoEncoderConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) dispatch_queue_t queue;

@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *completedFuture;


@end

@interface FBSimulatorVideo_SimulatorKit : FBSimulatorVideo

@property (nonatomic, strong, readonly) FBFramebuffer *framebuffer;
@property (nonatomic, strong, readwrite) FBVideoEncoderSimulatorKit *encoder;

- (instancetype)initWithConfiguration:(FBVideoEncoderConfiguration *)configuration framebuffer:(FBFramebuffer *)framebuffer logger:(id<FBControlCoreLogger>)logger;

@end

@interface FBSimulatorVideo_SimCtl : FBSimulatorVideo

@property (nonatomic, strong, readonly) FBAppleSimctlCommandExecutor *simctlExecutor;
@property (nonatomic, strong, nullable, readwrite) FBFuture<FBTask<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *> *recordingStarted;
@property (nonatomic, copy, nullable, readwrite) NSString *filePath;

- (instancetype)initWithWithSimctlExecutor:(FBAppleSimctlCommandExecutor *)simctlExecutor logger:(id<FBControlCoreLogger>)logger;

@end

@implementation FBSimulatorVideo

#pragma mark Initializers

+ (instancetype)videoWithConfiguration:(FBVideoEncoderConfiguration *)configuration framebuffer:(FBFramebuffer *)framebuffer logger:(id<FBControlCoreLogger>)logger
{
  return [[FBSimulatorVideo_SimulatorKit alloc] initWithConfiguration:configuration framebuffer:framebuffer logger:logger];
}

+ (instancetype)videoWithSimctlExecutor:(FBAppleSimctlCommandExecutor *)simctlExecutor logger:(id<FBControlCoreLogger>)logger
{
  return [[FBSimulatorVideo_SimCtl alloc] initWithWithSimctlExecutor:simctlExecutor logger:logger];
}

- (instancetype)initWithConfiguration:(FBVideoEncoderConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _logger = logger;
  _queue = dispatch_queue_create("com.facebook.simulatorvideo.simctl", DISPATCH_QUEUE_SERIAL);

  _completedFuture = FBMutableFuture.future;


  return self;
}

#pragma mark Public Methods

- (FBFuture<FBSimulatorVideo *> *)startRecordingToFile:(nullable NSString *)filePath
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (FBFuture<FBSimulatorVideo *> *)stopRecording
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark FBiOSTargetContinuation

- (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeVideoRecording;
}

- (FBFuture<NSNull *> *)completed
{
  return [self.completedFuture onQueue:self.queue respondToCancellation:^{
    return [self stopRecording];
  }];
}

@end

@implementation FBSimulatorVideo_SimulatorKit

- (instancetype)initWithConfiguration:(FBVideoEncoderConfiguration *)configuration framebuffer:(FBFramebuffer *)framebuffer logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:configuration logger:logger];
  if (!self) {
    return nil;
  }

  _framebuffer = framebuffer;

  BOOL pendingStart = (configuration.options & FBVideoEncoderOptionsAutorecord) == FBVideoEncoderOptionsAutorecord;
  if (pendingStart) {
    [self startRecordingToFile:nil];
  }

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)startRecordingToFile:(NSString *)filePath
{
  if (self.encoder) {
    return [[FBSimulatorError
      describe:@"Cannot Start Recording, there is already an active encoder"]
      failFuture];
  }
  // Choose the Path for the Log
  NSString *path = filePath ?: self.configuration.filePath;

  // Create and start the encoder.
  self.encoder = [FBVideoEncoderSimulatorKit encoderWithFramebuffer:self.framebuffer videoPath:path logger:self.logger];
  FBFuture<NSNull *> *future = [self.encoder startRecording];

  return future;
}

- (FBFuture<NSNull *> *)stopRecording
{
  if (!self.encoder) {
    return [[FBSimulatorError
      describe:@"Cannot Stop Recording, there is no active encoder"]
      failFuture];
  }

  // Stop and release the encoder
  FBFuture *future = [self.encoder stopRecording];
  dispatch_queue_t queue = [self.encoder mediaQueue];
  self.encoder = nil;
  return [future onQueue:queue notifyOfCompletion:^(id _) {
    [self.completedFuture resolveWithResult:NSNull.null];
  }];
}

@end

@implementation FBSimulatorVideo_SimCtl

- (instancetype)initWithWithSimctlExecutor:(FBAppleSimctlCommandExecutor *)simctlExecutor logger:(id<FBControlCoreLogger>)logger
{
  self = [super initWithConfiguration:FBVideoEncoderConfiguration.defaultConfiguration logger:logger];
  if (!self) {
    return nil;
  }

  _simctlExecutor = simctlExecutor;

  return self;
}

#pragma mark Public

- (FBFuture<NSNull *> *)startRecordingToFile:(NSString *)filePath
{
  // Fail early if there's a task running.
  if (self.recordingStarted) {
    return [[FBSimulatorError
      describe:@"Cannot Start Recording, there is already an recording task running"]
      failFuture];
  }

  self.recordingStarted = [[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/what"
    arguments:@[@"/Library/Developer/PrivateFrameworks/CoreSimulator.framework/Versions/A/Resources/bin/simctl"]]
    runUntilCompletion]
    onQueue:self.queue handleError:^(NSError *error) {
      [self.logger logFormat:@"Abnormal exit of what process %@", error];
      return [FBFuture futureWithResult:NSNull.null];
    }]
    onQueue:self.queue fmap:^(FBTask *task) {
      if ([task isKindOfClass:[NSNull class]]) {
        [self.logger logFormat:@"what command failed, return 0.0"];
        return [FBFuture futureWithResult:@"0.0"];
      }

      NSString *output = [task stdOut];
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
        return [FBFuture futureWithResult:@"0.0"];
      }
      NSTextCheckingResult *match = matches[0];
      NSString *result = [output substringWithRange:[match rangeAtIndex:1]];

      return [FBFuture futureWithResult:result];
    }]
    onQueue:self.queue fmap:^(NSString *simctlVersion) {
      // Earlier versions use --type=codec instead of --type, so we need to switch on the version of simctl
      NSDecimalNumber *simctlVersionNumber = [NSDecimalNumber decimalNumberWithString:simctlVersion];
      NSArray<NSString *> *recordVideoParameters = @[@"--type=mp4"];
      if ([simctlVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"681.14"]]) {
        recordVideoParameters = @[@"--codec=h264", @"--force"];
      }

      NSArray<NSString *> *ioCommandArguments = [[@[@"recordVideo"]
        arrayByAddingObjectsFromArray:recordVideoParameters]
        arrayByAddingObject:filePath];

      return [[[[self.simctlExecutor
        taskBuilderWithCommand:@"io" arguments:ioCommandArguments]
        withStdOutToLogger:self.logger]
        withStdErrToLogger:self.logger]
        start];
    }];

  self.filePath = filePath;

  return [self.recordingStarted mapReplace:NSNull.null];
}

- (FBFuture<NSNull *> *)stopRecording
{
  // Fail early if there's no task running.
  FBFuture<FBTask<NSNull *, id<FBControlCoreLogger>, id<FBControlCoreLogger>> *> *recordingStarted = self.recordingStarted;
  if (!recordingStarted) {
    return [[FBSimulatorError
      describe:@"Cannot Stop Recording, there is no recording task started"]
      failFuture];
  }
  FBTask *recordingTask = recordingStarted.result;
  if (!recordingTask) {
    return [[FBSimulatorError
      describe:@"Cannot Stop Recording, the recording task hasn't started"]
      failFuture];
  }
  NSString *filePath = self.filePath;
  self.filePath = nil;

  // Grab the task and see if it died already.
  if (recordingTask.completed.hasCompleted) {
    [self.logger logFormat:@"Stop Recording requested, but it's completed with output '%@' '%@', perhaps the video is damaged", recordingTask.stdOut, recordingTask.stdErr];
    return FBFuture.empty;
  }

  NSTimeInterval recordingTaskWaitTimeout = 10.0;
  NSString *recordingTaskWaitTimeoutFromEnv = NSProcessInfo.processInfo.environment[@"FBXCTEST_VIDEO_RECORDING_SIGINT_WAIT_TIMEOUT"];
  if (recordingTaskWaitTimeoutFromEnv) {
    recordingTaskWaitTimeout = recordingTaskWaitTimeoutFromEnv.floatValue;
  }

  // Stop for real be interrupting the task itself.
  FBFuture<NSNull *> *completed = [[[[recordingTask
    sendSignal:SIGINT backingOffToKillWithTimeout:recordingTaskWaitTimeout logger:self.logger]
    logCompletion:self.logger withPurpose:@"The video recording task terminated"]
    onQueue:self.queue fmap:^(NSNumber *result) {
      self.recordingStarted = nil;
      return [FBSimulatorVideo_SimCtl confirmFileHasBeenWritten:filePath queue:self.queue];
    }]
    onQueue:self.queue handleError:^(NSError *error) {
      [self.logger logFormat:@"Failed confirm video file been written %@", error];
      return [FBFuture futureWithResult:NSNull.null];
    }];

  [self.completedFuture resolveFromFuture:completed];

  return completed;
}

static NSTimeInterval const SimctlResolveFileTimeout = 10;

// simctl, may exit before the underlying video file has been written out to disk.
// This is unfortunate as we can't guarantee that video file is valid until this happens.
// Therefore, we must check (with some timeout) for the existence of the file on disk.
// It's not simply enough to check that the file exists, we must also check that it has a nonzero size.
// The reason for this is that simctl itself (since Xcode 10) isn't doing the writing, this is instead delegated to SimStreamProcessorService.
// Since this writing is asynchronous with simctl, it's possible that it isn't written out when simctl has terminated.
+ (FBFuture<NSNull *> *)confirmFileHasBeenWritten:(NSString *)filePath queue:(dispatch_queue_t)queue
{
  return [[FBFuture
    onQueue:queue resolveWhen:^{
      NSDictionary<NSString *, id> *fileAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:filePath error:nil];
      NSUInteger fileSize = [fileAttributes[NSFileSize] unsignedIntegerValue];
      if (fileSize > 0) {
        return YES;
      }
      return NO;
    }]
    timeout:SimctlResolveFileTimeout waitingFor:@"simctl to write file to %@", filePath];
}

@end
