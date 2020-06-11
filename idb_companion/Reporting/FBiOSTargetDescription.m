/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetDescription.h"

@interface FBiOSTargetDescription ()

@property (nonatomic, assign, readonly) FBiOSTargetState state;
@property (nonatomic, assign, readonly) FBiOSTargetType targetType;
@property (nonatomic, copy, readonly) FBArchitecture architecture;
@property (nonatomic, copy, readonly) FBDeviceModel model;
@property (nonatomic, copy, readonly) FBDeviceType *deviceType;
@property (nonatomic, copy, readonly) FBOSVersion *osVersion;
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *extendedInformation;
@property (nonatomic, copy, readonly) NSString *name;

@end

@implementation FBiOSTargetDescription

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

- (instancetype)initWithTarget:(id<FBiOSTargetInfo>)target
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _architecture = target.architecture;
  _extendedInformation = target.extendedInformation;
  _model = target.deviceType.model;
  _name = target.name;
  _osVersion = target.osVersion;
  _state = target.state;
  _targetType = target.targetType;
  _udid = target.udid;

  return self;
}

- (id)copyWithZone:(NSZone *)zone
{
  return self;
}

// These values are parsed into TargetDescription in idb/common/types.py, so need to be stable.
static NSString *const KeyArchitecture = @"architecture";
static NSString *const KeyModel = @"model";
static NSString *const KeyName = @"name";
static NSString *const KeyOSVersion = @"os_version";
static NSString *const KeyState = @"state";
static NSString *const KeyType = @"type";
static NSString *const KeyUDID = @"udid";

- (NSDictionary<NSString *, id> *)jsonSerializableRepresentation
{
  NSMutableDictionary<NSString *, id> *representation = [NSMutableDictionary dictionaryWithDictionary:@{
    KeyArchitecture : self.architecture ?: NSNull.null,
    KeyModel : self.model ?: NSNull.null,
    KeyName : self.name ?: NSNull.null,
    KeyOSVersion : self.osVersion.name ?: NSNull.null,
    KeyState : FBiOSTargetStateStringFromState(self.state),
    KeyType : FBiOSTargetTypeStringFromTargetType(self.targetType),
    KeyUDID : self.udid ?: NSNull.null,
  }];
  [representation addEntriesFromDictionary:self.extendedInformation];
  return representation;
}

@end
