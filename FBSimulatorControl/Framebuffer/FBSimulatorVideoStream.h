/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Edge insets that extend the output frame dimensions beyond the source framebuffer.
 Each edge adds opaque pixels for overlay content (label bars, diagnostic stats, etc.).
 */
typedef struct {
  NSUInteger top;
  NSUInteger bottom;
  NSUInteger left;
  NSUInteger right;
} FBVideoStreamEdgeInsets;

/**
 Stats tracked by the video encoder (VideoToolbox).
 Zeroed if the stream uses a non-encoded format (e.g. bitmap/BGRA).
 */
typedef struct {
  NSUInteger callbackCount;
  NSUInteger writeCount;
  NSUInteger dropCount;
  NSUInteger writeFailureCount;
  NSUInteger encodeErrorCount;
  NSUInteger tornFrameCount;
  NSUInteger totalEncodedBytes;
  CFTimeInterval totalEncodeSubmitSeconds;
} FBVideoEncoderStats;
