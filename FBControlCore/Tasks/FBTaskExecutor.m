/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTaskExecutor.h"
#import "FBTaskExecutor+Private.h"

#import <objc/runtime.h>

#import "FBTask+Private.h"
#import "FBTask.h"
#import "FBRunLoopSpinner.h"

NSString *const FBTaskExecutorErrorDomain = @"com.facebook.fbcontrolcore.task";

/**
 The name of the shell executable file to execute shell commands.
 */
static NSString *const FBTaskShellExecutablePath = @"/bin/sh";

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
  _environment = [FBTaskExecutor suitableEnvironmentForTask];
  return self;
}

- (instancetype)copyWithZone:(NSZone *)zone
{
  FBTaskExecutor *executor = [self.class new];
  executor.shellPath = self.shellPath;
  executor.launchPath = self.launchPath;
  executor.arguments = self.arguments;
  executor.environment = self.environment;
  executor.shellCommand = self.shellCommand;
  executor.acceptableStatusCodes = self.acceptableStatusCodes;
  executor.stdOutPath = self.stdOutPath;
  executor.stdErrPath = self.stdErrPath;
  return executor;
}

#pragma mark - FBTaskBuilder

- (instancetype)withAcceptableTerminationStatusCodes:(NSSet *)statusCodes
{
  FBTaskExecutor *executor = [self copy];
  executor.acceptableStatusCodes = statusCodes;
  return executor;
}

- (instancetype)withLaunchPath:(NSString *)launchPath
{
  FBTaskExecutor *executor = [self copy];
  object_setClass(executor, FBTaskExecutor_Task.class);
  executor.launchPath = launchPath;
  return executor;
}

- (instancetype)withArguments:(NSArray *)arguments
{
  FBTaskExecutor *executor = [self copy];
  object_setClass(executor, FBTaskExecutor_Task.class);
  executor.arguments = arguments;
  return executor;
}

- (instancetype)withEnvironmentAdditions:(NSDictionary *)environment
{
  FBTaskExecutor *executor = [self copy];
  NSMutableDictionary *dictionary = [self.environment mutableCopy];
  [dictionary addEntriesFromDictionary:environment];
  executor.environment = [dictionary copy];
  return executor;
}

- (instancetype)withShellTaskCommand:(NSString *)shellCommand
{
  FBTaskExecutor *executor = [self copy];
  object_setClass(executor, FBTaskExecutor_ShellTask.class);
  executor.shellCommand = shellCommand;
  return executor;
}

- (instancetype)withStdOutPath:(NSString *)stdOutPath stdErrPath:(NSString *)stdErrPath
{
  FBTaskExecutor *executor = [self copy];
  executor.stdOutPath = stdOutPath;
  executor.stdErrPath = stdErrPath;
  return executor;
}

- (instancetype)withWritingInMemory
{
  FBTaskExecutor *executor = [self copy];
  executor.stdOutPath = nil;
  executor.stdErrPath = nil;
  return executor;
}

- (id<FBTask>)build
{
  return [FBTask taskWithNSTask:[self buildTask] acceptableStatusCodes:self.acceptableStatusCodes stdOutPath:self.stdOutPath stdErrPath:self.stdErrPath];
}

- (NSTask *)buildTask
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark - FBTaskExecutor

- (id<FBTask>)taskWithLaunchPath:(NSString *)launchPath arguments:(NSArray *)arguments
{
  return [[[self withLaunchPath:launchPath] withArguments:arguments] build];
}

- (id<FBTask>)shellTask:(NSString *)commandString
{
  return [[self withShellTaskCommand:commandString] build];
}

+ (NSString *)escapePathForShell:(NSString *)path
{
  return [path stringByReplacingOccurrencesOfString:@" " withString:@"\\ "];
}

#pragma mark - Private

+ (NSError *)errorForDescription:(NSString *)description
{
  NSParameterAssert(description);
  return [NSError
    errorWithDomain:FBTaskExecutorErrorDomain
    code:0
    userInfo:@{NSLocalizedDescriptionKey : description}];
}

+ (NSDictionary *)suitableEnvironmentForTask
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

@end

@implementation FBTaskExecutor_Task

- (NSTask *)buildTask
{
  NSTask *nsTask = [[NSTask alloc] init];
  nsTask.environment = self.environment;
  nsTask.launchPath = self.launchPath;
  nsTask.arguments = self.arguments;
  return nsTask;
}

@end

@implementation FBTaskExecutor_ShellTask

- (NSTask *)buildTask
{
  NSTask *nsTask = [[NSTask alloc] init];
  nsTask.environment = self.environment;
  nsTask.launchPath = self.shellPath;
  nsTask.arguments = @[@"-c", self.shellCommand];
  return nsTask;
}

@end
