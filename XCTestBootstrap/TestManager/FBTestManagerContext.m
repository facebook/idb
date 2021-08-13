/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerContext.h"

@implementation FBTestManagerContext

- (instancetype)initWithSessionIdentifier:(NSUUID *)sessionIdentifier timeout:(NSTimeInterval)timeout testHostLaunchConfiguration:(FBApplicationLaunchConfiguration *)testHostLaunchConfiguration  testedApplicationAdditionalEnvironment:(nullable NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _sessionIdentifier = sessionIdentifier;
  _timeout = timeout;
  _testHostLaunchConfiguration = testHostLaunchConfiguration;
  _testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Test Host %@ | Session ID %@ | Timeout %f",
    self.testHostLaunchConfiguration,
    self.sessionIdentifier.UUIDString,
    self.timeout
  ];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
  // Class is immutable.
  return self;
}

@end
