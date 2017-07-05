/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAgentLaunchConfiguration+Simulator.h"

#import "FBSimulator.h"
#import "FBProcessOutput.h"
#import "FBSimulatorError.h"
#import "FBProcessLaunchConfiguration+Simulator.h"

FBiOSTargetActionType const FBiOSTargetActionTypeAgentLaunch = @"agentlaunch";

@implementation FBAgentLaunchConfiguration (Simulator)

#pragma mark FBiOSTargetAction

+ (FBiOSTargetActionType)actionType
{
  return FBiOSTargetActionTypeAgentLaunch;
}

- (BOOL)runWithTarget:(id<FBiOSTarget>)target delegate:(id<FBiOSTargetActionDelegate>)delegate error:(NSError **)error;
{
  if (![target isKindOfClass:FBSimulator.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ cannot launch an agent", target]
      failBool:error];
  }
  FBSimulator *simulator = (FBSimulator *) target;
  return [simulator launchAgent:self error:error] != nil;
}

#pragma mark Public

- (BOOL)createOutputForSimulator:(FBSimulator *)simulator stdOutOut:(FBProcessOutput **)stdOutOut stdErrOut:(FBProcessOutput **)stdErrOut error:(NSError **)error
{
  FBDiagnostic *stdOutDiagnostic = nil;
  FBDiagnostic *stdErrDiagnostic = nil;
  NSFileHandle *stdOutHandle = nil;
  NSFileHandle *stdErrHandle = nil;

  // Create the File Handles, based on the configuration for the AgentLaunch.
  if (![self createStdOutDiagnosticForSimulator:simulator diagnosticOut:&stdOutDiagnostic error:error]) {
    return NO;
  }
  if (stdOutDiagnostic) {
    NSString *path = stdOutDiagnostic.asPath;
    stdOutHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!stdOutHandle) {
      return [[FBSimulatorError
        describeFormat:@"Could not file handle for stdout at path '%@' for config '%@'", path, self]
        failBool:error];
    }
    if (stdErrOut) {
      *stdErrOut = [FBProcessOutput outputForFileHandle:stdErrHandle diagnostic:stdOutDiagnostic];
    }
  }
  if (![self createStdErrDiagnosticForSimulator:simulator diagnosticOut:&stdErrDiagnostic error:error]) {
    return NO;
  }
  if (stdErrDiagnostic) {
    NSString *path = stdErrDiagnostic.asPath;
    stdErrHandle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!stdOutHandle) {
      return [[FBSimulatorError
        describeFormat:@"Could not file handle for stderr at path '%@' for config '%@'", path, self]
        failBool:error];
    }
    if (stdOutOut) {
      *stdOutOut = [FBProcessOutput outputForFileHandle:stdOutHandle diagnostic:stdOutDiagnostic];
    }
  }
  return YES;
}

@end
