/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestLaunchConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import "FBTestManagerTestReporter.h"

@interface FBTestLaunchConfiguration ()
@property (nonatomic, copy, readwrite) FBApplicationLaunchConfiguration *applicationLaunchConfiguration;
@property (nonatomic, copy, readwrite) NSString *testBundlePath;
@property (nonatomic, assign, readwrite) BOOL shouldInitializeUITesting;
@end

@implementation FBTestLaunchConfiguration

- (instancetype)withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration
{
  self.applicationLaunchConfiguration = applicationLaunchConfiguration;
  return self;
}

- (instancetype)withUITesting:(BOOL)shouldInitializeUITesting
{
  self.shouldInitializeUITesting = shouldInitializeUITesting;
  return self;
}

- (instancetype)withTestBundlePath:(NSString *)testBundlePath
{
  self.testBundlePath = testBundlePath;
  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return
  [[[[self.class alloc]
     withTestBundlePath:self.testBundlePath]
    withApplicationLaunchConfiguration:self.applicationLaunchConfiguration]
   withUITesting:self.shouldInitializeUITesting];
}

#pragma mark NSObject

- (BOOL)isEqual:(FBTestLaunchConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }
  return
  [self.testBundlePath isEqualToString:configuration.testBundlePath] &&
  [self.applicationLaunchConfiguration isEqual:configuration.applicationLaunchConfiguration] &&
  self.shouldInitializeUITesting == configuration.shouldInitializeUITesting;
}

- (NSUInteger)hash
{
  return self.testBundlePath.hash ^ self.applicationLaunchConfiguration.hash ^ (unsigned)self.shouldInitializeUITesting;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
          @"Scale %@ | AppConfig %@ | UITesting %d",
          self.testBundlePath,
          self.applicationLaunchConfiguration,
          self.shouldInitializeUITesting
          ];
}

- (NSString *)shortDescription
{
  return [self description];
}

- (NSString *)debugDescription
{
  return [self description];
}


@end
