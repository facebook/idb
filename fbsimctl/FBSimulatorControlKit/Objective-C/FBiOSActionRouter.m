/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBiOSActionRouter.h"

#import "FBUploadBuffer.h"

@implementation FBiOSActionRouter

#pragma mark Initializers

+ (instancetype)routerForTarget:(id<FBiOSTarget>)target
{
  NSMutableSet<Class> *classes = [NSMutableSet set];
  [classes addObjectsFromArray:self.defaultActionClasses];
  [classes addObjectsFromArray:target.actionClasses];
  return [self routerForTarget:target actionClasses:classes.allObjects];
}

+ (instancetype)routerForTarget:(id<FBiOSTarget>)target actionClasses:(NSArray<Class> *)actionClasses
{
  NSDictionary<FBiOSTargetFutureType, Class> *actionMapping = [self actionMappingForActionClasses:actionClasses];
  return [[self alloc] initWithTarget:target actionMapping:actionMapping];
}

+ (NSDictionary<FBiOSTargetFutureType, Class> *)actionMappingForActionClasses:(NSArray<Class> *)actionClasses
{
  NSMutableDictionary<FBiOSTargetFutureType, Class> *mapping = [NSMutableDictionary dictionary];
  for (Class actionClass in actionClasses) {
    NSAssert(([actionClass conformsToProtocol:@protocol(FBiOSTargetFuture)]), @"%@ is not an action class", actionClass);
    FBiOSTargetFutureType actionType = [actionClass futureType];
    mapping[actionType] = actionClass;
  }
  return [mapping copy];
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target actionMapping:(NSDictionary<FBiOSTargetFutureType, Class> *)actionMapping
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _actionMapping = actionMapping;

  return self;
}

+ (NSArray<Class> *)defaultActionClasses
{
  return @[
    FBApplicationLaunchConfiguration.class,
    FBUploadHeader.class,
    FBListApplicationsConfiguration.class,
  ];
}

#pragma mark Serialization

static NSString *const KeyActionType = @"action";
static NSString *const KeyActionPayload = @"payload";
static NSString *const KeyUDID = @"udid";

- (nullable id<FBiOSTargetFuture>)actionFromJSON:(NSDictionary<NSString *, id> *)json error:(NSError **)error
{
  if (![FBCollectionInformation isDictionaryHeterogeneous:json keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Dictionary<String, Object>", json]
      fail:error];
  }

  FBiOSTargetFutureType actionType = json[KeyActionType];
  Class actionClass = self.actionMapping[actionType];
  if (!actionClass) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a valid action name in %@ for %@", actionType, [FBCollectionInformation oneLineDescriptionFromArray:self.actionMapping.allKeys], KeyActionType]
      fail:error];
  }
  NSDictionary<NSString *, id> *payload = json[KeyActionPayload];
  if (![FBCollectionInformation isDictionaryHeterogeneous:payload keyClass:NSString.class valueClass:NSObject.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a Dictionary<String, Any> for %@", payload, KeyActionPayload]
      fail:error];
  }
  NSString *udid = json[KeyUDID];
  if (udid && ![udid isKindOfClass:NSString.class]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not a String for %@", udid, KeyUDID]
      fail:error];
  }
  if (udid && ![udid isEqualToString:self.target.udid]) {
    return [[FBControlCoreError
      describeFormat:@"%@ is not the udid of the target %@", udid, self.target.udid]
      fail:error];
  }

  id action = [actionClass inflateFromJSON:payload error:error];
  if ([action conformsToProtocol:@protocol(FBiOSTargetFuture)]) {
    return action;
  } else {
    return [[FBControlCoreError
      describeFormat:@"%@ is not routable", action]
      fail:error];
  }
}

- (NSDictionary<NSString *, id> *)jsonFromAction:(id<FBiOSTargetFuture>)action
{
  NSMutableDictionary<NSString *, id> *json = [[FBiOSActionRouter jsonFromAction:action] mutableCopy];
  json[KeyUDID] = self.target.udid;
  return [json copy];
}

+ (NSDictionary<NSString *, id> *)jsonFromAction:(id<FBiOSTargetFuture>)action
{
  return @{
    KeyActionType: [action.class futureType],
    KeyActionPayload: action.jsonSerializableRepresentation,
  };
}

@end
