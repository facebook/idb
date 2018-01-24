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

#import "FBFileConsumer.h"
#import "FBTask.h"
#import "FBTaskConfiguration.h"
#import "FBProcessStream.h"

@interface FBTaskBuilder ()

@property (nonatomic, copy, readwrite) NSString *launchPath;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, copy, readwrite) NSSet<NSNumber *> *acceptableStatusCodes;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput *stdOut;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput *stdErr;
@property (nonatomic, strong, nullable, readwrite) FBProcessInput *stdIn;

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
  _stdOut = [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  _stdErr = [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  _stdIn = nil;

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

- (instancetype)withStdOutInMemoryAsData
{
  self.stdOut = [FBProcessOutput outputToMutableData:NSMutableData.data];
  return self;
}

- (instancetype)withStdErrInMemoryAsData
{
  self.stdErr = [FBProcessOutput outputToMutableData:NSMutableData.data];
  return self;
}

- (instancetype)withStdOutInMemoryAsString
{
  self.stdOut = [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  return self;
}

- (instancetype)withStdErrInMemoryAsString
{
  self.stdErr = [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  return self;
}

- (instancetype)withStdOutPath:(NSString *)stdOutPath
{
  NSParameterAssert(stdOutPath);
  self.stdOut = [FBProcessOutput outputForFilePath:stdOutPath];
  return self;
}

- (instancetype)withStdErrPath:(NSString *)stdErrPath
{
  NSParameterAssert(stdErrPath);
  self.stdErr = [FBProcessOutput outputForFilePath:stdErrPath];
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
  self.stdOut = [FBProcessOutput outputForFileConsumer:consumer];
  return self;
}

- (instancetype)withStdErrConsumer:(id<FBFileConsumer>)consumer
{
  self.stdErr = [FBProcessOutput outputForFileConsumer:consumer];
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
  self.stdOut = [FBProcessOutput outputForLogger:logger];
  return self;
}

- (instancetype)withStdErrToLogger:(id<FBControlCoreLogger>)logger
{
  self.stdErr = [FBProcessOutput outputForLogger:logger];
  return self;
}

- (instancetype)withStdInConnected
{
  self.stdIn = [FBProcessInput inputProducingConsumer];
  return self;
}

- (instancetype)withStdInFromData:(NSData *)data
{
  self.stdIn = [FBProcessInput inputFromData:data];
  return self;
}

- (instancetype)withAcceptableTerminationStatusCodes:(NSSet<NSNumber *> *)statusCodes
{
  NSParameterAssert(statusCodes);
  self.acceptableStatusCodes = statusCodes;
  return self;
}

- (FBFuture<FBTask *> *)start
{
  return [FBTask startTaskWithConfiguration:self.buildConfiguration];
}

- (FBTask *)startSynchronously
{
  FBFuture<FBTask *> *future = [self start];
  NSError *error = nil;
  FBTask *task = [future await:&error];
  NSAssert(task, @"Task Could not be started %@", error);
  return task;
}

#pragma mark - Private

- (FBTaskConfiguration *)buildConfiguration
{
  return [[FBTaskConfiguration alloc]
    initWithLaunchPath:self.launchPath
    arguments:self.arguments
    environment:self.environment
    acceptableStatusCodes:self.acceptableStatusCodes
    stdOut:self.stdOut
    stdErr:self.stdErr
    stdIn:self.stdIn];
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

- (FBFuture<FBTask *> *)runUntilCompletion
{
  return [[self
    start]
    onQueue:dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0) fmap:^(FBTask *task) {
      return [[task completed] mapReplace:task];
    }];
}

- (FBTask *)runSynchronouslyUntilCompletionWithTimeout:(NSTimeInterval)timeout
{
  FBTask *task = [self startSynchronously];
  FBFuture<NSNumber *> *future = [task completed];
  NSError *error = nil;
  [future awaitWithTimeout:timeout error:&error];

  // The Future will still be running in the event that we await and the future is still running.
  // In this event we should ancel the future and wait for the cancellation to propogate.
  if (future.state == FBFutureStateRunning) {
    [future.cancel await:nil];
    return task;
  }

  return task;
}

@end
