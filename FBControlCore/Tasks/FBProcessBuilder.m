/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessBuilder.h"

#import <FBControlCore/FBControlCore.h>

#import "FBDataBuffer.h"
#import "FBDataConsumer.h"
#import "FBProcessIO.h"
#import "FBProcessStream.h"
#import "FBProcess.h"
#import "FBProcessSpawnConfiguration.h"

@interface FBProcessBuilder ()

@property (nonatomic, copy, readwrite) NSString *launchPath;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput *stdOut;
@property (nonatomic, strong, nullable, readwrite) FBProcessOutput *stdErr;
@property (nonatomic, strong, nullable, readwrite) FBProcessInput *stdIn;
@property (nonatomic, strong, nullable, readwrite) id<FBControlCoreLogger> logger;

@end

@implementation FBProcessBuilder

#pragma mark Initializers

- (instancetype)initWithLaunchPath:(NSString *)launchPath
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _arguments = @[];
  _environment = FBProcessBuilder.defaultEnvironmentForSubprocess;
  _stdOut = [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  _stdErr = [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  _stdIn = nil;
  _logger = nil;

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

#pragma mark Spawn Configuration

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

#pragma mark stdin

- (instancetype)withStdIn:(FBProcessInput *)input
{
  self.stdIn = input;
  return self;
}

- (instancetype)withStdInConnected
{
  self.stdIn = [FBProcessInput inputFromConsumer];
  return self;
}

- (instancetype)withStdInFromData:(NSData *)data
{
  self.stdIn = [FBProcessInput inputFromData:data];
  return self;
}

#pragma mark stdout

- (instancetype)withStdOutInMemoryAsData
{
  self.stdOut = [FBProcessOutput outputToMutableData:NSMutableData.data];
  return self;
}

- (instancetype)withStdOutInMemoryAsString
{
  self.stdOut = [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  return self;
}

- (instancetype)withStdOutPath:(NSString *)stdOutPath
{
  NSParameterAssert(stdOutPath);
  self.stdOut = [FBProcessOutput outputForFilePath:stdOutPath];
  return self;
}

- (instancetype)withStdOutToDevNull
{
  self.stdOut = nil;
  return self;
}

- (instancetype)withStdOutToInputStream
{
  self.stdOut = [FBProcessOutput outputToInputStream];
  return self;
}

- (instancetype)withStdOutConsumer:(id<FBDataConsumer>)consumer
{
  self.stdOut = [FBProcessOutput outputForDataConsumer:consumer];
  return self;
}

- (instancetype)withStdOutLineReader:(void (^)(NSString *))reader
{
  return [self withStdOutConsumer:[FBBlockDataConsumer asynchronousLineConsumerWithBlock:reader]];
}

- (instancetype)withStdOutToLogger:(id<FBControlCoreLogger>)logger
{
  self.stdOut = [FBProcessOutput outputForLogger:logger];
  return self;
}

- (instancetype)withStdOutToLoggerAndErrorMessage:(id<FBControlCoreLogger>)logger
{
  self.stdOut = [FBProcessOutput outputForDataConsumer:[FBDataBuffer accumulatingBufferWithCapacity:FBProcessOutputErrorMessageLength] logger:logger];
  return self;
}

#pragma mark stderr

- (instancetype)withStdErrInMemoryAsData
{
  self.stdErr = [FBProcessOutput outputToMutableData:NSMutableData.data];
  return self;
}

- (instancetype)withStdErrInMemoryAsString
{
  self.stdErr = [FBProcessOutput outputToStringBackedByMutableData:NSMutableData.data];
  return self;
}

- (instancetype)withStdErrPath:(NSString *)stdErrPath
{
  NSParameterAssert(stdErrPath);
  self.stdErr = [FBProcessOutput outputForFilePath:stdErrPath];
  return self;
}

- (instancetype)withStdErrToDevNull
{
  self.stdErr = nil;
  return self;
}

- (instancetype)withStdErrConsumer:(id<FBDataConsumer>)consumer
{
  self.stdErr = [FBProcessOutput outputForDataConsumer:consumer];
  return self;
}

- (instancetype)withStdErrLineReader:(void (^)(NSString *))reader
{
  return [self withStdErrConsumer:[FBBlockDataConsumer asynchronousLineConsumerWithBlock:reader]];
}

- (instancetype)withStdErrToLogger:(id<FBControlCoreLogger>)logger
{
  self.stdErr = [FBProcessOutput outputForLogger:logger];
  return self;
}

- (instancetype)withStdErrToLoggerAndErrorMessage:(id<FBControlCoreLogger>)logger
{
  self.stdErr = [FBProcessOutput outputForDataConsumer:[FBDataBuffer accumulatingBufferWithCapacity:FBProcessOutputErrorMessageLength] logger:logger];
  return self;
}

#pragma mark Loggers

- (instancetype)withTaskLifecycleLoggingTo:(id<FBControlCoreLogger>)logger;
{
  self.logger = logger;
  return self;
}

#pragma mark Building

- (FBFuture<FBProcess *> *)start
{
  return [FBProcess launchProcessWithConfiguration:self.buildConfiguration logger:self.logger];
}

- (FBFuture<FBProcess *> *)runUntilCompletionWithAcceptableExitCodes:(NSSet<NSNumber *> *)exitCodes
{
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  return [[self
    start]
    onQueue:queue fmap:^(FBProcess *process) {
      return [[process exitedWithCodes:exitCodes] mapReplace:process];
    }];
}

#pragma mark Private

- (FBProcessSpawnConfiguration *)buildConfiguration
{
  return [[FBProcessSpawnConfiguration alloc]
    initWithLaunchPath:self.launchPath
    arguments:self.arguments
    environment:self.environment
    io:[[FBProcessIO alloc] initWithStdIn:self.stdIn stdOut:self.stdOut stdErr:self.stdErr]
    mode:FBProcessSpawnModeDefault];
}

+ (NSDictionary<NSString *, NSString *> *)defaultEnvironmentForSubprocess
{
  static dispatch_once_t onceToken;
  static NSDictionary<NSString *, NSString *> *environment = nil;
  dispatch_once(&onceToken, ^{
    NSArray<NSString *> *applicableVariables = @[@"DEVELOPER_DIR", @"HOME", @"PATH"];
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
