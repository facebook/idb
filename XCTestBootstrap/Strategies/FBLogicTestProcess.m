/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBLogicTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>

#import "XCTestBootstrapError.h"

static NSTimeInterval const CrashLogStartDateFuzz = -10;

@interface FBLogicTestProcess ()

@property (nonatomic, strong, readonly) id<FBLogicTestStrategy> strategy;
@property (nonatomic, copy, readwrite, nullable) NSDate *startDate;

@end

@implementation FBLogicTestProcess

+ (instancetype)processWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader strategy:(id<FBLogicTestStrategy>)strategy
{
  return [[FBLogicTestProcess alloc] initWithLaunchPath:launchPath arguments:arguments environment:environment waitForDebugger:waitForDebugger stdOutReader:stdOutReader stdErrReader:stdErrReader strategy:strategy];
}

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutReader:(id<FBFileConsumer>)stdOutReader stdErrReader:(id<FBFileConsumer>)stdErrReader strategy:(id<FBLogicTestStrategy>)strategy
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _arguments = arguments;
  _environment = environment;
  _waitForDebugger = waitForDebugger;
  _stdOutReader = stdOutReader;
  _stdErrReader = stdErrReader;
  _strategy = strategy;

  return self;
}

- (pid_t)startWithError:(NSError **)error
{
  // Construct and launch the task.
  self.startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];
  return [self.strategy logicTestProcess:self startWithError:error];
}

- (void)terminate
{
  [self.strategy terminateLogicTestProcess:self];
}

- (BOOL)waitForCompletionWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  return [self.strategy logicTestProcess:self waitForCompletionWithTimeout:timeout error:error];
}

- (BOOL)processDidTerminateNormallyWithProcessIdentifier:(pid_t)processIdentifier didTimeout:(BOOL)didTimeout exitCode:(int)exitCode error:(NSError **)error
{
  // If the xctest process has stalled, we should sample it (if possible), then terminate it.
  if (didTimeout) {
    NSString *sample = [FBLogicTestProcess sampleStalledProcess:processIdentifier];
    [self terminate];
    return [[FBXCTestError
      describeFormat:@"The xctest process stalled: %@", sample]
      failBool:error];
  }

  // If exited abnormally, check for a crash log
  if (exitCode != 0 && exitCode != 1) {
    FBCrashLogInfo *crashLogInfo = [FBLogicTestProcess crashLogsForChildProcessOf:processIdentifier since:self.startDate];
    if (crashLogInfo) {
      FBDiagnostic *diagnosticCrash = [crashLogInfo toDiagnostic:FBDiagnosticBuilder.builder];
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", diagnosticCrash.asString]
        failBool:error];
    }
    return [[FBXCTestError
      describeFormat:@"xctest process exited abnormally with exit code %d", exitCode]
      failBool:error];
  }
  return YES;
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
