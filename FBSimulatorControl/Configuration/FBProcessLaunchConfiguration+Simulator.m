/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessLaunchConfiguration+Simulator.h"

#import "FBSimulator.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorError.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@implementation FBProcessLaunchConfiguration (Simulator)

- (BOOL)createStdOutDiagnosticForSimulator:(FBSimulator *)simulator diagnosticOut:(FBDiagnostic **)diagnosticOut error:(NSError **)error
{
  return [self createDiagnosticForSelector:@selector(stdOut) simulator:simulator diagnosticOut:diagnosticOut error:error];
}

- (BOOL)createStdErrDiagnosticForSimulator:(FBSimulator *)simulator diagnosticOut:(FBDiagnostic **)diagnosticOut error:(NSError **)error
{
  return [self createDiagnosticForSelector:@selector(stdErr) simulator:simulator diagnosticOut:diagnosticOut error:error];
}

#pragma mark Private

- (BOOL)createDiagnosticForSelector:(SEL)selector simulator:(FBSimulator *)simulator diagnosticOut:(FBDiagnostic **)diagnosticOut error:(NSError **)error
{
  NSString *output = [self.output performSelector:selector];
  if (![output isKindOfClass:NSString.class]) {
    return YES;
  }

  if ([output isEqualToString:FBProcessOutputToFileDefaultLocation]) {
    SEL diagnosticSelector = NSSelectorFromString([NSString stringWithFormat:@"%@:", NSStringFromSelector(selector)]);
    FBDiagnostic *diagnostic = [simulator.diagnostics performSelector:diagnosticSelector withObject:self];
    FBDiagnosticBuilder *builder = [FBDiagnosticBuilder builderWithDiagnostic:diagnostic];
    NSString *path = [builder createPath];
    if (![NSFileManager.defaultManager createFileAtPath:path contents:NSData.data attributes:nil]) {
      return [[FBSimulatorError
        describeFormat:@"Could not create '%@' at path '%@' for config '%@'", NSStringFromSelector(selector), path, self]
        failBool:error];
    }
    if (diagnosticOut) {
      *diagnosticOut = diagnostic;
    }
  }
  return YES;
}

@end

#pragma clang diagnostic pop
