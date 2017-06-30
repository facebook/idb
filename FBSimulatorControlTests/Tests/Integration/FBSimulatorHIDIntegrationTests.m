/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorControl.h>
#import <FBControlCore/FBControlCore.h>
#import <SimulatorApp/Indigo.h>
#import <malloc/malloc.h>

@interface FBSimulatorHIDIntegrationTests : XCTestCase

@end

@implementation FBSimulatorHIDIntegrationTests

- (void)assertButtonPayload:(NSData *)left isEqualTo:(NSData *)right
{
  IndigoMessage *leftMessage = (IndigoMessage *) left.bytes;
  IndigoMessage *rightMessage = (IndigoMessage *) right.bytes;

  XCTAssertEqual(leftMessage->eventType, rightMessage->eventType);
  XCTAssertEqual(leftMessage->innerSize, rightMessage->innerSize);
  XCTAssertEqual(leftMessage->inner.unionPayload.button.eventSource, rightMessage->inner.unionPayload.button.eventSource);
  XCTAssertEqual(leftMessage->inner.unionPayload.button.eventType, rightMessage->inner.unionPayload.button.eventType);
  XCTAssertEqual(leftMessage->inner.unionPayload.button.eventTarget, rightMessage->inner.unionPayload.button.eventTarget);
  XCTAssertEqual(malloc_size(leftMessage), malloc_size(rightMessage));
}

- (void)assertKeyboardPayload:(NSData *)left isEqualTo:(NSData *)right
{
  IndigoMessage *leftMessage = (IndigoMessage *) left.bytes;
  IndigoMessage *rightMessage = (IndigoMessage *) right.bytes;

  XCTAssertEqual(leftMessage->eventType, rightMessage->eventType);
  XCTAssertEqual(leftMessage->innerSize, rightMessage->innerSize);
  XCTAssertEqual(leftMessage->inner.unionPayload.button.eventSource, rightMessage->inner.unionPayload.button.eventSource);
  XCTAssertEqual(leftMessage->inner.unionPayload.button.eventType, rightMessage->inner.unionPayload.button.eventType);
  XCTAssertEqual(leftMessage->inner.unionPayload.button.eventTarget, rightMessage->inner.unionPayload.button.eventTarget);
  XCTAssertEqual(leftMessage->inner.unionPayload.button.keyCode, rightMessage->inner.unionPayload.button.keyCode);
  XCTAssertEqual(malloc_size(leftMessage), malloc_size(rightMessage));
}

- (void)assertTouchPayload:(NSData *)left isEqualTo:(NSData *)right
{
  IndigoMessage *leftMessage = (IndigoMessage *) left.bytes;
  IndigoMessage *rightMessage = (IndigoMessage *) right.bytes;

  XCTAssertEqual(leftMessage->eventType, rightMessage->eventType);
  XCTAssertEqual(leftMessage->innerSize, rightMessage->innerSize);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field1, rightMessage->inner.unionPayload.touch.field1);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field2, rightMessage->inner.unionPayload.touch.field2);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field3, rightMessage->inner.unionPayload.touch.field3);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.xRatio, rightMessage->inner.unionPayload.touch.xRatio);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.yRatio, rightMessage->inner.unionPayload.touch.yRatio);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field6, rightMessage->inner.unionPayload.touch.field6);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field7, rightMessage->inner.unionPayload.touch.field7);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field8, rightMessage->inner.unionPayload.touch.field8);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field9, rightMessage->inner.unionPayload.touch.field9);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field10, rightMessage->inner.unionPayload.touch.field10);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field11, rightMessage->inner.unionPayload.touch.field11);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field12, rightMessage->inner.unionPayload.touch.field12);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field13, rightMessage->inner.unionPayload.touch.field13);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field14, rightMessage->inner.unionPayload.touch.field14);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field15, rightMessage->inner.unionPayload.touch.field15);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field16, rightMessage->inner.unionPayload.touch.field16);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field17, rightMessage->inner.unionPayload.touch.field17);
  XCTAssertEqual(leftMessage->inner.unionPayload.touch.field18, rightMessage->inner.unionPayload.touch.field18);
  XCTAssertEqual(malloc_size(leftMessage), malloc_size(rightMessage));
}

+ (BOOL)supportsHIDIntegrationTests
{
  if (FBControlCoreGlobalConfiguration.isXcode9OrGreater) {
    return YES;
  }
  NSLog(@"This test is only supported on Xcode 9 or greater");
  return NO;
}

- (void)testButtonPayloads
{
  if (!FBControlCoreGlobalConfiguration.isXcode9OrGreater) {
    return;
  }

  FBSimulatorIndigoHID *simulatorKit = FBSimulatorIndigoHID.simulatorKit;
  FBSimulatorIndigoHID *reimplemented = FBSimulatorIndigoHID.reimplemented;
  [self assertButtonPayload:[simulatorKit buttonWithDirection:FBSimulatorHIDDirectionDown button:FBSimulatorHIDButtonSiri]
                  isEqualTo:[reimplemented buttonWithDirection:FBSimulatorHIDDirectionDown button:FBSimulatorHIDButtonSiri]];
  [self assertButtonPayload:[simulatorKit buttonWithDirection:FBSimulatorHIDDirectionUp button:FBSimulatorHIDButtonApplePay]
                  isEqualTo:[reimplemented buttonWithDirection:FBSimulatorHIDDirectionUp button:FBSimulatorHIDButtonApplePay]];
  [self assertButtonPayload:[simulatorKit buttonWithDirection:FBSimulatorHIDDirectionDown button:FBSimulatorHIDButtonHomeButton]
                  isEqualTo:[reimplemented buttonWithDirection:FBSimulatorHIDDirectionDown button:FBSimulatorHIDButtonHomeButton]];
}

- (void)testKeyboardPayloads
{
  if (!FBControlCoreGlobalConfiguration.isXcode9OrGreater) {
    return;
  }

  FBSimulatorIndigoHID *simulatorKit = FBSimulatorIndigoHID.simulatorKit;
  FBSimulatorIndigoHID *reimplemented = FBSimulatorIndigoHID.reimplemented;
  [self assertKeyboardPayload:[simulatorKit keyboardWithDirection:FBSimulatorHIDDirectionDown keyCode:12]
                    isEqualTo:[reimplemented keyboardWithDirection:FBSimulatorHIDDirectionDown keyCode:12]];
  [self assertKeyboardPayload:[simulatorKit keyboardWithDirection:FBSimulatorHIDDirectionUp keyCode:122]
                    isEqualTo:[reimplemented keyboardWithDirection:FBSimulatorHIDDirectionUp keyCode:122]];
}

- (void)testTouchPayloads
{
  if (!FBControlCoreGlobalConfiguration.isXcode9OrGreater) {
    return;
  }

  FBSimulatorIndigoHID *simulatorKit = FBSimulatorIndigoHID.simulatorKit;
  FBSimulatorIndigoHID *reimplemented = FBSimulatorIndigoHID.reimplemented;
  [self assertTouchPayload:[simulatorKit touchScreenSize:CGSizeMake(100, 100) direction:FBSimulatorHIDDirectionDown x:10 y:20]
                 isEqualTo:[reimplemented touchScreenSize:CGSizeMake(100, 100) direction:FBSimulatorHIDDirectionDown x:10 y:20]];
  [self assertTouchPayload:[simulatorKit touchScreenSize:CGSizeMake(1000, 1000) direction:FBSimulatorHIDDirectionUp x:230 y:177]
                 isEqualTo:[reimplemented touchScreenSize:CGSizeMake(1000, 1000) direction:FBSimulatorHIDDirectionUp x:230 y:177]];
}

@end
