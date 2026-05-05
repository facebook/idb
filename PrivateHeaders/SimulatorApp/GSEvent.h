/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/**
 GSEvent mach message format for PurpleWorkspacePort.

 This is a separate HID transport from Indigo. Indigo messages go through
 SimDeviceLegacyHIDClient → IndigoHIDRegistrationPort → SimHIDVirtualServiceManager.
 GSEvent messages go through mach_msg_send → PurpleWorkspacePort →
 GraphicsServices._PurpleEventCallback → backboardd.

 Simulator.app implements this in [SimDevice(GSEvents) gsEventsSendOrientation:]
 → [SimDevice(GSEventsPrivate) sendPurpleEvent:], compiled into the Simulator.app
 binary from SimDevice+GSEvents.m (Indigo project, Indigo-1062.1).

 Wire format (reverse-engineered from Simulator.app ARM64 disassembly, Xcode 26.2):

 Offset  Size  Field
 ------  ----  -----
 0x00    4     msgh_bits            = 0x13 (MACH_MSG_TYPE_COPY_SEND)
 0x04    4     msgh_size            = align4(record_info_size + 0x6B)
 0x08    4     msgh_remote_port     = PurpleWorkspacePort (from SimDevice lookup:)
 0x0C    4     msgh_local_port      = 0 (MACH_PORT_NULL)
 0x10    4     msgh_voucher_port    = 0
 0x14    4     msgh_id              = 0x7B (123)
 ------ mach_msg_header_t ends (24 bytes) ------
 0x18    4     GSEvent type         = event type | GSEventHostFlag
 0x1C    4     GSEvent subtype      (zeroed for orientation)
 0x20    8     location.x           (float pair, zeroed for orientation)
 0x28    8     location.y           (float pair, zeroed for orientation)
 0x30    8     windowLocation.x     (float pair, zeroed for orientation)
 0x38    8     windowLocation.y     (float pair, zeroed for orientation)
 0x40    8     timestamp            (uint64, zeroed for orientation)
 0x48    4     record_info_size     = size of appended event-specific data
 0x4C    N     record_info_data     = event-specific payload
 ------ total = align4(record_info_size + 0x6B) ------

 Guest-side receiver (GraphicsServices.framework):
   CreateWithMachMessage validates msgh_size >= 0x4C.
   GSEventGetType reads from CF offset +0x10 (wire 0x18).
   GSEventDeviceOrientation reads uint32 from CF offset +0x5C (wire 0x4C).
   Location fields undergo float→double conversion during reception.

 Orientation events (GSEventTypeDeviceOrientationChanged = 50):
   GSEvent type = 50 | 0x20000 (GSEventHostFlag)
   record_info_size = 4
   record_info_data = UIDeviceOrientation value (uint32: 1=portrait, 2=portraitUpsideDown,
                      3=landscapeRight, 4=landscapeLeft)
   Total message size = align4(4 + 0x6B) = 108 bytes (0x6C)

 The 0x20000 host flag is set by Simulator.app's sendPurpleEvent: when resolving
 the PurpleWorkspacePort from a sentinel value (0xFFFFFFFE) in the event template.
 The flag must be present for the guest to process the event.
 */

#define GSEventTypeDeviceOrientationChanged 50
#define GSEventTypeLockDevice 1014
#define GSEventHostFlag 0x20000
#define GSEventMachMessageID 0x7B
