/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorHIDEvent.h>

@interface FBSimulatorHIDEventOrientationTests : XCTestCase
@end

@implementation FBSimulatorHIDEventOrientationTests

- (void)testOrientationEventEquality
{
  id<FBSimulatorHIDEvent> event1 = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationLandscapeLeft];
  id<FBSimulatorHIDEvent> event2 = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationLandscapeLeft];
  XCTAssertEqualObjects(event1, event2);
}

- (void)testOrientationEventInequality
{
  id<FBSimulatorHIDEvent> event1 = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationPortrait];
  id<FBSimulatorHIDEvent> event2 = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationLandscapeLeft];
  XCTAssertNotEqualObjects(event1, event2);
}

- (void)testOrientationEventCopying
{
  id<FBSimulatorHIDEvent> event = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationPortrait];
  id<FBSimulatorHIDEvent> copy = [event copyWithZone:nil];
  XCTAssertEqual(event, copy, @"Immutable event should return self from copy");
}

- (void)testOrientationEventHash
{
  id<FBSimulatorHIDEvent> portrait = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationPortrait];
  id<FBSimulatorHIDEvent> landscape = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationLandscapeLeft];
  XCTAssertNotEqual([portrait hash], [landscape hash]);

  id<FBSimulatorHIDEvent> portrait2 = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationPortrait];
  XCTAssertEqual([portrait hash], [portrait2 hash]);
}

- (void)testOrientationEventDescription
{
  id<FBSimulatorHIDEvent> event = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationLandscapeLeft];
  NSString *description = [event description];
  XCTAssertTrue([description containsString:@"landscape_left"], @"Description should contain orientation name, got: %@", description);
}

- (void)testSetOrientationFactory
{
  id<FBSimulatorHIDEvent> event = [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationPortraitUpsideDown];
  XCTAssertNotNil(event);
  XCTAssertTrue([event conformsToProtocol:@protocol(FBSimulatorHIDEvent)]);
}

- (void)testAllOrientationsCreateDistinctEvents
{
  NSArray<id<FBSimulatorHIDEvent>> *events = @[
    [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationPortrait],
    [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationPortraitUpsideDown],
    [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationLandscapeRight],
    [FBSimulatorHIDEvent setOrientation:FBSimulatorHIDDeviceOrientationLandscapeLeft],
  ];
  NSSet *uniqueEvents = [NSSet setWithArray:events];
  XCTAssertEqual(uniqueEvents.count, 4u, @"All four orientations should be distinct");
}

@end
