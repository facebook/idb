/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTaskBuilder.h"

#import <FBControlCore/FBControlCore.h>

#import "FBTask.h"
#import "FBRunLoopSpinner.h"
#import "FBTaskConfiguration.h"

@interface FBTaskBuilder ()

@property (nonatomic, copy, readwrite) NSString *launchPath;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, copy, readwrite) NSSet<NSNumber *> *acceptableStatusCodes;
@property (nonatomic, strong, nullable, readwrite) id stdOut;
@property (nonatomic, strong, nullable, readwrite) id stdErr;

@end

@implementation FBTaskBuilder

- (instancetype)initWithLaunchPath:(NSString *)launchPath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _arguments = @[];
  _environment = FBTaskBuilder.defaultEnvironmentForSubprocess;
  _acceptableStatusCodes = [NSSet setWithObject:@0];
  _stdOut = [NSMutableData data];
  _stdErr = [NSMutableData data];

  return self;
}

+ (instancetype)withLaunchPath:(NSString *)launchPath
{
  NSParameterAssert(launchPath);
  return [[self alloc] initWithLaunchPath:launchPath];
}

+ (instancetype)withLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments
{
  NSParameterAssert(launchPath);
  NSParameterAssert(arguments);
  return [[self withLaunchPath:launchPath] withArguments:arguments];
}

#pragma mark - FBTaskBuilder

- (instancetype)withLaunchPath:(NSString *)launchPath
{
  NSParameterAssert(launchPath);
  self.launchPath = launchPath;
  return self;
}

- (instancetype)withArguments:(NSArray<NSString *> *)arguments
{
  NSParameterAssert(arguments);
  self.arguments = arguments;
  return self;
}

- (instancetype)withEnvironment:(NSDictionary<NSString *, NSString *> *)environment
{
  NSParameterAssert(environment);
  self.environment = environment;
  return self;
}

- (instancetype)withEnvironmentAdditions:(NSDictionary<NSString *, NSString *> *)environment
{
  NSParameterAssert(environment);
  NSMutableDictionary<NSString *, NSString *> *dictionary = [self.environment mutableCopy];
  [dictionary addEntriesFromDictionary:environment];
  return [self withEnvironment:[dictionary copy]];
}

- (instancetype)withStdOutInMemory
{
  self.stdOut = [NSMutableData data];
  return self;
}

- (instancetype)withStdErrInMemory
{
  self.stdErr = [NSMutableData data];
  return self;
}

- (instancetype)withStdOutPath:(NSString *)stdOutPath
{
  NSParameterAssert(stdOutPath);
  self.stdOut = stdOutPath;
  return self;
}

- (instancetype)withStdErrPath:(NSString *)stdErrPath
{
  NSParameterAssert(stdErrPath);
  self.stdErr = stdErrPath;
  return self;
}

- (instancetype)withStdOutToDevNull
{
  self.stdOut = nil;
  return self;
}

- (instancetype)withStdErrToDevNull
{
  self.stdErr = nil;
  return self;
}

- (instancetype)withStdOutConsumer:(id<FBFileConsumer>)consumer
{
  self.stdOut = consumer;
  return self;
}

- (instancetype)withStdErrConsumer:(id<FBFileConsumer>)consumer
{
  self.stdErr = consumer;
  return self;
}

- (instancetype)withStdOutLineReader:(void (^)(NSString *))reader
{
  return [self withStdOutConsumer:[FBLineFileConsumer asynchronousReaderWithConsumer:reader]];
}

- (instancetype)withStdErrLineReader:(void (^)(NSString *))reader
{
  return [self withStdErrConsumer:[FBLineFileConsumer asynchronousReaderWithConsumer:reader]];
}

- (instancetype)withStdOutToLogger:(id<FBControlCoreLogger>)logger
{
  self.stdOut = logger;
  return self;
}

- (instancetype)withStdErrToLogger:(id<FBControlCoreLogger>)logger
{
  self.stdErr = logger;
  return self;
}

- (instancetype)withAcceptableTerminationStatusCodes:(NSSet<NSNumber *> *)statusCodes
{
  NSParameterAssert(statusCodes);
  self.acceptableStatusCodes = statusCodes;
  return self;
}

- (FBTask *)build
{
  return [FBTask taskWithConfiguration:self.buildConfiguration];
}

- (FBTaskConfiguration *)buildConfiguration
{
  return [[FBTaskConfiguration alloc]
    initWithLaunchPath:self.launchPath
    arguments:self.arguments
    environment:self.environment
    acceptableStatusCodes:self.acceptableStatusCodes
    stdOut:self.stdOut
    stdErr:self.stdErr];
}

#pragma mark - Private

+ (NSError *)errorForDescription:(NSString *)description
{
  NSParameterAssert(description);
  return [NSError
    errorWithDomain:FBTaskErrorDomain
    code:0
    userInfo:@{NSLocalizedDescriptionKey : description}];
}

+ (NSDictionary<NSString *, NSString *> *)defaultEnvironmentForSubprocess
{
  static dispatch_once_t onceToken;
  static NSDictionary<NSString *, NSString *> *environment = nil;
  dispatch_once(&onceToken, ^{
    NSArray<NSString *> *applicableVariables = @[@"DEVELOPER_DIR", @"PATH"];
    NSDictionary<NSString *, NSString *> *parentEnvironment = NSProcessInfo.processInfo.environment;
    NSMutableDictionary<NSString *, NSString *> *taskEnvironment = [NSMutableDictionary dictionary];

    for (NSString *key in applicableVariables) {
      if (parentEnvironment[key]) {
        taskEnvironment[key] = parentEnvironment[key];
      }
    }
    environment = [taskEnvironment copy];
  });
  return environment;
}

@end

@implementation FBTaskBuilder (Convenience)

+ (FBTask *)taskWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments;
{
  return [[self withLaunchPath:launchPath arguments:arguments] build];
}

- (nullable NSString *)executeReturningError:(NSError **)error
{
  FBTask *task = [[self build] startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];
  if (error) {
    *error = [task error];
  }
  return [task stdOut];
}

@end
