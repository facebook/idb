/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTask.h"
#import "FBTask+Private.h"

#import "FBTaskExecutor.h"
#import "FBRunLoopSpinner.h"

@implementation FBTask

#pragma mark Initializers

+ (instancetype)taskWithNSTask:(NSTask *)nsTask acceptableStatusCodes:(NSSet *)acceptableStatusCodes stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  FBTask *task = stdOutPath || stdErrPath
    ? [[FBTask_FileBacked alloc] initWithTask:nsTask acceptableStatusCodes:acceptableStatusCodes stdOutPath:stdOutPath stdErrPath:stdErrPath]
    : [[FBTask_InMemory alloc] initWithTask:nsTask acceptableStatusCodes:acceptableStatusCodes];
  [task decorateTask:nsTask];
  return task;
}

- (instancetype)initWithTask:(NSTask *)task acceptableStatusCodes:(NSSet *)acceptableStatusCodes
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  _acceptableStatusCodes = acceptableStatusCodes ?: [NSSet setWithObject:@0];
  return self;
}

#pragma mark - FBTerminationHandle Protocol

- (void)terminate
{
  @synchronized(self) {
    if (self.hasTerminated) {
      return;
    }

    [self teardownTask];
    [self teardownResources];
    [self completeTermination];
  }
}

#pragma mark - FBTask Protocl

#pragma mark Starting

- (instancetype)startAsynchronously
{
  return [self launchWithTerminationHandler:nil];
}

- (instancetype)startAsynchronouslyWithTerminationHandler:(void (^)(id<FBTask> task))handler
{
  return [self launchWithTerminationHandler:handler];
}

- (instancetype)startSynchronouslyWithTimeout:(NSTimeInterval)timeout
{
  [self launchWithTerminationHandler:nil];
  BOOL completed = [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:timeout untilTrue:^BOOL{
    return !self.task.isRunning;
  }];

  if (!completed) {
    NSString *message = [NSString stringWithFormat:
      @"Shell command '%@' took longer than %f seconds to execute",
      self.task,
      timeout
    ];
    self.runningError = [self errorForDescription:message];
  }

  [self terminate];
  return self;
}

- (instancetype)launchWithTerminationHandler:(void (^)(id<FBTask> task))handler
{
  self.terminationHandler = handler;
  CFRetain((__bridge CFTypeRef)(self.task));
  [self.task launch];
  return self;
}

#pragma mark Accessors

- (pid_t)processIdentifier
{
  return self.task.processIdentifier;
}

- (NSString *)stdOut
{
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (NSString *)stdErr
{
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (NSError *)error
{
  return self.runningError;
}

- (BOOL)wasSuccessful
{
  @synchronized(self)
  {
    return self.hasTerminated && self.runningError == nil;
  }
}

#pragma mark Private

- (NSTask *)decorateTask:(NSTask *)task
{
  __weak typeof(self) weakSelf = self;
  task.terminationHandler = ^(NSTask *_) {
    [weakSelf terminate];
  };
  return task;
}

- (void)teardownTask
{
  if (self.task.isRunning) {
    [self.task terminate];
    [self.task waitUntilExit];
  }
  self.task.terminationHandler = nil;
}

- (void)teardownResources
{
  [self doesNotRecognizeSelector:_cmd];
}

- (void)completeTermination
{
  if (self.runningError == nil && [self.acceptableStatusCodes containsObject:@(self.task.terminationStatus)] == NO) {
    NSString *description = [NSString stringWithFormat:@"Returned non-zero status code %d", self.task.terminationStatus];
    self.runningError = [self errorForDescription:description];
  }

  CFRelease((__bridge CFTypeRef)(self.task));
  self.hasTerminated = YES;

  void (^terminationHandler)(id<FBTask>) = self.terminationHandler;
  if (!terminationHandler) {
    return;
  }
  dispatch_async(dispatch_get_main_queue(), ^{
    terminationHandler(self);
  });
  self.terminationHandler = nil;
}

- (NSError *)errorForDescription:(NSString *)description
{
  NSParameterAssert(description);
  NSMutableDictionary *userInfo = [@{
    NSLocalizedDescriptionKey : description,
  } mutableCopy];
  if (self.stdOut) {
    userInfo[@"stdout"] = self.stdOut;
  }
  if (self.stdErr) {
    userInfo[@"stderr"] = self.stdErr;
  }

  if (self.task.isRunning) {
    userInfo[@"exitcode"] = @(self.task.terminationStatus);
  }

  return [NSError errorWithDomain:FBTaskExecutorErrorDomain code:0 userInfo:userInfo];
}

- (NSString *)description
{
  @synchronized(self) {
    return self.task.description;
  }
}

@end

@implementation FBTask_InMemory

- (instancetype)initWithTask:(NSTask *)task acceptableStatusCodes:(NSSet *)acceptableStatusCodes
{
  self = [super initWithTask:task acceptableStatusCodes:acceptableStatusCodes];
  if (!self) {
    return nil;
  }

  _stdOutData = [NSMutableData data];
  _stdErrData = [NSMutableData data];
  return self;
}

- (NSString *)stdOut
{
  @synchronized(self) {
    return [[[NSString alloc]
      initWithData:self.stdOutData encoding:NSUTF8StringEncoding]
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  }
}

- (NSString *)stdErr
{
  @synchronized(self) {
    return [[[NSString alloc]
      initWithData:self.stdErrData encoding:NSUTF8StringEncoding]
      stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
  }
}

- (NSTask *)decorateTask:(NSTask *)task
{
  __weak typeof(self) weakSelf = self;

  self.stdOutPipe = [NSPipe pipe];
  self.stdOutPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
    NSData *data = handle.availableData;
    @synchronized(weakSelf) {
      [weakSelf.stdOutData appendData:data];
    }
  };
  [task setStandardOutput:self.stdOutPipe];

  self.stdErrPipe = [NSPipe pipe];
  self.stdErrPipe.fileHandleForReading.readabilityHandler = ^(NSFileHandle *handle) {
    NSData *data = handle.availableData;
    @synchronized(weakSelf) {
      [weakSelf.stdErrData appendData:data];
    }
  };
  [task setStandardError:self.stdErrPipe];

  return [super decorateTask:task];
}

- (void)teardownResources
{
  self.stdOutPipe.fileHandleForReading.readabilityHandler = nil;
  self.stdErrPipe.fileHandleForReading.readabilityHandler = nil;
  self.stdOutPipe = nil;
  self.stdErrPipe = nil;
}

@end

@implementation FBTask_FileBacked

- (instancetype)initWithTask:(NSTask *)task acceptableStatusCodes:(NSSet *)acceptableStatusCodes stdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  self = [super initWithTask:task acceptableStatusCodes:acceptableStatusCodes];
  if (!self) {
    return nil;
  }

  _stdOutPath = stdOutPath;
  _stdErrPath = stdErrPath;
  return self;
}

- (NSString *)stdOut
{
  @synchronized(self) {
    return [NSString stringWithContentsOfFile:self.stdOutPath usedEncoding:nil error:nil];
  }
}

- (NSString *)stdErr
{
  @synchronized(self) {
    return [NSString stringWithContentsOfFile:self.stdErrPath usedEncoding:nil error:nil];
  }
}

- (NSTask *)decorateTask:(NSTask *)task
{
  if (self.stdOutPath && ![NSFileManager.defaultManager createFileAtPath:self.stdOutPath contents:nil attributes:nil]) {
    self.runningError = [self errorForDescription:[NSString stringWithFormat:@"Could not create stdout file at %@", self.stdOutPath]];
    return task;
  }
  if (self.stdErrPath && ![NSFileManager.defaultManager createFileAtPath:self.stdErrPath contents:nil attributes:nil]) {
    self.runningError = [self errorForDescription:[NSString stringWithFormat:@"Could not create stdErr file at %@", self.stdErrPath]];
    return task;
  }

  self.stdOutFileHandle = self.stdOutPath ? [NSFileHandle fileHandleForWritingAtPath:self.stdOutPath] : NSFileHandle.fileHandleWithNullDevice;
  task.standardOutput = self.stdOutFileHandle;
  self.stdErrFileHandle = self.stdErrPath ? [NSFileHandle fileHandleForWritingAtPath:self.stdErrPath] : NSFileHandle.fileHandleWithNullDevice;
  task.standardError = self.stdErrFileHandle;

  return [super decorateTask:task];
}

- (void)teardownResources
{
  [self.stdOutFileHandle closeFile];
  self.stdOutFileHandle = nil;
  [self.stdErrFileHandle closeFile];
  self.stdErrFileHandle = nil;
}

@end
