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

@end

@interface FBXCTestContext_Fetch : FBXCTestContext

@property (nonatomic, strong, readwrite, nullable) FBXCTestSimulatorFetcher *simulatorFetcher;

@end

@interface FBXCTestContext_Passed : FBXCTestContext

@property (nonatomic, strong, readonly) FBSimulator *simulator;

- (instancetype)initWithSimulator:(FBSimulator *)simulator reporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger;

@end

@implementation FBXCTestContext

#pragma mark Initializers

+ (instancetype)contextWithReporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger
{
  return [[FBXCTestContext_Fetch alloc] initWithReporter:reporter logger:logger];
}

+ (instancetype)contextWithSimulator:(FBSimulator *)simulator reporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger
{
  return [[FBXCTestContext_Passed alloc] initWithSimulator:simulator reporter:reporter logger:logger];
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

#pragma mark Public Methods

- (nullable FBSimulator *)simulatorForiOSTestRun:(FBXCTestConfiguration *)configuration error:(NSError **)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

- (void)finishedExecutionOnSimulator:(FBSimulator *)simulator
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
}

@end

@implementation FBXCTestContext_Fetch

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

@implementation FBXCTestContext_Passed

- (instancetype)initWithSimulator:(FBSimulator *)simulator reporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger
{
  self = [super initWithReporter:reporter logger:logger];
  if (!self) {
    return nil;
  }

  _simulator = simulator;

  return self;
}

- (nullable FBSimulator *)simulatorForiOSTestRun:(FBXCTestConfiguration *)configuration error:(NSError **)error
{
  return self.simulator;
}

- (void)finishedExecutionOnSimulator:(FBSimulator *)simulator
{
  // Do nothing.
}

@end
