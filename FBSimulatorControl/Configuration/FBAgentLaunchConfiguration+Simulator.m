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
#import "FBSimulatorError.h"
#import "FBProcessLaunchConfiguration+Simulator.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@implementation FBAgentLaunchConfiguration (Simulator)

#pragma mark FBiOSTargetFuture

+ (FBiOSTargetFutureType)futureType
{
  return FBiOSTargetFutureTypeAgentLaunch;
}

- (FBFuture<id<FBiOSTargetContinuation>> *)runWithTarget:(id<FBiOSTarget>)target consumer:(id<FBFileConsumer>)consumer reporter:(id<FBEventReporter>)reporter
{
  if (![target isKindOfClass:FBSimulator.class]) {
    return [[FBSimulatorError
      describeFormat:@"%@ cannot launch an agent", target]
      failFuture];
  }
  FBSimulator *simulator = (FBSimulator *) target;
  return [[simulator launchAgent:self] mapReplace:FBiOSTargetContinuationDone(self.class.futureType)];
}

#pragma mark Public

- (FBFuture<NSArray<FBProcessOutput *> *> *)createOutputForSimulator:(FBSimulator *)simulator
{
  return [FBFuture futureWithFutures:@[
    [self createOutputForSimulator:simulator selector:@selector(stdOut)],
    [self createOutputForSimulator:simulator selector:@selector(stdErr)],
  ]];
}

#pragma mark Private

- (FBFuture<FBProcessOutput *> *)createOutputForSimulator:(FBSimulator *)simulator selector:(SEL)selector
{
  return [[self
    createDiagnosticForSelector:selector simulator:simulator]
    onQueue:simulator.workQueue fmap:^FBFuture *(id maybeDiagnostic) {
      if ([maybeDiagnostic isKindOfClass:FBDiagnostic.class]) {
        FBDiagnostic *diagnostic = maybeDiagnostic;
        NSString *path = diagnostic.asPath;
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
          return [[FBSimulatorError
            describeFormat:@"Could not file handle for %@ at path '%@' for config '%@'", NSStringFromSelector(selector), path, self]
            failFuture];
        }
        return [FBFuture futureWithResult:[FBProcessOutput outputForFileHandle:handle diagnostic:diagnostic]];
      }
      id<FBFileConsumer> consumer = [self.output performSelector:selector];
      if (![consumer conformsToProtocol:@protocol(FBFileConsumer)]) {
        return [FBFuture futureWithResult:FBProcessOutput.outputForNullDevice];
      }
      return [FBFuture futureWithResult:[FBProcessOutput outputForFileConsumer:consumer]];
    }];
}

@end

#pragma clang diagnostic pop
