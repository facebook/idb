/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorVideo.h"

#import <objc/runtime.h>

#import <FBControlCore/FBControlCore.h>

#import "FBAppleSimctlCommandExecutor.h"
#import "FBFramebufferConfiguration.h"
#import "FBSimulatorError.h"
#import "FBVideoEncoderConfiguration.h"
#import "FBVideoEncoderSimulatorKit.h"

static const NSTimeInterval SimCtlIOPollDelay = 20.0;  // Wait this long for "simctl io poll" to create IOSurface.

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
@property (nonatomic, strong, readwrite) FBFuture<FBTask<NSNull *, NSString *, NSString *> *> *recordingStarted;

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
#pragma mark Private

+ (dispatch_time_t)convertTimeIntervalToDispatchTime:(NSTimeInterval)timeInterval
{
  int64_t timeoutInt = ((int64_t) timeInterval) * ((int64_t) NSEC_PER_SEC);
  return dispatch_time(DISPATCH_TIME_NOW, timeoutInt);
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

  // Choose the Path for the Log
  filePath = filePath ?: self.configuration.filePath;

  FBTaskBuilder *recordingTaskBuilder = [[[self.simctlExecutor
    taskBuilderWithCommand:@"io"
    arguments:@[
      @"recordVideo",
      @"--type=mp4",
      filePath
    ]]
    withStdOutInMemoryAsString]
    withStdErrInMemoryAsString];

  if (!FBXcodeConfiguration.isXcode10OrGreater) {
    self.recordingStarted = [recordingTaskBuilder start];
    return [self.recordingStarted mapReplace:NSNull.null];
  }

  // In Xcode 10, we need to run "simctl io poll" to create IOSurface first
  // to make video recording work, if the simulator is launched without Simulator.app.

  NSMutableArray<NSString *> *lines = [NSMutableArray array];
  id<FBControlCoreLogger> ioPollLogger = [self.logger withName:@"simctl_io_poll"];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.simulatorvideo.simctl.io.poll", DISPATCH_QUEUE_SERIAL);

  return [[[[[[[self.simctlExecutor
    taskBuilderWithCommand:@"io"
    arguments:@[@"poll"]]
    withStdOutLineReader:^(NSString *line) {
      [ioPollLogger log:line];
      [lines addObject:line];
    }]
    withStdErrLineReader:^(NSString *line) {
      [ioPollLogger log:line];
      [lines addObject:line];
    }]
    start]
    onQueue:queue fmap:^FBFuture *(FBTask *task) {
      return [[[[FBFuture onQueue:queue resolveWhen:^BOOL{
        for (NSString *line in lines) {
          if ([line containsString:@"IOSurface changed"]) {
            return YES;
          }
        }
        return NO;
      }]
      mapReplace:task]
      timeout:SimCtlIOPollDelay
      waitingFor:@"simulator IO surface created"]
      fallback:task];
    }]
    onQueue:queue fmap:^FBFuture *(FBTask *task) {
      return [task sendSignal:SIGINT];
    }]
    onQueue:queue fmap:^FBFuture *(id _) {
      self.recordingStarted = [recordingTaskBuilder start];
      return [self.recordingStarted mapReplace:NSNull.null];
    }];
}

- (FBFuture<NSNull *> *)stopRecording
{
  // Fail early if there's no task running.
  FBFuture<FBTask<NSNull *, NSString *, NSString *> *> *recordingStarted = self.recordingStarted;
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

  // Grab the task and see if it died already.
  if (recordingTask.completed.hasCompleted) {
    [self.logger logFormat:@"Stop Recording requested, but it's completed with output '%@' '%@', perhaps the video is damaged", recordingTask.stdOut, recordingTask.stdErr];
    return [FBFuture futureWithResult:NSNull.null];
  }

  // Stop for real be interrupting the task itself.
  FBFuture<NSNull *> *completed = [[[recordingTask
    sendSignal:SIGTERM backingOfToKillWithTimeout:10]
    mapReplace:NSNull.null]
    logCompletion:self.logger withPurpose:@"The video recording task"];
  [self.completedFuture resolveFromFuture:completed];

  return completed;
}

@end
