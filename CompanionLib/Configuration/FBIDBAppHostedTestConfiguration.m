/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBIDBAppHostedTestConfiguration.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

@implementation FBIDBAppHostedTestConfiguration

- (instancetype)initWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration coverageConfiguration:(nullable FBCodeCoverageConfiguration *)coverageConfiguration
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  _testLaunchConfiguration = testLaunchConfiguration;
  _coverageConfiguration = coverageConfiguration;
  
  return self;
}

@end
