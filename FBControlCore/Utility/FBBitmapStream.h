/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#import <FBControlCore/FBJSONConversion.h>
#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Termination Handle Type for an Recording Operation.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeVideoStreaming;

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

@protocol FBDataConsumer;

/**
 Streams Bitmaps to a File Sink
 */
@protocol FBBitmapStream <FBiOSTargetContinuation>

#pragma mark Public Methods

/**
 Obtains a Dictonary Describing the Attributes of the Stream.

 @return a Future wrapping the stream attributes.
 */
- (FBFuture<FBBitmapStreamAttributes *> *)streamAttributes;

/**
 Starts the Streaming, to a Data Consumer.

 @param consumer the consumer to consume the bytes to.
 @return A future that resolves when the streaming has started.
 */
- (FBFuture<NSNull *> *)startStreaming:(id<FBDataConsumer>)consumer;

/**
 Stops the Streaming.

 @return A future that resolves when the streaming has stopped.
 */
- (FBFuture<NSNull *> *)stopStreaming;

@end

/**
 Write an H264 frame to the stream, in the Annex-B stream format.

 @param sampleBuffer the Sample buffer to write/
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

NS_ASSUME_NONNULL_END
