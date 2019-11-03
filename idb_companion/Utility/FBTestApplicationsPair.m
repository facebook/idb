/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestApplicationsPair.h"

@implementation FBTestApplicationsPair

#pragma mark Initializers

- (instancetype)initWithApplicationUnderTest:(FBInstalledApplication *)applicationUnderTest testHostApp:(FBInstalledApplication *)testHostApp
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _applicationUnderTest = applicationUnderTest;
  _testHostApp = testHostApp;

  return self;
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:@"AUT %@, Test Host %@", self.applicationUnderTest, self.testHostApp];
}

@end
