/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Protocol for denoting objects that are serializable with NSJSONSerialization.
 */
@protocol FBJSONSerializable

/**
 Returns an NSJSONSerialization-compatible representation of the receiver.
 For more information about permitted types, refer the the NSJSONSerialization Documentation.

 @return an NSJSONSerialization-compatible representation of the receiver.
 */
@property (nonatomic, copy, readonly) id jsonSerializableRepresentation;

@end

/**
 Protocol for providing a way of de-serializing Native JSON Objects to FBSimulatorControl objects.
 */
@protocol FBJSONDeserializable

/**
 Creates and Returns an instance of the receiver, using the input json.

 @param json the JSON to inflate from
 @param error an error out for any that occurs
 @return an instance of the receiver's class if one could be made, nil otherwise
 */
+ (nullable instancetype)inflateFromJSON:(id)json error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
