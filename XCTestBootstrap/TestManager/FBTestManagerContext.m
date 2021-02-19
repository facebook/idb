/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerContext.h"

@implementation FBTestManagerContext

- (instancetype)initWithTestRunnerPID:(pid_t)testRunnerPID testRunnerBundleID:(NSString *)testRunnerBundleID sessionIdentifier:(NSUUID *)sessionIdentifier testedApplicationAdditionalEnvironment:(nullable NSDictionary<NSString *, NSString *> *)testedApplicationAdditionalEnvironment
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testRunnerPID = testRunnerPID;
  _testRunnerBundleID = testRunnerBundleID;
  _sessionIdentifier = sessionIdentifier;
  _testedApplicationAdditionalEnvironment = testedApplicationAdditionalEnvironment;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Test Host PID %d | Test Host Bundle %@ | Session ID %@",
    self.testRunnerPID,
    self.testRunnerBundleID,
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
