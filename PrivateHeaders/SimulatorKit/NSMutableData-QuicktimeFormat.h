/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/NSMutableData.h>

@interface NSMutableData (QuicktimeFormat)
+ (id)dataWithVisualSampleEntryForCodingName:(id)arg1 dataReferenceIndex:(id)arg2 width:(id)arg3 height:(id)arg4 horizResolution:(id)arg5 vertResolution:(id)arg6 frameCount:(id)arg7 depth:(id)arg8 extraData:(id)arg9;
+ (id)dataWithVideoMediaHeaderBoxForGraphicsMode:(id)arg1 opColor:(id)arg2;
+ (id)dataWithTrackRunBoxForVersion:(id)arg1 optionalFields:(id)arg2 samples:(id)arg3;
+ (id)dataWithTrackHeaderBoxForVersion:(id)arg1 creationTime:(id)arg2 modificationTime:(id)arg3 trackID:(id)arg4 duration:(id)arg5 layer:(id)arg6 alternateGroup:(id)arg7 volume:(id)arg8 matrix:(double [3][3])arg9 width:(id)arg10 height:(id)arg11;
+ (id)dataWithTrackFragmentHeaderBoxForTrackID:(id)arg1 fields:(id)arg2;
+ (id)dataWithTrackFragmentBoxForFields:(id)arg1;
+ (id)dataWithTrackFragmentBaseMediaDecodeTimeBoxForVersion:(id)arg1 baseMediaDecodeTime:(id)arg2;
+ (id)dataWithTrackExtendsBoxForTrackID:(id)arg1 defaultSampleDescriptionIndex:(id)arg2 defaultSampleDuration:(id)arg3 defaultSampleSize:(id)arg4 defaultSampleFlags:(id)arg5;
+ (id)dataWithTrackBoxForFields:(id)arg1;
+ (id)dataWithTimeToSampleBoxForSamples:(id)arg1;
+ (id)dataWithSampleToChunkBoxForSamples:(id)arg1;
+ (id)dataWithSampleTableSyncSamplesBoxForSampleNumbers:(id)arg1;
+ (id)dataWithSampleTableBoxForFields:(id)arg1;
+ (id)dataWithSampleSizeBoxForSampleSize:(id)arg1 entrySizes:(id)arg2;
+ (id)dataWithSampleDescriptionBoxForEntries:(id)arg1;
+ (id)dataWithMovieHeaderBoxForVersion:(id)arg1 creationTime:(id)arg2 modificationTime:(id)arg3 timeScale:(id)arg4 duration:(id)arg5 rate:(id)arg6 volume:(id)arg7 matrix:(double [3][3])arg8 nextTrackID:(id)arg9;
+ (id)dataWithMovieFragmentHeaderBoxForSequenceNumber:(id)arg1;
+ (id)dataWithMovieFragmentBoxForFields:(id)arg1;
+ (id)dataWithMovieExtendsHeaderBoxForVersion:(id)arg1 fragmentDuration:(id)arg2;
+ (id)dataWithMovieExtendsBoxForFields:(id)arg1;
+ (id)dataWithMovieBoxForFields:(id)arg1;
+ (id)dataWithMediaInformationBoxForFields:(id)arg1;
+ (id)dataWithMediaHeaderBoxForVersion:(id)arg1 creationTime:(id)arg2 modificationTime:(id)arg3 timeScale:(id)arg4 duration:(id)arg5 language:(id)arg6;
+ (id)dataWithMediaDataBoxForMediaData:(id)arg1;
+ (id)dataWithMediaBoxForFields:(id)arg1;
+ (id)dataWithHandlerBoxForHandlerType:(id)arg1 name:(id)arg2;
+ (id)dataWithFullBoxForSize:(id)arg1 type:(id)arg2 version:(id)arg3 flags:(id)arg4;
+ (id)dataWithFileTypeBoxForMajorBrand:(id)arg1 minorVersion:(id)arg2 compatibleBrands:(id)arg3;
+ (id)dataWithDataReferenceBoxForEntries:(id)arg1;
+ (id)dataWithDataInformationBoxForFields:(id)arg1;
+ (id)dataWithDataEntryUrnBoxForFlags:(id)arg1 name:(id)arg2 location:(id)arg3;
+ (id)dataWithDataEntryUrlBoxForFlags:(id)arg1 location:(id)arg2;
+ (id)dataWithChunkOffsetBoxForChunkOffsets:(id)arg1;
+ (id)dataWithBoxForSize:(id)arg1 type:(id)arg2;
@end
