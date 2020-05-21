/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetStateUpdate.h"
#import "FBiOSTargetConfiguration.h"

@interface FBiOSTargetStateUpdate ()

@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) FBOSVersion *osVersion;
@property (nonatomic, assign, readonly) FBiOSTargetState state;
@property (nonatomic, assign, readonly) FBiOSTargetType targetType;
@property (nonatomic, assign, readonly) FBArchitecture architecture;
@property (nonatomic, assign, readonly) NSDictionary<NSString *, id> *extendedInformation;

@end


@implementation FBiOSTargetStateUpdate

static NSString *FBiOSTargetTypeStringFromTargetType(FBiOSTargetType targetType)
{
  if ((targetType & FBiOSTargetTypeDevice) == FBiOSTargetTypeDevice) {
    return @"device";
  } else if ((targetType & FBiOSTargetTypeSimulator) == FBiOSTargetTypeSimulator) {
    return @"simulator";
  } else if ((targetType & FBiOSTargetTypeLocalMac) == FBiOSTargetTypeLocalMac) {
    return @"mac";
  }
  return nil;
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _udid = target.udid;
  _state = target.state;
  _targetType = target.targetType;
  _name = target.name;
  _osVersion = target.osVersion;
  _architecture = target.architecture;
  _extendedInformation = target.extendedInformation;

  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  return self;
}

static NSString *const KeyUDID = @"udid";
static NSString *const KeyState = @"state";
static NSString *const KeyType = @"type";
static NSString *const KeyName = @"name";
static NSString *const KeyOsVersion = @"os_version";
static NSString *const KeyArchitecture = @"architecture";

- (NSDictionary<NSString *, id> *)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *representation = [NSMutableDictionary dictionaryWithDictionary:@{
    KeyUDID : self.udid,
    KeyState : FBiOSTargetStateStringFromState(self.state),
    KeyType : FBiOSTargetTypeStringFromTargetType(self.targetType),
    KeyName : self.name ?: @"unknown",
    KeyOsVersion : self.osVersion.name ?: @"unknown",
    KeyArchitecture : self.architecture ?: @"unknown",
  }];
  [representation addEntriesFromDictionary:self.extendedInformation];
  return representation;
}

@end
