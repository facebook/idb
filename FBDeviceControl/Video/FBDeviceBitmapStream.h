/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class AVCaptureSession;
@class FBBitmapStreamAttributes;
@protocol FBFileConsumer;

/**
 A Video Encoder that Writes to a Stream.
 */
@interface FBDeviceBitmapStream : NSObject <FBBitmapStream>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param session the Session to record from.
 @param encoding The encoding of the stream
 @param logger the logger to log to.
 @param error an error out for any error that occurs.
 @return a new Video Encoder.
 */
+ (instancetype)streamWithSession:(AVCaptureSession *)session encoding:(FBBitmapStreamEncoding)encoding logger:(id<FBControlCoreLogger>)logger error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
