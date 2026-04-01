/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBSimulatorControl/FBSimulatorPurpleHID.h>

#import <mach/mach.h>

@interface FBSimulatorPurpleHIDTests : XCTestCase
@end

@implementation FBSimulatorPurpleHIDTests

- (uint32_t)uint32AtOffset:(NSUInteger)offset inData:(NSData *)data
{
  uint32_t value;
  [data getBytes:&value range:NSMakeRange(offset, sizeof(value))];
  return value;
}

- (void)testOrientationEventSize
{
  FBSimulatorPurpleHID *purple = [FBSimulatorPurpleHID purple];
  NSData *data = [purple orientationEvent:FBSimulatorHIDDeviceOrientationPortrait];
  XCTAssertEqual(data.length, 112u, @"Buffer should be 112 bytes (aligned to 8)");
  XCTAssertEqual([self uint32AtOffset:0x04 inData:data], 108u, @"msgh_size should be 108");
}

- (void)testOrientationEventMachHeader
{
  FBSimulatorPurpleHID *purple = [FBSimulatorPurpleHID purple];
  NSData *data = [purple orientationEvent:FBSimulatorHIDDeviceOrientationPortrait];

  // msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) = 0x13
  XCTAssertEqual([self uint32AtOffset:0x00 inData:data], (uint32_t)MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0));
  // msgh_remote_port = 0 (patched later by transport)
  XCTAssertEqual([self uint32AtOffset:0x08 inData:data], 0u);
  // msgh_local_port = 0
  XCTAssertEqual([self uint32AtOffset:0x0C inData:data], 0u);
  // msgh_id = 0x7B (123)
  XCTAssertEqual([self uint32AtOffset:0x14 inData:data], 0x7Bu);
}

- (void)testOrientationEventPortrait
{
  FBSimulatorPurpleHID *purple = [FBSimulatorPurpleHID purple];
  NSData *data = [purple orientationEvent:FBSimulatorHIDDeviceOrientationPortrait];

  // GSEvent type at offset 0x18 = 50 | 0x20000 = 0x20032
  XCTAssertEqual([self uint32AtOffset:0x18 inData:data], 0x20032u);
  // record_info_size at offset 0x48 = 4
  XCTAssertEqual([self uint32AtOffset:0x48 inData:data], 4u);
  // orientation at offset 0x4C = 1 (portrait)
  XCTAssertEqual([self uint32AtOffset:0x4C inData:data], 1u);
}

- (void)testOrientationEventPortraitUpsideDown
{
  FBSimulatorPurpleHID *purple = [FBSimulatorPurpleHID purple];
  NSData *data = [purple orientationEvent:FBSimulatorHIDDeviceOrientationPortraitUpsideDown];
  XCTAssertEqual([self uint32AtOffset:0x4C inData:data], 2u);
}

- (void)testOrientationEventLandscapeRight
{
  FBSimulatorPurpleHID *purple = [FBSimulatorPurpleHID purple];
  NSData *data = [purple orientationEvent:FBSimulatorHIDDeviceOrientationLandscapeRight];
  XCTAssertEqual([self uint32AtOffset:0x4C inData:data], 3u);
}

- (void)testOrientationEventLandscapeLeft
{
  FBSimulatorPurpleHID *purple = [FBSimulatorPurpleHID purple];
  NSData *data = [purple orientationEvent:FBSimulatorHIDDeviceOrientationLandscapeLeft];
  XCTAssertEqual([self uint32AtOffset:0x4C inData:data], 4u);
}

- (void)testOrientationEventZeroedBody
{
  FBSimulatorPurpleHID *purple = [FBSimulatorPurpleHID purple];
  NSData *data = [purple orientationEvent:FBSimulatorHIDDeviceOrientationPortrait];

  // GSEvent body from offset 0x1C to 0x47 (44 bytes) should be zeroed
  const uint8_t *bytes = data.bytes;
  for (NSUInteger i = 0x1C; i < 0x48; i++) {
    XCTAssertEqual(bytes[i], 0, @"Byte at offset 0x%lx should be zero", (unsigned long)i);
  }
}

@end
