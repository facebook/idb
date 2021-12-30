/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestDestination.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

static NSString * const KeyPlatformiOSSimulator = @"iphonesimulator";
static NSString * const KeyPlatformMacOS = @"macos";

@implementation FBXCTestDestination

- (NSString *)xctestPath
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  // References are immutable.
  return self;
}

@end

@implementation FBXCTestDestinationMacOSX

#pragma mark NSObject

- (BOOL)isEqual:(FBXCTestDestinationiPhoneSimulator *)object
{
  return [object isKindOfClass:self.class];
}

- (NSUInteger)hash
{
  return KeyPlatformMacOS.hash;
}

@end

@implementation FBXCTestDestinationiPhoneSimulator

- (instancetype)initWithModel:(nullable FBDeviceModel)model version:(nullable FBOSVersionName)version
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _model = model;
  _version = version;

  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBXCTestDestinationiPhoneSimulator *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return (self.model == object.model || [self.model isEqualToString:object.model])
      && (self.version == object.version || [self.version isEqualToString:object.version]);
}

- (NSUInteger)hash
{
  return self.model.hash ^ self.version.hash ^ KeyPlatformiOSSimulator.hash;
}

@end
