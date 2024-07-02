/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#import <FBControlCore/FBiOSTargetOperation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBDataConsumer;
@protocol FBDataConsumerSync;

/**
 Streams Bitmaps to a File Sink
 */
@protocol FBVideoStream <FBiOSTargetOperation>

#pragma mark Public Methods

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
 Returns true if consumer is ready to process another frame, false if consumer buffered data exceedes allowed limit
 
 @param consumer consumer
 @return True if next frame should be pushed; False if frame should be dropped
 */
extern BOOL checkConsumerBufferLimit(id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger);

/**
 Write an H264 frame to the stream, in the Annex-B stream format.

 @param sampleBuffer the Sample buffer to write.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write a JPEG frame to the MJPEG stream.

 @param jpegDataBuffer the JPEG data to write.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteJPEGDataToMJPEGStream(CMBlockBufferRef jpegDataBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write a Minicap frame to the stream, based upon using the provided JPEG Block Buffer.

 @param jpegDataBuffer the JPEG data to write.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteJPEGDataToMinicapStream(CMBlockBufferRef jpegDataBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write a Minicap header to the stream.

 @param width the width of the image stream.
 @param height the height of the image stream.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
*/
extern BOOL WriteMinicapHeaderToStream(uint32 width, uint32 height, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

NS_ASSUME_NONNULL_END
