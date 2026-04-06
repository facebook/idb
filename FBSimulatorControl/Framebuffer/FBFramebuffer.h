// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

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

/**
 A Consumer of a Framebuffer.
 */
@protocol FBFramebufferConsumer <NSObject>

/**
 Called when an IOSurface becomes available or invalid

 @param surface the surface, or NULL if a surface is not available/becomes unavailable
 */
- (void)didChangeIOSurface:(nullable IOSurface *)surface;

/**
 Called when screen content has changed.
 */
- (void)didReceiveDamageRect;

@end

// FBFramebuffer class is now implemented in Swift.
// The Swift header is imported by the umbrella header FBSimulatorControl.h.
