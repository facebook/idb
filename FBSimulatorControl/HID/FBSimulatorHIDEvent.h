// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorIndigoHID.h>

static const double DEFAULT_SWIPE_DELTA = 10.0;

@class FBSimulatorHID;

/**
 A HID event that can be performed on a HID
 */
@protocol FBSimulatorHIDEventProtocol <NSObject, NSCopying>

/**
 Materializes the event, performing it on the hid object.

 @param hid the hid to perform on.
 @return A future that resolves when the event has been sent.
 */
- (nonnull FBFuture<NSNull *> *)performOnHID:(nonnull FBSimulatorHID *)hid NS_SWIFT_NAME(sendOn(hid:));

@end

/**
 A HID event that resolves to a single payload, performed on a HID
 */
@protocol FBSimulatorHIDEventPayload <FBSimulatorHIDEventProtocol>

/**
 Constructs the Indigo event data for the reciever.

 @param hid the hid to perform on.
 @return the data produced by the reciever.
 */
- (nonnull NSData *)payloadForHID:(nonnull FBSimulatorHID *)hid;

@end

/**
 A HID event that delays and does not resolve to a event performed on the HID.
 */
@protocol FBSimulatorHIDEventDelay <FBSimulatorHIDEventProtocol>

/**
 The duration of the delay.
 */
@property (nonatomic, readonly, assign) NSTimeInterval duration;

@end

/**
 A HID event that is composed through a discrete set of sub-events
 */
@protocol FBSimulatorHIDEventComposite <FBSimulatorHIDEventProtocol>

/**
 The subevents, may be a FBSimulatorHIDEventPayload or a FBSimulatorHIDEventDelay.
 */
@property (nonnull, nonatomic, readonly, copy) NSArray<id<FBSimulatorHIDEventProtocol>> *events;

@end

// FBSimulatorHIDEvent class is now implemented in Swift.
// The Swift header is imported by the umbrella header FBSimulatorControl.h.
