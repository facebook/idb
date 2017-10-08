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

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

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
  FBProcessOutput *stdOut = nil;
  FBProcessOutput *stdErr = nil;
  if (![self createOutputForSimulator:simulator outputOut:&stdOut selector:@selector(stdOut) error:error]) {
    return NO;
  }
  if (stdOutOut && stdOut) {
    *stdOutOut = stdOut;
  }
  if (![self createOutputForSimulator:simulator outputOut:&stdErr selector:@selector(stdErr) error:error]) {
    return NO;
  }
  if (stdErrOut && stdErr) {
    *stdErrOut = stdErr;
  }
  return YES;
}

#pragma mark Private

- (BOOL)createOutputForSimulator:(FBSimulator *)simulator outputOut:(FBProcessOutput **)outputOut selector:(SEL)selector error:(NSError **)error
{
  FBDiagnostic *diagnostic = nil;
  if (![self createDiagnosticForSelector:selector simulator:simulator diagnosticOut:&diagnostic error:error]) {
    return NO;
  }
  if (diagnostic) {
    NSString *path = diagnostic.asPath;
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
      return [[FBSimulatorError
        describeFormat:@"Could not file handle for %@ at path '%@' for config '%@'", NSStringFromSelector(selector), path, self]
        failBool:error];
    }
    if (outputOut) {
      *outputOut = [FBProcessOutput outputForFileHandle:handle diagnostic:diagnostic];
    }
    return YES;
  }
  id<FBFileConsumer> consumer = [self.output performSelector:selector];
  if (![consumer conformsToProtocol:@protocol(FBFileConsumer)]) {
    return YES;
  }
  FBProcessOutput *output = [FBProcessOutput outputWithConsumer:consumer error:error];
  if (!output) {
    return NO;
  }
  if (outputOut) {
    *outputOut = output;
  }
  return YES;
}

@end

#pragma clang diagnostic pop
