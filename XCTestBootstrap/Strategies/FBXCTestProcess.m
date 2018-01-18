/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>

#import "XCTestBootstrapError.h"
#import "FBXCTestProcessExecutor.h"

static NSTimeInterval const CrashLogStartDateFuzz = -20;
static NSTimeInterval const CrashLogWaitTime = 20;

@interface FBXCTestProcess ()

@property (nonatomic, strong, readonly) id<FBXCTestProcessExecutor> executor;

@end

@implementation FBXCTestProcess

#pragma mark Initializers

+ (instancetype)processWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutConsumer:(id<FBFileConsumer>)stdOutConsumer stdErrConsumer:(id<FBFileConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor
{
  return [[FBXCTestProcess alloc] initWithLaunchPath:launchPath arguments:arguments environment:environment waitForDebugger:waitForDebugger stdOutConsumer:stdOutConsumer stdErrConsumer:stdErrConsumer executor:executor];
}

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOutConsumer:(id<FBFileConsumer>)stdOutConsumer stdErrConsumer:(id<FBFileConsumer>)stdErrConsumer executor:(id<FBXCTestProcessExecutor>)executor
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _arguments = arguments;
  _environment = environment;
  _waitForDebugger = waitForDebugger;
  _stdOutConsumer = stdOutConsumer;
  _stdErrConsumer = stdErrConsumer;
  _executor = executor;

  return self;
}

#pragma mark Public

- (FBFuture<NSNumber *> *)startWithTimeout:(NSTimeInterval)timeout
{
  NSDate *startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];

  return [[self.executor
    startProcess:self]
    onQueue:self.executor.workQueue map:^(FBLaunchedProcess *processInfo) {
      FBFuture<NSNumber *> *exitCode = [self decorateLaunchedWithErrorHandlingProcess:processInfo startDate:startDate timeout:timeout];
      return [[FBLaunchedProcess alloc] initWithProcessIdentifier:processInfo.processIdentifier exitCode:exitCode];
    }];
}

#pragma mark Private

- (FBFuture<NSNumber *> *)decorateLaunchedWithErrorHandlingProcess:(FBLaunchedProcess *)processInfo startDate:(NSDate *)startDate timeout:(NSTimeInterval)timeout
{
  dispatch_queue_t queue = self.executor.workQueue;

  FBFuture<NSNumber *> *completionFuture = [processInfo.exitCode
    onQueue:queue fmap:^(NSNumber *exitCode) {
      return [FBXCTestProcess onQueue:queue confirmNormalExitFor:processInfo.processIdentifier exitCode:exitCode.intValue startDate:startDate];
    }];
  FBFuture<NSNumber *> *timeoutFuture = [FBXCTestProcess onQueue:queue timeoutFuture:timeout processIdentifier:processInfo.processIdentifier];
  return [FBFuture race:@[completionFuture, timeoutFuture]];
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue timeoutFuture:(NSTimeInterval)timeout processIdentifier:(pid_t)processIdentifier
{
  return [[FBFuture
    futureWithDelay:timeout future:[FBFuture futureWithResult:NSNull.null]]
    onQueue:queue fmap:^(id _) {
      return [FBXCTestProcess onQueue:queue timeoutErrorWithTimeout:timeout processIdentifier:processIdentifier];
    }];
}

+ (FBFuture<id> *)onQueue:(dispatch_queue_t)queue timeoutErrorWithTimeout:(NSTimeInterval)timeout processIdentifier:(pid_t)processIdentifier
{
  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @"1"]]
    runFuture]
    onQueue:queue fmap:^(FBTask *task) {
      return [[FBXCTestError
        describeFormat:@"Waited %f seconds for process %d to terminate, but the xctest process stalled: %@", timeout, processIdentifier, task.stdOut]
        failFuture];
    }];
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue confirmNormalExitFor:(pid_t)processIdentifier exitCode:(int)exitCode startDate:(NSDate *)startDate
{
  // If exited abnormally, check for a crash log
  if (exitCode == 0 || exitCode == 1) {
    return [FBFuture futureWithResult:@(exitCode)];
  }
  return [[[FBXCTestProcess
    onQueue:queue crashLogsForTerminationOfProcess:processIdentifier since:startDate]
    rephraseFailure:@"xctest process (%d) exited abnormally (exit code %d) with no crash log", processIdentifier, exitCode]
    onQueue:queue fmap:^(FBCrashLogInfo *crashInfo) {
      FBDiagnostic *diagnosticCrash = [crashInfo toDiagnostic:FBDiagnosticBuilder.builder];
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", diagnosticCrash.asString]
        failFuture];
    }];
}

+ (FBFuture<FBCrashLogInfo *> *)onQueue:(dispatch_queue_t)queue crashLogsForTerminationOfProcess:(pid_t)processIdentifier since:(NSDate *)sinceDate
{
  NSPredicate *crashLogInfoPredicate = [NSPredicate predicateWithBlock:^ BOOL (FBCrashLogInfo *crashLogInfo, id _) {
    return processIdentifier == crashLogInfo.processIdentifier;
  }];
  return [[FBFuture
    onQueue:queue resolveUntil:^{
      FBCrashLogInfo *crashInfo = [[[FBCrashLogInfo
        crashInfoAfterDate:sinceDate]
        filteredArrayUsingPredicate:crashLogInfoPredicate]
        firstObject];
      if (!crashInfo) {
        return [[[XCTestBootstrapError
          describeFormat:@"Crash Info for %d could not be obtained", processIdentifier]
          noLogging]
          failFuture];
      }
      return [FBFuture futureWithResult:crashInfo];
    }]
    timedOutIn:CrashLogWaitTime];
}

@end
