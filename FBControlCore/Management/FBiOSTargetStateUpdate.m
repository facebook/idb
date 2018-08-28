// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBiOSTargetStateUpdate.h"
@implementation FBiOSTargetStateUpdate
@synthesize jsonSerializableRepresentation;

static NSString *const KeyUDID = @"udid";
static NSString *const KeyState = @"state";
static NSString *const KeyType = @"type";

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

- (instancetype)initWithUDID:(NSString *)udid state:(FBiOSTargetState)state type:(FBiOSTargetType)type
{
  self = [super init];
  if (!self) {
    return nil;
  }
  _udid = udid;
  _state = state;
  _type = type;

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
           };
}

+ (instancetype)inflateFromJSON:(id)json error:(NSError **)error {
  NSString *udid = json[KeyUDID];
  FBiOSTargetState state = [json[KeyState] unsignedIntegerValue];
  FBiOSTargetType type = [json[KeyType] unsignedIntegerValue];
  return [[FBiOSTargetStateUpdate alloc] initWithUDID:udid state:state type:type];
}

@end
