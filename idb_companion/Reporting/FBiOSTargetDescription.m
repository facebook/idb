/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSTargetDescription.h"

@interface FBiOSTargetDescription ()

@property (nonatomic, copy, readonly) FBDeviceModel model;
@end

@implementation FBiOSTargetDescription

@synthesize deviceType = _deviceType;
@synthesize extendedInformation = _extendedInformation;
@synthesize name = _name;
@synthesize osVersion = _osVersion;
@synthesize state = _state;
@synthesize targetType = _targetType;
@synthesize udid = _udid;
@synthesize uniqueIdentifier = _uniqueIdentifier;
@synthesize architectures = _architectures;

- (instancetype)initWithTarget:(id<FBiOSTargetInfo>)target
{
  self = [super init];
  if (!self) {
    return nil;
  }

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

- (NSDictionary<NSString *, id> *)asJSON
{
  NSMutableDictionary<NSString *, id> *representation = [NSMutableDictionary dictionaryWithDictionary:@{
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
