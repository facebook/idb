// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 Commands to perform on a Simulator, related to photos/videos on the device
 */
@protocol FBSimulatorMediaCommandsProtocol <NSObject, FBiOSTargetCommand>

/**
 Add media files to the simulator

 @param mediaFileURLs local paths to the media files to add
 @return A future that resolves when the media has been added.
 */
- (nonnull FBFuture<NSNull *> *)addMedia:(nonnull NSArray<NSURL *> *)mediaFileURLs;

@end

// FBSimulatorMediaCommands class is now implemented in Swift.
// The Swift header is imported by the umbrella header FBSimulatorControl.h.
