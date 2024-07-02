/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestProcess.h"

#import <sys/wait.h>

#import <FBControlCore/FBControlCore.h>

#import "FBXCTestConstants.h"
#import "XCTestBootstrapError.h"

static NSTimeInterval const CrashLogStartDateFuzz = -20;
static NSTimeInterval const CrashLogWaitTime = 180; // In case resources are pegged, just wait
static NSTimeInterval const KillBackoffTimeout = 1;

@implementation FBXCTestProcess

#pragma mark Public

+ (FBFuture<NSNumber *> *)ensureProcess:(FBProcess *)process completesWithin:(NSTimeInterval)timeout crashLogCommands:(id<FBCrashLogCommands>)crashLogCommands queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  // The start date of the process appear slightly older than we might think, so avoid missing it by a few seconds.
  NSDate *startDate = [NSDate.date dateByAddingTimeInterval:CrashLogStartDateFuzz];

  [logger logFormat:@"Waiting for %d to exit within %f seconds", process.processIdentifier, timeout];
  return [[[process
    statLoc]
    onQueue:queue timeout:timeout handler:^{
      return [FBXCTestProcess performSampleStackshotOnProcess:process forTimeout:timeout queue:queue logger:logger];;
    }]
    onQueue:queue fmap:^(id _) {
      // This will not be reached if the sample error ran.
      return [[process
        exitCode] // Re-map to the exit code as the first part of the chain will fire on *any* exit (including crashes).
        onQueue:queue chain:^ FBFuture<NSNumber *> * (FBFuture<NSNumber *> *exitCodeFuture) {
          // If there's an exit code, there wasn't a crash. Exit code handling is done in the caller.
          if (exitCodeFuture.state == FBFutureStateDone) {
            return exitCodeFuture;
          }
          // Here we know a signalled exit has occurred. This return happens if no crash log detection is present.
          if (!crashLogCommands) {
            return exitCodeFuture;
          }
          // Here we know we want to find the crash log, so attempt to get it.
          return [FBXCTestProcess performCrashLogQueryForProcess:process startDate:startDate crashLogCommands:crashLogCommands crashLogWaitTime:CrashLogWaitTime queue:queue logger:logger];
        }];
    }];
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

+ (FBFuture<id> *)performSampleStackshotOnProcess:(FBProcess *)process forTimeout:(NSTimeInterval)timeout queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[FBProcessFetcher
    performSampleStackshotForProcessIdentifier:process.processIdentifier  queue:queue]
    onQueue:queue fmap:^FBFuture<id> *(NSString *stackshot) {
      return [[FBXCTestError
        describeFormat:@"Waited %f seconds for process %d to terminate, but the xctest process stalled: %@", timeout, process.processIdentifier, stackshot]
        failFuture];
    }]
    onQueue:queue notifyOfCompletion:^(FBFuture *_) {
      [logger logFormat:@"Terminating stalled xctest process %@", process];
      [[process
        sendSignal:SIGTERM backingOffToKillWithTimeout:KillBackoffTimeout logger:logger]
        onQueue:queue notifyOfCompletion:^(FBFuture *__) {
          [logger logFormat:@"Stalled xctest process %@ has been terminated", process];
        }];
    }];
}

+ (FBFuture<NSNumber *> *)performCrashLogQueryForProcess:(FBProcess *)process startDate:(NSDate *)startDate crashLogCommands:(id<FBCrashLogCommands>)crashLogCommands crashLogWaitTime:(NSTimeInterval)crashLogWaitTime queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  [logger logFormat:@"xctest process (%d) died prematurely, checking for crash log for %f seconds", process.processIdentifier, crashLogWaitTime];
  return [[[FBXCTestProcess
    crashLogsForTerminationOfProcess:process since:startDate crashLogCommands:crashLogCommands crashLogWaitTime:crashLogWaitTime queue:queue]
    rephraseFailure:@"xctest process (%d) exited abnormally with no crash log, to check for yourself look in ~/Library/Logs/DiagnosticReports", process.processIdentifier]
    onQueue:queue fmap:^(FBCrashLogInfo *crashInfo) {
      return [[FBXCTestError
        describeFormat:@"xctest process crashed\n%@\n\nRaw Crash File Contents\n%@", crashInfo, [crashInfo loadRawCrashLogStringWithError:nil]]
        failFuture];
    }];
}

+ (FBFuture<FBCrashLogInfo *> *)crashLogsForTerminationOfProcess:(FBProcess *)process since:(NSDate *)sinceDate crashLogCommands:(id<FBCrashLogCommands>)crashLogCommands crashLogWaitTime:(NSTimeInterval)crashLogWaitTime queue:(dispatch_queue_t)queue
{
  NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[
    [FBCrashLogInfo predicateForCrashLogsWithProcessID:process.processIdentifier],
    [FBCrashLogInfo predicateNewerThanDate:sinceDate],
  ]];

  return [[crashLogCommands
    notifyOfCrash:predicate]
    timeout:crashLogWaitTime waitingFor:@"Crash logs for terminated process %d to appear", process.processIdentifier];
}

@end
