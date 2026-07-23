/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class IOSurface;

/**
 Stats tracked by the framebuffer from the simulator's damage/IOSurface callbacks.
 */
typedef struct {
  NSUInteger damageCallbackCount;
  NSUInteger damageRectCount;
  NSUInteger emptyDamageCallbackCount;
  NSUInteger ioSurfaceChangeCount;
} FBFramebufferStats;

@protocol FBFramebufferConsumer;
