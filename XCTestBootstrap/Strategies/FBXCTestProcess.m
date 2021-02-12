/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>

#import "XCTestBootstrapError.h"
#import "FBXCTestProcessExecutor.h"
#import "ReporterEvents.h"

static NSTimeInterval const CrashLogStartDateFuzz = -20;
static NSTimeInterval const CrashLogWaitTime = 180; // In case resources are pegged, just wait
static NSUInteger const SampleDuration = 1;
static NSTimeInterval const SampleTimeoutSubtraction = SampleDuration + 1;

@implementation FBXCTestProcess

#pragma mark Public

+ (FBFuture<NSNumber *> *)ensureProcess:(id<FBLaunchedProcess>)process completesWithin:(NSTimeInterval)timeout withCrashLogDetection:(BOOL)crashLogDetection queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return crashLogDetection
    ? [self ensureProcessWithCrashDetection:process completesWithin:timeout queue:queue logger:logger]
    : [self ensureProcessExitCode:process.exitCode processIdentifier:process.processIdentifier completesWithin:timeout queue:queue logger:logger];
}

+ (nullable NSString *)describeFailingExitCode:(int)exitCode
{
  switch (exitCode) {
    case 0:
      return nil;
    case 1:
      return nil;
    case TestShimExitCodeDLOpenError:
      return @"DLOpen Error";
    case TestShimExitCodeBundleOpenError:
      return @"Error opening test bundle";
    case TestShimExitCodeMissingExecutable:
      return @"Missing executable";
    case TestShimExitCodeXCTestFailedLoading:
      return @"XCTest Framework failed loading";
    default:
      return [NSString stringWithFormat:@"Unknown xctest exit code %d", exitCode];
  }
}

#pragma mark Private

+ (FBFuture<NSNumber *> *)ensureProcessWithCrashDetection:(id<FBLaunchedProcess>)process completesWithin:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBCrashLogNotifier *notifier = [FBCrashLogNotifier.sharedInstance startListening:YES];
  NSDate *startDate = NSDate.date;

  // Since launching the process may make some time, we still want to respect the timeout.
  // For this reason we have to take this delta into account.
  // In addition, the timing out of the process is also more agressive, since we have to take into account the time to take a stack sample
  NSTimeInterval realTimeout = MAX(timeout - [NSDate.date timeIntervalSinceDate:startDate] - SampleTimeoutSubtraction, 0);

  // Additionally, we make the start date of the process appear slightly older than we might think, this is in order that we can catch crash logs that may match this process.
  NSDate *fuzzedStartDate = [startDate dateByAddingTimeInterval:CrashLogStartDateFuzz];

  return [FBXCTestProcess onQueue:queue decorateLaunchedWithErrorHandlingProcess:process startDate:fuzzedStartDate timeout:realTimeout notifier:notifier logger:logger];
}

+ (FBFuture<NSNumber *> *)ensureProcessExitCode:(FBFuture<NSNumber *> *)exitCode processIdentifier:(pid_t)processIdentifier completesWithin:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  FBFuture<NSNumber *> *timeoutFuture = [FBXCTestProcess timeoutFuture:timeout processIdentifier:processIdentifier queue:queue];
  return [FBFuture race:@[exitCode, timeoutFuture]];
}

+ (FBFuture<NSNumber *> *)onQueue:(dispatch_queue_t)queue decorateLaunchedWithErrorHandlingProcess:(id<FBLaunchedProcess>)process startDate:(NSDate *)startDate timeout:(NSTimeInterval)timeout notifier:(FBCrashLogNotifier *)notifier logger:(id<FBControlCoreLogger>)logger
{
  // Timeout should only apply to the duration of the process itself and not include sampling time.
  FBFuture<NSNumber *> *exitCode = [self ensureProcessExitCode:process.exitCode processIdentifier:process.processIdentifier completesWithin:timeout queue:queue logger:logger];
  return [exitCode  // This will resolve a future with an exit code, or error for crash/timeout.
    onQueue:queue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *exitCodeFuture) {
      // Do not handle exit codes, this is done upstream.
      if (exitCodeFuture.state == FBFutureStateDone) {
        return exitCodeFuture;
      }
      return [FBXCTestProcess performCrashLogQueryForProcess:process.processIdentifier startDate:startDate notifier:notifier crashLogWaitTime:CrashLogWaitTime queue:queue logger:logger];
    }];
}

+ (FBFuture<NSNumber *> *)timeoutFuture:(NSTimeInterval)timeout processIdentifier:(pid_t)processIdentifier queue:(dispatch_queue_t)queue
{
  return [[FBFuture
    futureWithDelay:timeout future:FBFuture.empty]
    onQueue:queue fmap:^(id _) {
      return [FBXCTestProcess performSampleStackshotForTimeout:timeout queue:queue processIdentifier:processIdentifier];
    }];
}

+ (FBFuture<id> *)performSampleStackshotForTimeout:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue processIdentifier:(pid_t)processIdentifier
{
  return [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/sample" arguments:@[@(processIdentifier).stringValue, @(SampleDuration).stringValue]]
    runUntilCompletion]
    onQueue:queue fmap:^(FBTask *task) {
      return [[FBXCTestError
        describeFormat:@"Waited %f seconds for process %d to terminate, but the xctest process stalled: %@", timeout, processIdentifier, task.stdOut]
        failFuture];
    }];
}

+ (FBFuture<NSNumber *> *)performCrashLogQueryForProcess:(pid_t)processIdentifier startDate:(NSDate *)startDate notifier:(FBCrashLogNotifier *)notifier crashLogWaitTime:(NSTimeInterval)crashLogWaitTime queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"xctest process (%d) died prematurely, checking for crash log for %f seconds", processIdentifier, crashLogWaitTime];
  return [[[FBXCTestProcess
    crashLogsForTerminationOfProcess:processIdentifier since:startDate notifier:notifier crashLogWaitTime:crashLogWaitTime queue:queue]
    rephraseFailure:@"xctest process (%d) exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports", processIdentifier]
    onQueue:queue fmap:^(FBCrashLogInfo *crashInfo) {
      NSString *crashString = [NSString stringWithContentsOfFile:crashInfo.crashPath encoding:NSUTF8StringEncoding error:nil];
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n %@", crashString]
        failFuture];
    }];
}

+ (FBFuture<FBCrashLogInfo *> *)crashLogsForTerminationOfProcess:(pid_t)processIdentifier since:(NSDate *)sinceDate notifier:(FBCrashLogNotifier *)notifier crashLogWaitTime:(NSTimeInterval)crashLogWaitTime queue:(dispatch_queue_t)queue
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBCrashLogInfo predicateForCrashLogsWithProcessID:processIdentifier],
    [FBCrashLogInfo predicateNewerThanDate:sinceDate],
  ]];

  return [[notifier
    nextCrashLogForPredicate:predicate]
    timeout:crashLogWaitTime waitingFor:@"Crash logs for terminated process %d to appear", processIdentifier];
}

@end
