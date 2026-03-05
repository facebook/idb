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
 Write an HEVC frame to the stream, in the Annex-B stream format.
 Extracts VPS, SPS, and PPS parameter sets from keyframes.

 @param sampleBuffer the Sample buffer to write.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteHEVCFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write an HEVC frame to the stream, in the MPEG-TS container format.
 Emits PAT and PMT tables on keyframes for mid-stream join support.

 @param sampleBuffer the Sample buffer to write.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteHEVCFrameToMPEGTSStream(CMSampleBufferRef sampleBuffer, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

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
extern BOOL WriteMinicapHeaderToStream(uint32_t width, uint32_t height, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Compute MPEG-2 CRC32 over a byte buffer.

 @param data the input bytes.
 @param length the number of bytes.
 @return the CRC32 value.
 */
extern uint32_t FBMPEGTS_CRC32(const uint8_t *data, size_t length);

/**
 Create a PAT (Program Association Table) MPEG-TS packet.

 @param continuityCounter pointer to the PAT continuity counter, incremented on each call.
 @return a 188-byte TS packet.
 */
extern NSData *FBMPEGTSCreatePATPacket(uint8_t *continuityCounter);

/**
 Create a PMT (Program Map Table) MPEG-TS packet.

 @param continuityCounter pointer to the PMT continuity counter, incremented on each call.
 @param streamType the MPEG-TS stream type for the video elementary stream (e.g. 0x24 for HEVC, 0x1B for H264).
 @return a 188-byte TS packet.
 */
extern NSData *FBMPEGTSCreatePMTPacket(uint8_t *continuityCounter, uint8_t streamType);

/**
 Packetize a PES payload into one or more 188-byte MPEG-TS packets.
 Emits PAT and PMT before video packets when isKeyFrame is YES.

 @param pesData the PES packet data.
 @param isKeyFrame YES to prepend PAT+PMT for mid-stream join support.
 @param streamType the MPEG-TS stream type for the PMT (e.g. 0x24 for HEVC, 0x1B for H264).
 @param videoContinuityCounter pointer to the video PID continuity counter.
 @param patContinuityCounter pointer to the PAT continuity counter.
 @param pmtContinuityCounter pointer to the PMT continuity counter.
 @return the concatenated TS packets.
 */
extern NSData *FBMPEGTSPacketizePES(NSData *pesData, BOOL isKeyFrame, uint8_t streamType,
                                     uint8_t *videoContinuityCounter,
                                     uint8_t *patContinuityCounter, uint8_t *pmtContinuityCounter);

NS_ASSUME_NONNULL_END
