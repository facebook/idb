/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogicTestProcess.h"

#import <FBControlCore/FBControlCore.h>

#import "FBXCTestError.h"

static NSTimeInterval const CrashLogStartDateFuzz = -10;

@interface FBLogicTestProcess ()

@property (nonatomic, copy, readonly) NSString *launchPath;
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, strong, readonly) id<FBFileDataConsumer> stdOutReader;
@property (nonatomic, strong, readonly) id<FBFileDataConsumer> stdErrReader;
@property (nonatomic, assign, readwrite) BOOL xctestProcessIsSubprocess;

@property (nonatomic, copy, readwrite, nullable) NSDate *startDate;
@property (nonatomic, strong, readwrite, nullable) FBTask *task;

@end

@implementation FBLogicTestProcess

+ (instancetype)processWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutReader:(id<FBFileDataConsumer>)stdOutReader stdErrReader:(id<FBFileDataConsumer>)stdErrReader xctestProcessIsSubprocess:(BOOL)xctestProcessIsSubprocess
{
  return [[self alloc] initWithLaunchPath:launchPath arguments:arguments environment:environment stdOutReader:stdOutReader stdErrReader:stdErrReader xctestProcessIsSubprocess:xctestProcessIsSubprocess];
}

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment stdOutReader:(id<FBFileDataConsumer>)stdOutReader stdErrReader:(id<FBFileDataConsumer>)stdErrReader xctestProcessIsSubprocess:(BOOL)xctestProcessIsSubprocess
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _arguments = arguments;
  _environment = environment;
  _stdOutReader = stdOutReader;
  _stdErrReader = stdErrReader;
  _xctestProcessIsSubprocess = xctestProcessIsSubprocess;

  return self;
}

- (pid_t)startWithError:(NSError **)error
{
  // Construct and launch the task.
  self.startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];
  self.task = [[[[[[[[FBTaskBuilder
    withLaunchPath:self.launchPath]
    withArguments:self.arguments]
    withEnvironment:self.environment]
    withStdOutConsumer:self.stdOutReader]
    withStdErrConsumer:self.stdErrReader]
    withAcceptableTerminationStatusCodes:[NSSet setWithArray:@[@0, @1]]]
    build]
    startAsynchronously];

  if (self.task.error) {
    [[[FBControlCoreError
      describeFormat:@"Logic Test Process Errored %@", self.task.error.localizedDescription]
      causedBy:self.task.error]
      fail:error];
    self.task = nil;
    return -1;
  }

  return self.task.processIdentifier;
}

- (void)terminate
{
  [self.task terminate];
}

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  if (!self.task) {
    return [[FBControlCoreError
      describe:@"No task to await completion of"]
      failBool:error];
  }

  // Perform the underlying wait.
  FBTask *task = self.task;
  NSError *timeoutError = nil;
  BOOL waitSuccessful = [task waitForCompletionWithTimeout:timeout error:&timeoutError];

  // If the xctest process has stalled, we should sample it (if possible), then terminate it.
  if (!waitSuccessful) {
    pid_t xctestProcessIdentifier = self.xctestProcessIsSubprocess
      ? [FBLogicTestProcess xctestProcessIdentiferForSimctlParent:task.processIdentifier fetcher:FBProcessFetcher.new]
      : task.processIdentifier;

    NSString *sample = [FBLogicTestProcess sampleStalledProcess:xctestProcessIdentifier];
    [task terminate];
    return [[[FBXCTestError
      describeFormat:@"The xctest process stalled: %@", sample]
      causedBy:timeoutError]
      failBool:error];
  }

  // Fail on error event.
  if (task.error) {
    FBCrashLogInfo *crashLogInfo = [FBLogicTestProcess crashLogsForChildProcessOf:task.processIdentifier since:self.startDate];
    if (crashLogInfo) {
      FBDiagnostic *diagnosticCrash = [crashLogInfo toDiagnostic:FBDiagnosticBuilder.builder];
      return [[[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", diagnosticCrash.asString]
        causedBy:timeoutError]
        failBool:error];
    }
    return [[[FBXCTestError
      describeFormat:@"xctest process exited abnormally %@", self.task.error.localizedDescription]
      causedBy:task.error]
      failBool:error];
  }
  return YES;
}

+ (pid_t)xctestProcessIdentiferForSimctlParent:(pid_t)simctlProcessIdentifier fetcher:(FBProcessFetcher *)fetcher
{
  pid_t xctestProcessIdentifier = [fetcher subprocessOf:simctlProcessIdentifier withName:@"xctest"];
  if (xctestProcessIdentifier < 1) {
    return simctlProcessIdentifier;
  }
  return xctestProcessIdentifier;
}

+ (nullable FBCrashLogInfo *)crashLogsForChildProcessOf:(pid_t)processIdentifier since:(NSDate *)sinceDate
{
  NSSet<NSNumber *> *possiblePPIDs = [NSSet setWithArray:@[
    @(processIdentifier),
    @(NSProcessInfo.processInfo.processIdentifier),
  ]];

  NSPredicate *crashLogInfoPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLogInfo, id _) {
    return [possiblePPIDs containsObject:@(crashLogInfo.parentProcessIdentifier)];
  }];
  return [NSRunLoop.currentRunLoop spinRunLoopWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout untilExists:^ FBCrashLogInfo * {
    return [[[FBCrashLogInfo
      crashInfoAfterDate:sinceDate]
      filteredArrayUsingPredicate:crashLogInfoPredicate]
      firstObject];
  }];
}

+ (nullable NSString *)sampleStalledProcess:(pid_t)processIdentifier
{
  return [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @"1"]]
    build]
    startSynchronouslyWithTimeout:5]
    stdOut];
}

@end
