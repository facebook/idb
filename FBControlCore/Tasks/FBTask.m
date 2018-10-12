/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTask.h"

#import "FBControlCoreError.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBFileConsumer.h"
#import "FBFileWriter.h"
#import "FBLaunchedProcess.h"
#import "FBProcessStream.h"
#import "FBTaskConfiguration.h"
#import "NSRunLoop+FBControlCore.h"

NSString *const FBTaskErrorDomain = @"com.facebook.FBControlCore.task";

@protocol FBTaskProcess <NSObject, FBLaunchedProcess>

@property (nonatomic, assign, readonly) int terminationStatus;
@property (nonatomic, assign, readonly) BOOL isRunning;

- (void)launch;
- (void)mountStandardOut:(id)stdOut;
- (void)mountStandardErr:(id)stdErr;
- (void)mountStandardIn:(id)stdIn;
- (FBFuture<NSNumber *> *)sendSignal:(int)signo;

@end

@interface FBTaskProcess_NSTask : NSObject <FBTaskProcess>

@property (nonatomic, strong, readwrite) NSTask *task;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBTaskProcess_NSTask

@synthesize exitCode = _exitCode;

+ (instancetype)fromConfiguration:(FBTaskConfiguration *)configuration
{
  NSTask *task = [[NSTask alloc] init];
  task.environment = configuration.environment;
  task.launchPath = configuration.launchPath;
  task.arguments = configuration.arguments;
  return [[self alloc] initWithTask:task];
}

- (instancetype)initWithTask:(NSTask *)task
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  _exitCode = FBMutableFuture.future;
  _logger = [[FBControlCoreGlobalConfiguration defaultLogger] withName:[NSString stringWithFormat:@"FBTask_%@", [task.launchPath lastPathComponent]]];

  return self;
}

- (pid_t)processIdentifier
{
  return self.task.processIdentifier;
}

- (int)terminationStatus
{
  return self.task.terminationStatus;
}

- (BOOL)isRunning
{
  return self.task.isRunning;
}

- (void)mountStandardOut:(id)stdOut
{
  self.task.standardOutput = stdOut;
}

- (void)mountStandardErr:(id)stdErr
{
  self.task.standardError = stdErr;
}

- (void)mountStandardIn:(id)stdIn
{
  self.task.standardInput = stdIn;
}

- (void)launch
{
  FBMutableFuture<NSNumber *> *exitCode = (FBMutableFuture *) self.exitCode;
  id<FBControlCoreLogger> logger = self.logger;
  self.task.terminationHandler = ^(NSTask *task) {
    if (logger.level >= FBControlCoreLogLevelDebug) {
      [logger logFormat:@"Task finished with exit code %d", task.terminationStatus];
    }
    [exitCode resolveWithResult:@(task.terminationStatus)];
  };

  NSString *arguments = [self.task.arguments componentsJoinedByString:@" "];
  if (logger.level >= FBControlCoreLogLevelDebug) {
    [self.logger logFormat:@"Running %@ %@ with environment %@",
      self.task.launchPath,
      arguments,
      self.task.environment];
  }
  [self.task launch];
}

- (FBFuture<NSNumber *> *)sendSignal:(int)signo
{
  pid_t processIdentifier = self.processIdentifier;
  switch (signo) {
    case SIGTERM:
      [self.task terminate];
      break;
    case SIGINT:
      [self.task interrupt];
      break;
    default:
      kill(processIdentifier, signo);
      break;
  }
  return self.exitCode;
}

@end

@interface FBTask ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, copy, readonly) NSSet<NSNumber *> *acceptableStatusCodes;

@property (nonatomic, strong, nullable, readwrite) id<FBTaskProcess> process;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput *stdOutSlot;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput *stdErrSlot;
@property (nonatomic, strong, nullable, readwrite) FBProcessInput *stdInSlot;

@property (nonatomic, copy, readwrite) NSString *configurationDescription;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *errorFuture;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *startedTeardownFuture;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNull *> *completedTeardownFuture;

@end

@implementation FBTask

#pragma mark Initializers

+ (FBFuture<FBTask *> *)startTaskWithConfiguration:(FBTaskConfiguration *)configuration
{
  id<FBTaskProcess> process = [FBTaskProcess_NSTask fromConfiguration:configuration];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task", DISPATCH_QUEUE_SERIAL);
  FBTask *task = [[self alloc] initWithProcess:process stdOut:configuration.stdOut stdErr:configuration.stdErr stdIn:configuration.stdIn queue:queue acceptableStatusCodes:configuration.acceptableStatusCodes configurationDescription:configuration.description];
  return [task launchTask];
}

- (instancetype)initWithProcess:(id<FBTaskProcess>)process stdOut:(FBProcessOutput *)stdOut stdErr:(FBProcessOutput *)stdErr stdIn:(FBProcessInput *)stdIn queue:(dispatch_queue_t)queue acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes configurationDescription:(NSString *)configurationDescription
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _process = process;
  _acceptableStatusCodes = acceptableStatusCodes;
  _stdOutSlot = stdOut;
  _stdErrSlot = stdErr;
  _stdInSlot = stdIn;
  _queue = queue;
  _configurationDescription = configurationDescription;
  _errorFuture = FBMutableFuture.future;
  _startedTeardownFuture = FBMutableFuture.future;
  _completedTeardownFuture = FBMutableFuture.future;

  _completed = [[[FBFuture race:@[
      [FBMutableFuture.future resolveFromFuture:process.exitCode],
      _errorFuture,
    ]]
    onQueue:self.queue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *future) {
      return [[self
        terminateWithErrorMessage:future.error.localizedDescription]
        fmapReplace:future];
    }]
    onQueue:self.queue respondToCancellation:^FBFuture<NSNull *> *{
      return [self terminateWithErrorMessage:@"Execution was cancelled"];
    }];

  return self;
}

#pragma mark Public Methods

- (FBFuture *)sendSignal:(int)signo
{
  return [FBFuture
    onQueue:self.queue resolve:^{
      return [self.process sendSignal:signo];
    }];
}

#pragma mark Accessors

- (FBFuture<NSNumber *> *)exitCode
{
  return self.process.exitCode;
}

- (pid_t)processIdentifier
{
  return self.process.processIdentifier;
}

- (nullable id)stdOut
{
  return [self.stdOutSlot contents];
}

- (nullable id)stdErr
{
  return [self.stdErrSlot contents];
}

- (nullable id)stdIn
{
  return [self.stdInSlot contents];
}

#pragma mark Private

- (FBFuture<FBTask *> *)launchTask
{
  return [[FBFuture
    futureWithFutures:@[
      [self.stdInSlot attachToPipeOrFileHandle] ?: [FBFuture futureWithResult:NSNull.null],
      [self.stdOutSlot attachToPipeOrFileHandle] ?: [FBFuture futureWithResult:NSNull.null],
      [self.stdErrSlot attachToPipeOrFileHandle] ?: [FBFuture futureWithResult:NSNull.null],
    ]]
    onQueue:self.queue map:^(NSArray<id> *pipes) {
      // Mount all the relevant std streams.
      id stdIn = pipes[0];
      if ([stdIn isKindOfClass:NSFileHandle.class] || [stdIn isKindOfClass:NSPipe.class]) {
        [self.process mountStandardIn:stdIn];
      }
      id stdOut = pipes[1];
      if ([stdOut isKindOfClass:NSFileHandle.class] || [stdOut isKindOfClass:NSPipe.class]) {
        [self.process mountStandardOut:stdOut];
      }
      id stdErr = pipes[2];
      if ([stdErr isKindOfClass:NSFileHandle.class] || [stdErr isKindOfClass:NSPipe.class]) {
        [self.process mountStandardErr:stdErr];
      }

      // Everything is setup, launch the process now.
      [self.process launch];

      return self;
    }];
}

- (FBFuture<NSNull *> *)terminateWithErrorMessage:(nullable NSString *)errorMessage
{
  if (self.completedTeardownFuture.hasCompleted && !self.startedTeardownFuture.hasCompleted) {
    return [[FBControlCoreError
      describeFormat:@"Cannot call %@ as teardown is in progress", NSStringFromSelector(_cmd)]
      failFuture];
  }
  if (errorMessage) {
    [self.errorFuture resolveWithError:[self errorForMessage:errorMessage]];
  }
  if (self.completedTeardownFuture.hasCompleted) {
    return [FBFuture futureWithResult:NSNull.null];
  }

  [self.startedTeardownFuture resolveWithResult:NSNull.null];
  return [[[self
    teardownProcess]
    onQueue:self.queue fmap:^(NSNumber *exitCode) {
      if (![self.acceptableStatusCodes containsObject:exitCode]) {
        NSError *error = [self errorForMessage:[NSString stringWithFormat:@"Returned non-zero status code %d", self.process.terminationStatus]];
        [self.errorFuture resolveWithError:error];
      }
      return [self teardownResources];
    }]
    onQueue:self.queue chain:^(id _) {
      [self.completedTeardownFuture resolveWithResult:NSNull.null];
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

- (FBFuture<NSNumber *> *)teardownProcess
{
  if (self.process.isRunning) {
    return [self.process sendSignal:SIGTERM];
  }
  return self.process.exitCode;
}

- (FBFuture<NSNull *> *)teardownResources
{
  return [[FBFuture
    futureWithFutures:@[
      [self.stdOutSlot detach] ?: [FBFuture futureWithResult:NSNull.null],
      [self.stdErrSlot detach] ?: [FBFuture futureWithResult:NSNull.null],
      [self.stdInSlot detach] ?: [FBFuture futureWithResult:NSNull.null],
    ]]
    mapReplace:NSNull.null];
}

- (NSError *)errorForMessage:(NSString *)errorMessage
{
  FBControlCoreError *error = [[[[[FBControlCoreError
    describe:errorMessage]
    inDomain:FBTaskErrorDomain]
    extraInfo:@"stdout" value:self.stdOut]
    extraInfo:@"stderr" value:self.stdErr]
    extraInfo:@"pid" value:@(self.processIdentifier)];

  if (self.exitCode.state == FBFutureStateDone) {
    [error extraInfo:@"exitcode" value:self.exitCode.result];
  }
  return [error build];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString
    stringWithFormat:@"%@ | State %@",
    self.configurationDescription,
    self.completed
  ];
}

@end
