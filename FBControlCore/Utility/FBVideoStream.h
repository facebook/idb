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
 @param context unused, pass nil. Present for FBCompressedFrameWriter signature conformance.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write an HEVC frame to the stream, in the Annex-B stream format.
 Extracts VPS, SPS, and PPS parameter sets from keyframes.

 @param sampleBuffer the Sample buffer to write.
 @param context unused, pass nil. Present for FBCompressedFrameWriter signature conformance.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteHEVCFrameToAnnexBStream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write an HEVC frame to the stream, in the MPEG-TS container format.
 Emits PAT and PMT tables on keyframes for mid-stream join support.

 @param sampleBuffer the Sample buffer to write.
 @param context unused, pass nil. Present for FBCompressedFrameWriter signature conformance.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteHEVCFrameToMPEGTSStream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write an H264 frame to the stream, in the MPEG-TS container format.
 Emits PAT and PMT tables on keyframes for mid-stream join support.

 @param sampleBuffer the Sample buffer to write.
 @param context unused, pass nil. Present for FBCompressedFrameWriter signature conformance.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteH264FrameToMPEGTSStream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Muxer context for fragmented MP4 (fMP4) output.
 Minimal state holder — all frame writing logic lives in the C writer functions.
 Created per video stream — no static/global state.
 */
@interface FBFMP4MuxerContext : NSObject

/**
 Create a new fMP4 muxer context.

 @param isHEVC YES for HEVC/H.265, NO for H.264.
 @return a new muxer context.
 */
- (instancetype)initWithHEVC:(BOOL)isHEVC;

@property (nonatomic, assign, readonly) BOOL isHEVC;
@property (nonatomic, assign) BOOL initWritten;
@property (nonatomic, assign) uint32_t sequenceNumber;
@property (nonatomic, assign) uint64_t baseDecodeTime;
@property (nonatomic, assign) uint64_t lastPts90k;

@end

/**
 Write an H264 frame to the stream, in the fMP4 container format.
 Emits ftyp + moov on first keyframe. Each frame is a single-sample moof + mdat fragment.
 NAL data is kept in AVCC (length-prefixed) format — not converted to Annex-B.

 @param sampleBuffer the Sample buffer to write.
 @param context an FBFMP4MuxerContext instance holding per-stream state.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteH264FrameToFMP4Stream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write an HEVC frame to the stream, in the fMP4 container format.

 @param sampleBuffer the Sample buffer to write.
 @param context an FBFMP4MuxerContext instance holding per-stream state.
 @param consumer the consumer to write to.
 @param logger the logger to use.
 @param error an error out for any error that occurs.
 @return YES if successful, NO otherwise.
 */
extern BOOL WriteHEVCFrameToFMP4Stream(CMSampleBufferRef sampleBuffer, id _Nullable context, id<FBDataConsumer> consumer, id<FBControlCoreLogger> logger, NSError **error);

/**
 Write an emsg (Event Message) box for a chapter marker to the fMP4 stream.

 @param context the FBFMP4MuxerContext for PTS tracking.
 @param text the chapter/marker label text.
 @param consumer the data consumer to write the emsg box to.
 */
extern void FBFMP4WriteEmsgBox(FBFMP4MuxerContext *context, NSString *text, id<FBDataConsumer> consumer);

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
 The first TS packet of each access unit carries a PCR adaptation field.

 @param pesData the PES packet data.
 @param isKeyFrame YES to prepend PAT+PMT for mid-stream join support.
 @param streamType the MPEG-TS stream type for the PMT (e.g. 0x24 for HEVC, 0x1B for H264).
 @param pts90k the presentation timestamp in 90kHz units, used as the PCR base value.
 @param videoContinuityCounter pointer to the video PID continuity counter.
 @param patContinuityCounter pointer to the PAT continuity counter.
 @param pmtContinuityCounter pointer to the PMT continuity counter.
 @return the concatenated TS packets.
 */
extern NSData *FBMPEGTSPacketizePES(NSData *pesData, BOOL isKeyFrame, uint8_t streamType,
                                     uint64_t pts90k,
                                     uint8_t *videoContinuityCounter,
                                     uint8_t *patContinuityCounter, uint8_t *pmtContinuityCounter);

/**
 PID for the timed metadata elementary stream (ID3).
 */
extern const uint16_t FBMPEGTSMetadataPID;

/**
 Create a PMT that optionally includes a timed metadata stream entry alongside the video stream.

 @param continuityCounter pointer to the PMT continuity counter, incremented on each call.
 @param streamType the MPEG-TS stream type for the video elementary stream.
 @param includeMetadataStream YES to add a second stream entry for ID3 timed metadata on MetadataPID.
 @return a 188-byte TS packet.
 */
extern NSData *FBMPEGTSCreatePMTPacketWithMetadata(uint8_t *continuityCounter, uint8_t streamType, BOOL includeMetadataStream);

/**
 Build MPEG-TS packets containing an ID3v2 TXXX frame with the given text at the given PTS.

 @param text the chapter/marker label text.
 @param pts90k the presentation timestamp in 90kHz units.
 @param metadataContinuityCounter pointer to the metadata PID continuity counter, incremented on each call.
 @return one or more concatenated 188-byte TS packets on MetadataPID.
 */
extern NSData *FBMPEGTSCreateTimedMetadataPackets(NSString *text, uint64_t pts90k, uint8_t *metadataContinuityCounter);

/**
 Enable the timed metadata stream in the MPEG-TS muxer.
 After calling this, keyframe PMT emissions will include the metadata stream entry.
 */
extern void FBMPEGTSEnableMetadataStream(void);

/**
 Write a timed metadata marker into the MPEG-TS output stream at the current video PTS.
 Thread-safe: may be called from any thread while video encoding is active.

 @param text the chapter/marker label text.
 @param consumer the data consumer to write TS packets to (typically the same consumer as the video stream).
 */
extern void FBMPEGTSWriteTimedMetadata(NSString *text, id<FBDataConsumer> consumer);

NS_ASSUME_NONNULL_END
