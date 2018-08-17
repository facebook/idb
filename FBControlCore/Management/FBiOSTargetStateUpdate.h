// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>
#import <FBControlCore/FBiOSTarget.h>

@protocol FBJSONSerializable, FBJSONDeserializable;

/**
  Holds information about an update to FBiOSTarget
 */
@interface FBiOSTargetStateUpdate : NSObject <FBJSONSerializable, FBJSONDeserializable, NSCopying>

/**
 The Target's UDID.
 */
@property (nonatomic, copy, readonly) NSString *udid;

/**
 The Target's State.
 */
@property (nonatomic, assign, readonly) FBiOSTargetState state;

/**
 The Target's Type.
 */
@property (nonatomic, assign, readonly) FBiOSTargetType type;

/**
 Returns a new Target Update

 @param udid the udid of the target
 @param state the state of the target
 @param type the type of the target
 @return a new Target Update
 */
- (instancetype)initWithUDID:(NSString *)udid state:(FBiOSTargetState)state type:(FBiOSTargetType)type;

@end
