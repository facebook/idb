/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorSessionInteraction+Diagnostics.h"

#import "FBSimulatorApplication.h"
#import "FBSimulatorControl+Private.h"
#import "FBSimulatorSession+Private.h"
#import "FBSimulatorSession.h"
#import "FBSimulatorSessionInteraction+Private.h"
#import "FBSimulatorSessionLifecycle.h"
#import "FBSimulatorSessionState+Queries.h"
#import "FBTaskExecutor.h"

typedef id<FBTask>(^FBDiagnosticTaskFactory)(FBTaskExecutor *executor, NSInteger processIdentifier);

@implementation FBSimulatorSessionInteraction (Diagnostics)

- (instancetype)sampleApplication:(FBSimulatorApplication *)application withDuration:(NSInteger)durationInSeconds frequency:(NSInteger)frequencyInMilliseconds
{
  return [self asyncDiagnosticOnApplication:application name:@"stack_sample" taskFactory:^ id<FBTask> (FBTaskExecutor *executor, NSInteger processIdentifier) {
    return [executor
      taskWithLaunchPath:@"/usr/bin/sample"
      arguments:@[@(processIdentifier).stringValue, @(durationInSeconds).stringValue, @(frequencyInMilliseconds).stringValue]];
  }];
}

- (instancetype)onApplication:(FBSimulatorApplication *)application executeLLDBCommand:(NSString *)command
{
  NSParameterAssert(command);

  return [self syncDiagnosticOnApplication:application name:@"lldb_command" taskFactory:^id<FBTask>(FBTaskExecutor *executor, NSInteger processIdentifier) {
    return [executor
      taskWithLaunchPath:@"/usr/bin/lldb"
      arguments:@[@"-p", @(processIdentifier).stringValue, @"-o", command, @"-o", @"script import os; os._exit(1)"]];
  }];
}

#pragma mark Private

- (instancetype)asyncDiagnosticOnApplication:(FBSimulatorApplication *)application name:(NSString *)name taskFactory:(FBDiagnosticTaskFactory)taskFactory
{
  NSParameterAssert(application);
  NSParameterAssert(name);
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self application:application interact:^ BOOL (NSInteger processIdentifier, NSError **error) {
    id<FBTask> task = taskFactory(FBTaskExecutor.sharedInstance, processIdentifier);
    NSCAssert(task, @"Task should not be nil");

    [lifecycle associateEndOfSessionCleanup:task];
    [task startAsynchronouslyWithTerminationHandler:^(id<FBTask> innerTask) {
      if (innerTask.error) {
        return;
      }

      [lifecycle application:application didGainDiagnosticInformationWithName:name data:innerTask.stdOut];
    }];

    if (task.error) {
      return [FBSimulatorControl failBoolWithError:task.error errorOut:error];
    }
    return YES;
  }];
}

- (instancetype)syncDiagnosticOnApplication:(FBSimulatorApplication *)application name:(NSString *)name taskFactory:(FBDiagnosticTaskFactory)taskFactory
{
  NSParameterAssert(application);
  NSParameterAssert(name);
  FBSimulatorSessionLifecycle *lifecycle = self.session.lifecycle;

  return [self application:application interact:^ BOOL (NSInteger processIdentifier, NSError **error) {
    id<FBTask> task = taskFactory(FBTaskExecutor.sharedInstance, processIdentifier);
    NSCAssert(task, @"Task should not be nil");

    [task startSynchronouslyWithTimeout:FBSimulatorInteractionDefaultTimeout];
    // TODO(t7849941): We should obey the error, but lldb will return a status 1, so we need a way of setting acceptable status codes.
    [lifecycle application:application didGainDiagnosticInformationWithName:name data:task.stdOut];
    return YES;
  }];
}

@end
