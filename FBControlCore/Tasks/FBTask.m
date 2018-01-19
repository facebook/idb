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
#import "FBControlCoreLogger.h"
#import "FBFileConsumer.h"
#import "FBFileWriter.h"
#import "FBLaunchedProcess.h"
#import "FBProcessOutput.h"
#import "FBTaskConfiguration.h"
#import "NSRunLoop+FBControlCore.h"

NSString *const FBTaskErrorDomain = @"com.facebook.FBControlCore.task";

@protocol FBTaskProcess <NSObject>

@property (nonatomic, assign, readonly) int terminationStatus;
@property (nonatomic, assign, readonly) BOOL isRunning;

- (FBLaunchedProcess *)launch;
- (void)mountStandardOut:(id)stdOut;
- (void)mountStandardErr:(id)stdErr;
- (void)mountStandardIn:(id)stdIn;
- (void)terminate;

@end

@interface FBTaskProcess_NSTask : NSObject <FBTaskProcess>

@property (nonatomic, strong, readwrite) NSTask *task;

@end

@implementation FBTaskProcess_NSTask

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

- (FBLaunchedProcess *)launch
{
  FBMutableFuture<NSNumber *> *exitCode = [FBMutableFuture future];
  self.task.terminationHandler = ^(NSTask *task) {
    [exitCode resolveWithResult:@(task.terminationStatus)];
  };
  [self.task launch];
  return [[FBLaunchedProcess alloc] initWithProcessIdentifier:self.task.processIdentifier exitCode:exitCode];
}

- (void)terminate
{
  [self.task terminate];
  [self.task waitUntilExit];
  self.task.terminationHandler = nil;
}

@end

@interface FBTask ()

@property (nonatomic, strong, readonly) dispatch_queue_t queue;
@property (nonatomic, copy, readonly) NSSet<NSNumber *> *acceptableStatusCodes;

@property (nonatomic, strong, nullable, readwrite) id<FBTaskProcess> process;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput *stdOutSlot;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput *stdErrSlot;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput<id<FBFileConsumer>> *stdInSlot;
@property (nonatomic, strong, nullable, readwrite) FBLaunchedProcess *launchedProcess;

@property (nonatomic, copy, readwrite) NSString *configurationDescription;
@property (nonatomic, strong, readonly) FBMutableFuture<NSNumber *> *terminationStatusFuture;
@property (nonatomic, strong, readonly) FBMutableFuture *errorFuture;

@property (atomic, assign, readwrite) BOOL completedTeardown;

@end

@implementation FBTask

#pragma mark Initializers

+ (FBProcessOutput *)createTaskOutput:(id)output
{
  if (!output) {
    return nil;
  }
  if ([output isKindOfClass:NSURL.class]) {
    return [FBProcessOutput outputForFilePath:[output path]];
  }
  if ([output conformsToProtocol:@protocol(FBFileConsumer)]) {
    return [FBProcessOutput outputForFileConsumer:output];
  }
  if ([output conformsToProtocol:@protocol(FBControlCoreLogger)]) {
    return [FBProcessOutput outputForLogger:output];
  }
  if ([output isKindOfClass:NSData.class]) {
    return [FBProcessOutput outputToMutableData:NSMutableData.data];
  }
  if ([output isKindOfClass:NSString.class]) {
    return [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  }
  NSAssert(NO, @"Unexpected output type %@", output);
  return nil;
}

+ (FBProcessOutput<id<FBFileConsumer>> *)createTaskInput:(BOOL)connectStdIn
{
  if (!connectStdIn) {
    return nil;
  }
  return FBProcessOutput.inputProducingConsumer;
}

+ (FBFuture<FBTask *> *)startTaskWithConfiguration:(FBTaskConfiguration *)configuration
{
  id<FBTaskProcess> process = [FBTaskProcess_NSTask fromConfiguration:configuration];
  FBProcessOutput *stdOut = [self createTaskOutput:configuration.stdOut];
  FBProcessOutput *stdErr = [self createTaskOutput:configuration.stdErr];
  FBProcessOutput<id<FBFileConsumer>> *stdIn = [self createTaskInput:configuration.connectStdIn];
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.task", DISPATCH_QUEUE_SERIAL);
  FBTask *task = [[self alloc] initWithProcess:process stdOut:stdOut stdErr:stdErr stdIn:stdIn queue:queue acceptableStatusCodes:configuration.acceptableStatusCodes configurationDescription:configuration.description];
  return [task launchTask];
}

- (instancetype)initWithProcess:(id<FBTaskProcess>)process stdOut:(FBProcessOutput *)stdOut stdErr:(FBProcessOutput *)stdErr stdIn:(FBProcessOutput<id<FBFileConsumer>> *)stdIn queue:(dispatch_queue_t)queue acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes configurationDescription:(NSString *)configurationDescription
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

  _terminationStatusFuture = [FBMutableFuture future];
  _errorFuture = [FBMutableFuture future];

  return self;
}

#pragma mark Accessors

- (FBFuture<NSNumber *> *)completed
{
  FBFuture<NSNumber *> *completed = [FBFuture race:@[
    self.terminationStatusFuture,
    self.errorFuture,
  ]];
  return [completed onQueue:self.queue respondToCancellation:^FBFuture<NSNull *> *{
    [self terminate];
    return [FBFuture futureWithResult:NSNull.null];
  }];
}

- (FBFuture<NSNumber *> *)exitCode
{
  return self.terminationStatusFuture;
}

- (pid_t)processIdentifier
{
  @synchronized(self) {
    return self.launchedProcess ? self.launchedProcess.processIdentifier : -1;
  }
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

- (nullable NSError *)error
{
  return self.errorFuture.error;
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
      // Since the FBTask may not be returned by anyone and is asynchronous, it needs to be retained.
      // This Retain is matched by a release in -[FBTask completeTermination].
      CFRetain((__bridge CFTypeRef)(self));

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

      self.launchedProcess = [self.process launch];
      [self.launchedProcess.exitCode onQueue:self.queue notifyOfCompletion:^(FBFuture<NSNumber *> *future) {
        [self.terminationStatusFuture resolveFromFuture:future];
        [self terminateWithErrorMessage:future.error.localizedDescription];
      }];

      return self;
    }];
}

- (void)terminate
{
  [self terminateWithErrorMessage:nil];
}

- (instancetype)terminateWithErrorMessage:(nullable NSString *)errorMessage
{
  @synchronized(self) {
    if (errorMessage) {
      [self.errorFuture resolveWithError:[self errorForMessage:errorMessage]];
    }
    if (self.completedTeardown) {
      return self;
    }

    [self teardownProcess];
    [self teardownResources];
    [self completeTermination];
    self.completedTeardown = YES;
    return self;
  }
}

- (void)teardownProcess
{
  if (self.process.isRunning) {
    [self.process terminate];
  }
}

- (void)teardownResources
{
  [self.stdOutSlot detach];
  [self.stdErrSlot detach];
  [self.stdInSlot detach];
}

- (void)completeTermination
{
  NSAssert(self.process.isRunning == NO, @"Process should be terminated before calling completeTermination");
  if ([self.acceptableStatusCodes containsObject:@(self.process.terminationStatus)] == NO) {
    NSError *error = [self errorForMessage:[NSString stringWithFormat:@"Returned non-zero status code %d", self.process.terminationStatus]];
    [self.errorFuture resolveWithError:error];
  }

  // Matches the release in -[FBTask launchWithTerminationHandler:].
  CFRelease((__bridge CFTypeRef)(self));
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
