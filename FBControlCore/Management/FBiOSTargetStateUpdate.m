/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetStateUpdate.h"
#import "FBiOSTargetConfiguration.h"
@implementation FBiOSTargetStateUpdate
@synthesize jsonSerializableRepresentation;

static NSString *const KeyUDID = @"udid";
static NSString *const KeyState = @"state";
static NSString *const KeyType = @"type";
static NSString *const KeyName = @"name";
static NSString *const KeyOsVersion = @"os_version";
static NSString *const KeyArchitecture = @"architecture";

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

- (instancetype)initWithUDID:(NSString *)udid state:(FBiOSTargetState)state type:(FBiOSTargetType)type name:(NSString *)name osVersion:(FBOSVersion *)osVersion architecture:(FBArchitecture)architecture;
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _udid = udid;
  _state = state;
  _type = type;
  _name = name;
  _osVersion = osVersion;
  _architecture = architecture;

  return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
  return self;
}

- (NSDictionary<NSString *, id> *)jsonSerializableRepresentation
{
  return @{
           KeyUDID : self.udid,
           KeyState : FBiOSTargetStateStringFromState(self.state),
           KeyType : FBiOSTargetTypeStringFromTargetType(self.type),
           KeyName : self.name ?: @"unknown",
           KeyOsVersion : self.osVersion.name ?: @"unknown",
           KeyArchitecture : self.architecture ?: @"unknown",
           };
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error {
  NSString *udid = json[KeyUDID];
  FBiOSTargetState state = [json[KeyState] unsignedIntegerValue];
  FBiOSTargetType type = [json[KeyType] unsignedIntegerValue];
  NSString *name = json[KeyName];
  FBOSVersion *osVersion = [FBOSVersion genericWithName:json[KeyOsVersion]];
  NSString *architecture = json[KeyArchitecture];
  return [[FBiOSTargetStateUpdate alloc] initWithUDID:udid state:state type:type name:name osVersion:osVersion architecture:architecture];
}

@end
