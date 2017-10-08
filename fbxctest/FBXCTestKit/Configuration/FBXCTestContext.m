/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestContext.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestSimulatorFetcher.h"

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

- (nullable FBSimulator *)simulatorForiOSTestRun:(FBXCTestConfiguration *)configuration error:(NSError **)error
{
  if (!self.simulatorFetcher) {
    FBXCTestSimulatorFetcher *fetcher = [FBXCTestSimulatorFetcher fetcherWithWorkingDirectory:configuration.workingDirectory logger:self.logger error:error];
    if (!fetcher) {
      return nil;
    }
    self.simulatorFetcher = fetcher;
  }
  return [self.simulatorFetcher fetchSimulatorForConfiguration:configuration error:error];
}

- (void)finishedExecutionOnSimulator:(FBSimulator *)simulator
{
  [self.simulatorFetcher returnSimulator:simulator error:nil];
}

@end
