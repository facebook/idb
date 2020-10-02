/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
  XCTAssertEqual(leftMessage->payload.event.button.eventSource, rightMessage->payload.event.button.eventSource);
  XCTAssertEqual(leftMessage->payload.event.button.eventType, rightMessage->payload.event.button.eventType);
  XCTAssertEqual(leftMessage->payload.event.button.eventTarget, rightMessage->payload.event.button.eventTarget);
  XCTAssertEqual(malloc_size(leftMessage), malloc_size(rightMessage));
}

- (void)assertKeyboardPayload:(NSData *)left isEqualTo:(NSData *)right
{
  IndigoMessage *leftMessage = (IndigoMessage *) left.bytes;
  IndigoMessage *rightMessage = (IndigoMessage *) right.bytes;

  XCTAssertEqual(leftMessage->eventType, rightMessage->eventType);
  XCTAssertEqual(leftMessage->innerSize, rightMessage->innerSize);
  XCTAssertEqual(leftMessage->payload.event.button.eventSource, rightMessage->payload.event.button.eventSource);
  XCTAssertEqual(leftMessage->payload.event.button.eventType, rightMessage->payload.event.button.eventType);
  XCTAssertEqual(leftMessage->payload.event.button.eventTarget, rightMessage->payload.event.button.eventTarget);
  XCTAssertEqual(leftMessage->payload.event.button.keyCode, rightMessage->payload.event.button.keyCode);
  XCTAssertEqual(malloc_size(leftMessage), malloc_size(rightMessage));
}

- (void)assertTouchPayload:(NSData *)left isEqualTo:(NSData *)right
{
  IndigoMessage *leftMessage = (IndigoMessage *) left.bytes;
  IndigoMessage *rightMessage = (IndigoMessage *) right.bytes;

  XCTAssertEqual(leftMessage->eventType, rightMessage->eventType);
  XCTAssertEqual(leftMessage->innerSize, rightMessage->innerSize);
  XCTAssertEqual(leftMessage->payload.event.touch.field1, rightMessage->payload.event.touch.field1);
  XCTAssertEqual(leftMessage->payload.event.touch.field2, rightMessage->payload.event.touch.field2);
  XCTAssertEqual(leftMessage->payload.event.touch.field3, rightMessage->payload.event.touch.field3);
  XCTAssertEqual(leftMessage->payload.event.touch.xRatio, rightMessage->payload.event.touch.xRatio);
  XCTAssertEqual(leftMessage->payload.event.touch.yRatio, rightMessage->payload.event.touch.yRatio);
  XCTAssertEqual(leftMessage->payload.event.touch.field6, rightMessage->payload.event.touch.field6);
  XCTAssertEqual(leftMessage->payload.event.touch.field7, rightMessage->payload.event.touch.field7);
  XCTAssertEqual(leftMessage->payload.event.touch.field8, rightMessage->payload.event.touch.field8);
  XCTAssertEqual(leftMessage->payload.event.touch.field9, rightMessage->payload.event.touch.field9);
  XCTAssertEqual(leftMessage->payload.event.touch.field10, rightMessage->payload.event.touch.field10);
  XCTAssertEqual(leftMessage->payload.event.touch.field11, rightMessage->payload.event.touch.field11);
  XCTAssertEqual(leftMessage->payload.event.touch.field12, rightMessage->payload.event.touch.field12);
  XCTAssertEqual(leftMessage->payload.event.touch.field13, rightMessage->payload.event.touch.field13);
  XCTAssertEqual(leftMessage->payload.event.touch.field14, rightMessage->payload.event.touch.field14);
  XCTAssertEqual(leftMessage->payload.event.touch.field15, rightMessage->payload.event.touch.field15);
  XCTAssertEqual(leftMessage->payload.event.touch.field16, rightMessage->payload.event.touch.field16);
  XCTAssertEqual(leftMessage->payload.event.touch.field17, rightMessage->payload.event.touch.field17);
  XCTAssertEqual(leftMessage->payload.event.touch.field18, rightMessage->payload.event.touch.field18);
  XCTAssertEqual(malloc_size(leftMessage), malloc_size(rightMessage));
}

+ (BOOL)supportsHIDIntegrationTests
{
  if (FBXcodeConfiguration.isXcode9OrGreater) {
    return YES;
  }
  NSLog(@"This test is only supported on Xcode 9 or greater");
  return NO;
}

- (void)testButtonPayloads
{
  if (!FBXcodeConfiguration.isXcode9OrGreater) {
    return;
  }

  FBSimulatorIndigoHID *simulatorKit = [FBSimulatorIndigoHID simulatorKitHIDWithError:nil];
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
  if (!FBXcodeConfiguration.isXcode9OrGreater) {
    return;
  }

  FBSimulatorIndigoHID *simulatorKit = [FBSimulatorIndigoHID simulatorKitHIDWithError:nil];
  FBSimulatorIndigoHID *reimplemented = FBSimulatorIndigoHID.reimplemented;
  [self assertKeyboardPayload:[simulatorKit keyboardWithDirection:FBSimulatorHIDDirectionDown keyCode:12]
                    isEqualTo:[reimplemented keyboardWithDirection:FBSimulatorHIDDirectionDown keyCode:12]];
  [self assertKeyboardPayload:[simulatorKit keyboardWithDirection:FBSimulatorHIDDirectionUp keyCode:122]
                    isEqualTo:[reimplemented keyboardWithDirection:FBSimulatorHIDDirectionUp keyCode:122]];
}

- (void)testTouchPayloads
{
  if (!FBXcodeConfiguration.isXcode9OrGreater) {
    return;
  }

  FBSimulatorIndigoHID *simulatorKit = [FBSimulatorIndigoHID simulatorKitHIDWithError:nil];
  FBSimulatorIndigoHID *reimplemented = FBSimulatorIndigoHID.reimplemented;
  [self assertTouchPayload:[simulatorKit touchScreenSize:CGSizeMake(100, 100) direction:FBSimulatorHIDDirectionDown x:10 y:20]
                 isEqualTo:[reimplemented touchScreenSize:CGSizeMake(100, 100) direction:FBSimulatorHIDDirectionDown x:10 y:20]];
  [self assertTouchPayload:[simulatorKit touchScreenSize:CGSizeMake(1000, 1000) direction:FBSimulatorHIDDirectionUp x:230 y:177]
                 isEqualTo:[reimplemented touchScreenSize:CGSizeMake(1000, 1000) direction:FBSimulatorHIDDirectionUp x:230 y:177]];
}

@end
