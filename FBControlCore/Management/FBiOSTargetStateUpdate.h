/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

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
 The Target's Name.
 */
@property (nonatomic, assign, readonly) NSString *name;

/**
 The Target's OS Version.
 */
@property (nonatomic, assign, readonly) FBOSVersion *osVersion;

/**
 The Target's Architecture.
 */
@property (nonatomic, assign, readonly) FBArchitecture architecture;

/**
 Returns a new Target Update

 @param udid the udid of the target
 @param state the state of the target
 @param type the type of the target
 @return a new Target Update
 */
- (instancetype)initWithUDID:(NSString *)udid state:(FBiOSTargetState)state type:(FBiOSTargetType)type name:(NSString *)name osVersion:(FBOSVersion *)osVersion architecture:(FBArchitecture)architecture;

@end
