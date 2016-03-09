/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorInteraction+Diagnostics.h"

#import <FBControlCore/FBControlCore.h>

#import "FBSimulatorApplication.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorError.h"
#import "FBSimulatorEventSink.h"
#import "FBSimulatorHistory+Queries.h"
#import "FBSimulatorInteraction+Private.h"

typedef id<FBTask>(^FBDiagnosticTaskFactory)(FBTaskExecutor *executor, pid_t processIdentifier);

@implementation FBSimulatorInteraction (Diagnostics)

- (instancetype)sampleApplication:(FBSimulatorApplication *)application withDuration:(NSInteger)durationInSeconds frequency:(NSInteger)frequencyInMilliseconds
{
  return [self asyncDiagnosticOnApplication:application name:@"stack_sample" taskFactory:^ id<FBTask> (FBTaskExecutor *executor, pid_t processIdentifier) {
    return [executor
      taskWithLaunchPath:@"/usr/bin/sample"
      arguments:@[@(processIdentifier).stringValue, @(durationInSeconds).stringValue, @(frequencyInMilliseconds).stringValue]];
  }];
}

- (instancetype)onApplication:(FBSimulatorApplication *)application executeLLDBCommand:(NSString *)command
{
  NSParameterAssert(command);

  return [self syncDiagnosticOnApplication:application name:@"lldb_command" taskFactory:^id<FBTask>(FBTaskExecutor *executor, pid_t processIdentifier) {
    return [[[[executor
      withLaunchPath:@"/usr/bin/lldb"]
      withArguments:@[@"-p", @(processIdentifier).stringValue, @"-o", command, @"-o", @"script import os; os._exit(1)"]]
      withAcceptableTerminationStatusCodes:[NSSet setWithArray:@[@0, @1]]]
      build];
  }];
}

#pragma mark Private

- (instancetype)asyncDiagnosticOnApplication:(FBSimulatorApplication *)application name:(NSString *)name taskFactory:(FBDiagnosticTaskFactory)taskFactory
{
  NSParameterAssert(application);
  NSParameterAssert(name);

  return [self binary:application.binary interact:^ BOOL (NSError **error, FBSimulator *simulator, FBProcessInfo *process) {
    id<FBTask> task = taskFactory(FBTaskExecutor.sharedInstance, process.processIdentifier);
    NSCAssert(task, @"Task should not be nil");

    [task startAsynchronouslyWithTerminationHandler:^(id<FBTask> innerTask) {
      if (innerTask.error) {
        return;
      }

      [FBSimulatorInteraction writeDiagnosticForSimulator:simulator process:process name:name value:innerTask.stdOut];
    }];

    if (task.error) {
      return [FBSimulatorError failBoolWithError:task.error errorOut:error];
    }
    return YES;
  }];
}

- (instancetype)syncDiagnosticOnApplication:(FBSimulatorApplication *)application name:(NSString *)name taskFactory:(FBDiagnosticTaskFactory)taskFactory
{
  NSParameterAssert(application);
  NSParameterAssert(name);

  return [self binary:application.binary interact:^ BOOL (NSError **error, FBSimulator *simulator, FBProcessInfo *process) {
    id<FBTask> task = taskFactory(FBTaskExecutor.sharedInstance, process.processIdentifier);
    NSCAssert(task, @"Task should not be nil");

    [task startSynchronouslyWithTimeout:FBControlCoreGlobalConfiguration.regularTimeout];
    if (task.error) {
      return [FBSimulatorError failBoolWithError:task.error errorOut:error];
    }
    [FBSimulatorInteraction writeDiagnosticForSimulator:simulator process:process name:name value:task.stdOut];
    return YES;
  }];
}

+ (void)writeDiagnosticForSimulator:(FBSimulator *)simulator process:(FBProcessInfo *)process name:(NSString *)name value:(NSString *)value
{
  FBDiagnostic *diagnostic = [[[[[FBDiagnosticBuilder builderWithDiagnostic:simulator.diagnostics.base]
    updateString:value]
    updateShortName:[NSString stringWithFormat:@"%@_%@_%d", name, process.processName, process.processIdentifier]]
    updateFileType:@"txt"]
    build];

  return [simulator.eventSink diagnosticAvailable:diagnostic];
}

@end
