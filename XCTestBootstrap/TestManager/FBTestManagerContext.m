/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerContext.h"

@implementation FBTestManagerContext

+ (instancetype)contextWithTestRunnerPID:(pid_t)testRunnerPID testRunnerBundleID:(NSString *)testRunnerBundleID sessionIdentifier:(NSUUID *)sessionIdentifier
{
  return [[self alloc] initWithTestRunnerPID:testRunnerPID testRunnerBundleID:testRunnerBundleID sessionIdentifier:sessionIdentifier];
}

- (instancetype)initWithTestRunnerPID:(pid_t)testRunnerPID testRunnerBundleID:(NSString *)testRunnerBundleID sessionIdentifier:(NSUUID *)sessionIdentifier
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testRunnerPID = testRunnerPID;
  _testRunnerBundleID = testRunnerBundleID;
  _sessionIdentifier = sessionIdentifier;

  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return (NSUInteger) self.testRunnerPID ^ self.testRunnerBundleID.hash ^ self.sessionIdentifier.hash;
}

- (BOOL)isEqual:(FBTestManagerContext *)context
{
  if (![context isKindOfClass:self.class]) {
    return NO;
  }

  return self.testRunnerPID == context.testRunnerPID &&
         [self.testRunnerBundleID isEqualToString:context.testRunnerBundleID] &&
         [self.sessionIdentifier isEqual:context.sessionIdentifier];
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

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

@end
