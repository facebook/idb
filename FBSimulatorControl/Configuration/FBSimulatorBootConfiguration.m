/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorBootConfiguration.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"

@implementation FBSimulatorBootConfiguration

#pragma mark Initializers

+ (instancetype)defaultConfiguration
{
  static dispatch_once_t onceToken;
  static FBSimulatorBootConfiguration *configuration;
  dispatch_once(&onceToken, ^{
    configuration = [[FBSimulatorBootConfiguration alloc] initWithOptions:FBSimulatorBootOptionsVerifyUsable environment:@{}];
  });
  return configuration;
}

- (instancetype)initWithOptions:(FBSimulatorBootOptions)options environment:(NSDictionary<NSString *, NSString *> *)environment
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _options = options;
  _environment = environment;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // Instances are immutable.
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBSimulatorBootConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return self.options == configuration.options &&
    (self.environment == configuration.environment || [self.environment isEqualToDictionary:configuration.environment]);
}
  
- (NSUInteger)hash
{
  return self.options ^ self.environment.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Boot Environment %@ | Options %@",
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.environment],
    [FBCollectionInformation oneLineDescriptionFromArray:[FBSimulatorBootConfiguration stringsFromBootOptions:self.options]]
  ];
}

#pragma mark Utility

static NSString *const BootOptionStringDirectLaunch = @"Direct Launch";

+ (NSArray<NSString *> *)stringsFromBootOptions:(FBSimulatorBootOptions)options
{
  NSMutableArray<NSString *> *strings = [NSMutableArray array];
  if ((options & FBSimulatorBootOptionsTieToProcessLifecycle) == FBSimulatorBootOptionsTieToProcessLifecycle) {
    [strings addObject:BootOptionStringDirectLaunch];
  }
  return [strings copy];
}

@end
