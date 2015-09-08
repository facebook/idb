/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTaskExecutor.h"

#import "NSRunLoop+SimulatorControlAdditions.h"

NSString *const FBTaskExecutorErrorDomain = @"com.facebook.fbsimulatorcontrol.task";

/**
 The name of the shell executable file to execute shell commands.
 */
static NSString *const FBTaskShellExecutablePath = @"/bin/sh";

/**
 The default timeout for synchronous command waits
 */
static NSTimeInterval const FBTaskDefaultTimeout = 30;

@interface FBTaskExecutorTask : NSObject<FBTask>

@property (nonatomic, strong) NSTask *task;

@property (nonatomic, strong) NSPipe *stdOutPipe;
@property (nonatomic, strong) NSMutableData *stdOutData;
@property (nonatomic, strong) NSPipe *stdErrPipe;
@property (nonatomic, strong) NSMutableData *stdErrData;

@property (nonatomic, assign) BOOL hasTerminated;
@property (nonatomic, copy) void (^terminationHandler)(id<FBTask>);
@property (atomic, strong) NSError *runningError;

@end

@implementation FBTaskExecutorTask

#pragma mark Initializers

+ (instancetype)shellTaskWithLaunchPath:(NSString *)launchPath commandString:(NSString *)commandString
{
  NSTask *nsTask = [[NSTask alloc] init];
  nsTask.environment = [self sutableEnvironmentForTask];
  nsTask.launchPath = launchPath;
  nsTask.arguments = @[@"-c", commandString];

  FBTaskExecutorTask *task = [self new];
  task.stdOutData = [NSMutableData data];
  task.stdErrData = [NSMutableData data];
  task.task = [task decorateTask:nsTask];
  return task;
}

+ (instancetype)taskWithLaunchPath:(NSString *)launchPath arguments:(NSArray *)arguments
{
  NSTask *nsTask = [[NSTask alloc] init];
  nsTask.environment = [self sutableEnvironmentForTask];
  nsTask.launchPath = launchPath;
  nsTask.arguments = arguments;

  FBTaskExecutorTask *task = [self new];
  task.stdOutData = [NSMutableData data];
  task.stdErrData = [NSMutableData data];
  task.task = [task decorateTask:nsTask];
  return task;
}

- (void)terminate
{
  @synchronized(self) {
    if (self.hasTerminated) {
      return;
    }

    CFRelease((__bridge CFTypeRef)(self.task));
    if (self.task.isRunning) {
      [self.task terminate];
      [self.task waitUntilExit];
    }
    self.stdOutPipe.fileHandleForReading.readabilityHandler = nil;
    self.stdErrPipe.fileHandleForReading.readabilityHandler = nil;
    self.stdOutPipe = nil;
    self.stdErrPipe = nil;
    if (self.task.terminationStatus != 0 && self.runningError == nil) {
      NSString *description = [NSString stringWithFormat:@"Returned non-zero status code %d", self.task.terminationStatus];
      self.runningError = [self errorForDescription:description];
    }

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
}

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
      FBTaskDefaultTimeout
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

- (NSInteger)processIdentifier
{
  return self.task.processIdentifier;
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

- (NSError *)error
{
  return self.runningError;
}

- (NSString *)description
{
  @synchronized(self) {
    return self.task.description;
  }
}

#pragma mark Private

- (NSTask *)decorateTask:(NSTask *)task
{
  __weak typeof(self) weakSelf = self;
  task.terminationHandler = ^(NSTask *_) {
    [weakSelf terminate];
  };

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
  return task;
}

+ (NSDictionary *)sutableEnvironmentForTask
{
  NSArray *applicableVariables = @[@"DEVELOPER_DIR", @"PATH"];
  NSDictionary *parentEnvironment = NSProcessInfo.processInfo.environment;
  NSMutableDictionary *taskEnvironment = [NSMutableDictionary dictionary];

  for (NSString *key in applicableVariables) {
    if (parentEnvironment[key]) {
      taskEnvironment[key] = parentEnvironment[key];
    }
  }
  return [taskEnvironment copy];
}

- (NSError *)errorForDescription:(NSString *)description
{
  NSParameterAssert(description);
  NSMutableDictionary *userInfo = [@{
    NSLocalizedDescriptionKey : description,
    @"stdout" : self.stdOut,
    @"stderr" : self.stdErr,
  } mutableCopy];

  if (self.task.isRunning) {
    userInfo[@"exitcode"] = @(self.task.terminationStatus);
  }

  return [NSError errorWithDomain:FBTaskExecutorErrorDomain code:0 userInfo:userInfo];
}

@end

@interface FBTaskExecutor ()

@property (nonatomic, copy) NSString *shellPath;

@end

@implementation FBTaskExecutor

+ (instancetype)sharedInstance
{
  static FBTaskExecutor *executor = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    executor = [FBTaskExecutor new];
  });
  return executor;
}

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _shellPath = FBTaskShellExecutablePath;
  return self;
}

#pragma mark - FBTaskExecutor

- (id<FBTask>)taskWithLaunchPath:(NSString *)launchPath arguments:(NSArray *)arguments
{
  return [FBTaskExecutorTask taskWithLaunchPath:launchPath arguments:arguments];
}

- (id<FBTask>)shellTask:(NSString *)commandString
{
  return [FBTaskExecutorTask shellTaskWithLaunchPath:self.shellPath commandString:commandString];
}

- (NSString *)executeShellCommand:(NSString *)commandString
{
  return [self executeShellCommand:commandString returningError:nil];
}

- (NSString *)executeShellCommand:(NSString *)commandString returningError:(NSError **)error
{
  id<FBTask> command = [self shellTask:commandString];
  [command startSynchronouslyWithTimeout:FBTaskDefaultTimeout];

  if (command.error) {
    if (error) {
      *error = command.error;
    }
    return nil;
  }
  return command.stdOut;
}

- (BOOL)repeatedlyRunCommand:(NSString *)commandString withError:(NSError **)error untilTrue:( BOOL(^)(NSString *stdOut) )block
{
  @autoreleasepool {
    NSDate *endDate = [NSDate dateWithTimeIntervalSinceNow:FBTaskDefaultTimeout];
    while ([endDate timeIntervalSinceNow] < 0) {
      NSError *innerError = nil;
      NSString *stdOut = [self executeShellCommand:commandString returningError:&innerError];
      if (!stdOut) {
        if (error) {
          *error = innerError;
        }
        return NO;
      }
      if (block(stdOut)) {
        return YES;
      }

      CFRunLoopRun();
    }
  }

  if (error) {
    *error = [self errorForDescription:[NSString stringWithFormat:@"Timed out waiting to validate command %@", commandString]];
  }

  return YES;
}

+ (NSString *)escapePathForShell:(NSString *)path
{
  return [path stringByReplacingOccurrencesOfString:@" " withString:@"\\ "];
}

#pragma mark - Private

- (NSError *)errorForDescription:(NSString *)description
{
  NSParameterAssert(description);
  return [NSError
    errorWithDomain:FBTaskExecutorErrorDomain
    code:0
    userInfo:@{NSLocalizedDescriptionKey : description}];
}

@end
