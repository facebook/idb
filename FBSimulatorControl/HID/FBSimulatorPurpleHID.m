/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorPurpleHID.h"

#import <mach/mach.h>

#import <SimulatorApp/GSEvent.h>

@implementation FBSimulatorPurpleHID

+ (instancetype)purple
{
  return [[self alloc] init];
}

- (NSData *)orientationEvent:(FBSimulatorHIDDeviceOrientation)orientation
{
  // Construct a 112-byte buffer (aligned to 8 bytes, >= 108 = 0x6C mach message size).
  // See GSEvent.h for the complete wire format documentation.
  uint8_t buf[112];
  memset(buf, 0, sizeof(buf));

  mach_msg_header_t *header = (mach_msg_header_t *)buf;
  header->msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
  header->msgh_size = 108; // align4(4 + 0x6B) — matches Simulator.app's sendPurpleEvent:
  header->msgh_remote_port = MACH_PORT_NULL; // Patched by FBSimulatorHID.sendPurpleEvent:
  header->msgh_local_port = MACH_PORT_NULL;
  header->msgh_id = GSEventMachMessageID;

  // GSEvent type at offset 0x18
  uint32_t *gsEventType = (uint32_t *)(buf + 0x18);
  *gsEventType = GSEventTypeDeviceOrientationChanged | GSEventHostFlag;

  // record_info_size at offset 0x48
  uint32_t *dataSize = (uint32_t *)(buf + 0x48);
  *dataSize = 4;

  // orientation value at offset 0x4C
  uint32_t *orientationField = (uint32_t *)(buf + 0x4C);
  *orientationField = (uint32_t)orientation;

  return [NSData dataWithBytes:buf length:sizeof(buf)];
}

- (NSData *)lockDeviceEvent
{
  // Same 112-byte buffer as orientation, but with GSEventTypeLockDevice and no payload.
  uint8_t buf[112];
  memset(buf, 0, sizeof(buf));

  mach_msg_header_t *header = (mach_msg_header_t *)buf;
  header->msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
  header->msgh_size = 108;
  header->msgh_remote_port = MACH_PORT_NULL;
  header->msgh_local_port = MACH_PORT_NULL;
  header->msgh_id = GSEventMachMessageID;

  uint32_t *gsEventType = (uint32_t *)(buf + 0x18);
  *gsEventType = GSEventTypeLockDevice | GSEventHostFlag;

  // record_info_size = 0, no payload
  return [NSData dataWithBytes:buf length:sizeof(buf)];
}

@end
