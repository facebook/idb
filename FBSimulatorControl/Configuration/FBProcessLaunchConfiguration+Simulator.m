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
  NSString *outputPath = [self.output performSelector:selector];
  if (![outputPath isKindOfClass:NSString.class]) {
    return YES;
  }

  SEL diagnosticSelector = NSSelectorFromString([NSString stringWithFormat:@"%@:", NSStringFromSelector(selector)]);
  FBDiagnostic *diagnostic = [simulator.diagnostics performSelector:diagnosticSelector withObject:self];
  FBDiagnosticBuilder *builder = [FBDiagnosticBuilder builderWithDiagnostic:diagnostic];

  if ([outputPath isEqualToString:FBProcessOutputToFileDefaultLocation]) {
    NSString *defaultOuputPath = [builder createPath];
    NSString *filename = defaultOuputPath.lastPathComponent;
    outputPath = [[[defaultOuputPath stringByDeletingLastPathComponent]
      stringByAppendingPathComponent:NSUUID.UUID.UUIDString]
      stringByAppendingPathComponent:filename];
  }

  [builder updateStorageDirectory:[outputPath stringByDeletingLastPathComponent]];

  if (![NSFileManager.defaultManager createFileAtPath:outputPath contents:NSData.data attributes:nil]) {
    return [[FBSimulatorError
      describeFormat:@"Could not create '%@' at path '%@' for config '%@'", NSStringFromSelector(selector), outputPath, self]
      failBool:error];
  }

  [builder updatePath:outputPath];

  if (diagnosticOut) {
    *diagnosticOut = [builder build];
  }

  return YES;
}

@end

#pragma clang diagnostic pop
