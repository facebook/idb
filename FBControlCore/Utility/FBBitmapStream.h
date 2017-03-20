/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBTerminationHandle.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Termination Handle Type for an Recording Operation.
 */
extern FBTerminationHandleType const FBTerminationHandleTypeVideoStreaming;

/**
 A Value container for Stream Attributes.
 */
@interface FBBitmapStreamAttributes : NSObject <FBJSONSerializable>

/**
 The Underlying Dictionary Representation.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *attributes;

/**
 The Designated Initializer
 */
- (instancetype)initWithAttributes:(NSDictionary<NSString *, id> *)attributes;

@end

@protocol FBFileConsumer;

/**
 Streams Bitmaps to a File Sink
 */
@protocol FBBitmapStream <FBTerminationHandle>

#pragma mark Public Methods

/**
 Obtains a Dictonary Describing the Attributes of the Stream.

 @param error an error out for any error that occurs.
 @return the Attributes if successful, NO otherwise.
 */
- (nullable FBBitmapStreamAttributes *)streamAttributesWithError:(NSError **)error;

/**
 Starts the Streaming, to a File Consumer.

 @param consumer the consumer to consume the bytes. to.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise,
 */
- (BOOL)startStreaming:(id<FBFileConsumer>)consumer error:(NSError **)error;

/**
 Stops the Streaming.

 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise,
 */
- (BOOL)stopStreamingWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
