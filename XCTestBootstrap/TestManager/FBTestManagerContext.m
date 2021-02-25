/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerContext.h"

@implementation FBTestManagerContext

- (instancetype)initWithTestHostLaunchConfiguration:(FBApplicationLaunchConfiguration *)testHostLaunchConfiguration sessionIdentifier:(NSUUID *)sessionIdentifier testedApplicationAdditionalEnvironment:(nullable NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testHostLaunchConfiguration = testHostLaunchConfiguration;
  _sessionIdentifier = sessionIdentifier;
  _testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Test Host %@ | Session ID %@",
    self.testHostLaunchConfiguration,
    self.sessionIdentifier.UUIDString
  ];
}

#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone
{
  // Class is immutable.
  return self;
}

@end
