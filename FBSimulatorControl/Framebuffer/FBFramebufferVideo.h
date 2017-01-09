/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBFramebufferDelegate.h>

NS_ASSUME_NONNULL_BEGIN

@class FBFramebufferConfiguration;
@class SimDeviceIOClient;
@protocol FBControlCoreLogger;
@protocol FBSimulatorEventSink;

/**
 A component that encodes video and writes to a file.
 */
@protocol FBFramebufferVideo <NSObject>

/**
 Starts Recording Video.

 @param group the dispatch_group to put asynchronous work into. When the group's blocks have completed the recording has processed. If nil, an anonymous group will be created.
 */
- (void)startRecording:(dispatch_group_t)group;

/**
 Stops Recording Video.

 @param group the dispatch_group to put asynchronous work into. When the group's blocks have completed the recording has processed. If nil, an anonymous group will be created.
 */
- (void)stopRecording:(dispatch_group_t)group;

@end

/**
 An built-in implementation of a video encoder.
 All media activity is serialized on a queue, this queue is internal and should not be used by clients.
 */
@interface FBFramebufferVideo_BuiltIn : NSObject <FBFramebufferVideo, FBFramebufferDelegate>

/**
 The Designated Initializer.

 @param configuration the configuration to use for encoding.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBFramebufferVideo instance.
 */
+ (instancetype)withConfiguration:(FBFramebufferConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

@end

/**
 An implementation of FBFramebufferVideo backed by SimDisplayVideoWriter
 All media activity is serialized on a queue, this queue is internal and should not be used by clients.
 */
@interface FBFramebufferVideo_SimulatorKit : NSObject <FBFramebufferVideo>

/**
 The Designated Initializer.

 @param configuration the configuration to use for encoding.
 @param ioClient the SimDeviceIOClient to connect to.
 @param logger the logger object to log events to, may be nil.
 @param eventSink an event sink to report video output to.
 @return a new FBFramebufferVideo instance.
 */
+ (instancetype)withConfiguration:(FBFramebufferConfiguration *)configuration ioClient:(SimDeviceIOClient *)ioClient logger:(id<FBControlCoreLogger>)logger eventSink:(id<FBSimulatorEventSink>)eventSink;

/**
 YES if this class is supported, NO otherwise.
 */
+ (BOOL)isSupported;

@end

NS_ASSUME_NONNULL_END
