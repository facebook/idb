/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestContext.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestSimulatorFetcher.h"
#import "FBXCTestCommandLine.h"

@interface FBXCTestContext ()

@property (nonatomic, strong, readwrite, nullable) FBXCTestSimulatorFetcher *simulatorFetcher;

@end

@implementation FBXCTestContext

#pragma mark Initializers

+ (instancetype)contextWithReporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger
{
  return [[FBXCTestContext alloc] initWithReporter:reporter logger:logger];
}


- (instancetype)initWithReporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reporter = reporter;
  _logger = logger;

  return self;
}

#pragma mark Public

- (FBFuture<FBSimulator *> *)simulatorForCommandLine:(FBXCTestCommandLine *)commmandLine
{
  if (!self.simulatorFetcher) {
    NSError *error = nil;
    FBXCTestSimulatorFetcher *fetcher = [FBXCTestSimulatorFetcher fetcherWithWorkingDirectory:commmandLine.configuration.workingDirectory logger:self.logger error:&error];
    if (!fetcher) {
      return [FBFuture futureWithError:error];
    }
    self.simulatorFetcher = fetcher;
  }
  return [self.simulatorFetcher fetchSimulatorForCommandLine:commmandLine];
}

- (FBFuture<NSNull *> *)finishedExecutionOnSimulator:(FBSimulator *)simulator
{
  return [self.simulatorFetcher returnSimulator:simulator];
}

@end
