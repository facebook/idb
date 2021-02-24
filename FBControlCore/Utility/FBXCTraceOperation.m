/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTraceOperation.h"

#import "FBCollectionInformation.h"
#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBDataConsumer.h"
#import "FBFuture.h"
#import "FBXCTraceConfiguration.h"
#import "FBiOSTarget.h"
#import "FBTask+Helpers.h"
#import "FBTaskBuilder.h"

const NSTimeInterval DefaultXCTraceRecordOperationTimeLimit = 4 * 60 * 60; // 4h
const NSTimeInterval DefaultXCTraceRecordStopTimeout = 600.0; // 600s


@implementation FBXCTraceRecordOperation

#pragma mark Initializers

+ (FBFuture<FBXCTraceRecordOperation *> *)operationWithTarget:(id<FBiOSTarget>)target configuration:(FBXCTraceRecordConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbcontrolcore.xctrace", DISPATCH_QUEUE_SERIAL);
  NSString *traceDir = [target.auxillaryDirectory stringByAppendingPathComponent:[@"xctrace-" stringByAppendingString:[[NSUUID UUID] UUIDString]]];
  NSError *error = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:traceDir withIntermediateDirectories:NO attributes:nil error:&error]) {
    return [[FBControlCoreError describeFormat:@"Failed to create xctrace trace output directory: %@", error] failFuture];
  }
  NSString *traceFile = [traceDir stringByAppendingPathComponent:@"trace.trace"];

  NSMutableArray<NSString *> *arguments = [NSMutableArray new];
  [arguments addObjectsFromArray:@[@"xctrace", @"record", @"--template", configuration.templateName, @"--device", target.udid, @"--output", traceFile, @"--time-limit", [NSString stringWithFormat:@"%ds", (int)configuration.timeLimit]]];
  if ([configuration.package length] > 0) {
    [arguments addObjectsFromArray:@[@"--package", configuration.package]];
  }
  if ([configuration.targetStdin length] > 0) {
    [arguments addObjectsFromArray:@[@"--target-stdin", configuration.targetStdin]];
  }
  if ([configuration.targetStdout length] > 0) {
    [arguments addObjectsFromArray:@[@"--target-stdout", configuration.targetStdout]];
  }
  if (configuration.allProcesses) {
    [arguments addObject:@"--all-processes"];
  }
  if ([configuration.processToAttach length] > 0) {
    [arguments addObjectsFromArray:@[@"--attach", configuration.processToAttach]];
  }
  if ([configuration.processToLaunch length] > 0) {
    [arguments addObjectsFromArray:@[@"--launch", @"--", configuration.processToLaunch]];
    [arguments addObjectsFromArray:configuration.launchArgs];
    for (NSString *key in configuration.processEnv) {
      [arguments addObjectsFromArray:@[@"--env", [NSString stringWithFormat:@"%@=%@", key, configuration.processEnv[key]]]];
    }
  }
  [logger logFormat:@"Starting xctrace with arguments: %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]];

  return [[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/xcrun"]
    withArguments:arguments]
    withStdOutToLogger:logger]
    withStdErrToLogger:logger]
    start]
    onQueue:target.asyncQueue map:^ FBXCTraceRecordOperation * (FBTask *task) {
      [logger logFormat:@"Started xctrace %@", task];
      return [[FBXCTraceRecordOperation alloc] initWithTask:task traceDir:[NSURL fileURLWithPath:traceFile] configuration:configuration queue:queue logger:logger];
    }];
}

- (instancetype)initWithTask:(FBTask *)task traceDir:(NSURL *)traceDir configuration:(FBXCTraceRecordConfiguration *)configuration queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _task = task;
  _traceDir = traceDir;
  _configuration = configuration;
  _queue = queue;
  _logger = logger;

  return self;
}

#pragma mark Public Methods

- (FBFuture<NSURL *> *)stopWithTimeout:(NSTimeInterval)timeout
{
  return [[FBFuture
    onQueue:self.queue resolve:^{
      [self.logger logFormat:@"Terminating xctrace record %@. Backoff Timeout %f", self.task, timeout];
      return [self.task sendSignal:SIGINT backingOffToKillWithTimeout:timeout logger:self.logger];
    }] chainReplace:[[self.task exitCode]
    onQueue:self.queue fmap:^FBFuture<NSURL *> *(NSNumber *exitCode) {
      if ([exitCode isEqualToNumber:@(0)]) {
        return [FBFuture futureWithResult:self.traceDir];
      } else {
        return [[FBControlCoreError describeFormat:@"Xctrace record exited with failure - status: %@", exitCode] failFuture];
      }
    }]
  ];
}

+ (FBFuture<NSURL *> *)postProcess:(NSArray<NSString *> *)arguments traceDir:(NSURL *)traceDir queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  if (!arguments || arguments.count == 0) {
    return [FBFuture futureWithResult:traceDir];
  }
  NSURL *outputTraceFile = [[traceDir URLByDeletingLastPathComponent] URLByAppendingPathComponent:arguments[2]];
  NSMutableArray<NSString *> *launchArguments = [@[arguments[1], traceDir.path, @"-o", outputTraceFile.path] mutableCopy];
  if (arguments.count > 3) {
    [launchArguments addObjectsFromArray:[arguments subarrayWithRange:(NSRange){3, [arguments count] - 3}]];
  }

  [logger logFormat:@"Starting post processing | Launch path: %@ | Arguments: %@", arguments[0], [FBCollectionInformation oneLineDescriptionFromArray:launchArguments]];
  return [[[[[[[[FBTaskBuilder
    withLaunchPath:arguments[0]]
    withArguments:launchArguments]
    withStdInConnected]
    withStdOutToLogger:logger]
    withStdErrToLogger:logger]
    withAcceptableExitCodes:[NSSet setWithObject:@0]]
    runUntilCompletion]
    onQueue:queue map:^(id _) {
      return outputTraceFile;
    }];
}

#pragma mark FBiOSTargetOperation

- (FBFuture<NSNull *> *)completed
{
  return [[[self.task.completed
    mapReplace:NSNull.null]
    shieldCancellation]
    onQueue:self.queue respondToCancellation:^{
      return [[self stopWithTimeout:DefaultXCTraceRecordStopTimeout] mapReplace:NSNull.null];
    }];
}

@end
