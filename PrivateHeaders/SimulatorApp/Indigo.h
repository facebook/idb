/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/**
 Structures from class-dumping Simulator.app
 The notions of what these fields are is from tracing the messages sent at runtime.
 */

#import <SimulatorApp/Mach.h>

#pragma pack(push, 4)

/**
 A Quad that is sent via Indigo.
 This is equivalent to NSEdgeInsets, but packed.
 */
typedef struct {
  double field1; // 0x0
  double field2; // 0x8
  double field3; // 0x10
  double field4; // 0x18
} IndigoQuad;

/**
 An Event for Digitizer Events.

 The 'Location' of the touch is in the xRatio and yRatio slots.
 This is 0 > x > 1 and 0 > y > 1, representing the distance from the top left.
 The top left corner is xRatio=0.0, yRatio=0.0
 The bottom right corner is xRatio=1.0, yRatio=1.0
 The center is xRatio=0.5, yRatio=0.5

 The 9th and 10th Slot Represent a touch-up or touch-down.
 The struct is then partially repeated in the 10th slot.
 */
typedef struct {
  unsigned int field1; // 0x20 + 0x10 + 0x0 = 0x30
  unsigned int field2; // 0x20 + 0x10 + 0x4 = 0x34
  unsigned int field3; // 0x20 + 0x10 + 0x8 = 0x38
  double xRatio; // 0x20 + 0x10 + 0xc = 0x3c
  double yRatio; // 0x20 + 0x10 + 0x14 = 0x44
  double field6; // 0x20 + 0x10 + 0x1c = 0x4c
  double field7; // 0x20 + 0x10 + 0x24 = 0x54
  double field8; // 0x20 + 0x10 + 0x2c = 0x5c
  unsigned int field9; // 0x20 + 0x10 + 0x34 = 0x64
  unsigned int field10; // 0x20 + 0x10 + 0x38 = 0x68
  unsigned int field11; // 0x20 + 0x10 + 0x3c = 0x6c
  unsigned int field12; // 0x20 + 0x10 + 0x40 = 0x70
  unsigned int field13; // 0x20 + 0x10 + 0x44 = 0x74
  double field14; // 0x20 + 0x10 + 0x48 = 0x78
  double field15; // 0x20 + 0x10 + 0x50 = 0x80
  double field16; // 0x20 + 0x10 + 0x58 = 0x88
  double field17; // 0x20 + 0x10 + 0x60 = 0x90
  double field18; // 0x20 + 0x10 + 0x68 = 0x98
} IndigoTouch;

/**
 The Indigo Event for a wheel event.
 */
typedef struct {
  unsigned int field1; // 0x20 + 0x10 + 0x0 = 0x30
  double field2; // 0x20 + 0x10 + 0x4 = 0x34
  double field3; // 0x20 + 0x10 + 0xc = 0x3c
  double field4; // 0x20 + 0x10 + 0xc = 0x44
  unsigned int field5; // 0x20 + 0x10 + 0xc = 0x4c
} IndigoWheel;

/**
 The Indigo Event for a button event.
 */
typedef struct {
  unsigned int eventSource; // 0x20 + 0x10 + 0x0 = 0x30
  unsigned int eventType; // 0x20 + 0x10 + 0x4 = 0x34.
  unsigned int eventTarget; // 0x20 + 0x10 + 0x8 = 0x38
  unsigned int keyCode; // 0x20 + 0x10 + 0xc = 0x3c
  unsigned int field5; // 0x20 + 0x10 + 0x10 = 0x40
} IndigoButton;

#define ButtonEventSourceApplePay 0x1f4
#define ButtonEventSourceHomeButton 0x0
#define ButtonEventSourceLock 0x1
#define ButtonEventSourceKeyboard 0x2710
#define ButtonEventSourceSideButton 0xbb8
#define ButtonEventSourceSiri 0x400002

#define ButtonEventTargetHardware 0x33
#define ButtonEventTargetKeyboard 0x64

/**
 These are Derived from NSEventTypeKeyDown & NSEventTypeKeyUp.
 Subtracted by 10/0xa
 */
#define ButtonEventTypeDown 0x1
#define ButtonEventTypeUp 0x2

/**
 An Indigo Event for the accelerometer.
 */
typedef struct {
  unsigned int field1; // 0x20 + 0x10 + 0x0 = 0x30
  unsigned char field2[40]; // 0x20 + 0x10 + 0x4 = 0x34
} IndigoAccelerometer;

/**
 An Indigo Event for force touch.
 */
typedef struct {
  unsigned int field1; // 0x20 + 0x10 + 0x0 = 0x30
  double field2; // 0x20 + 0x10 + 0x4 = 0x34
  unsigned int field3; // 0x20 + 0x10 + 0xc = 0x3c
  double field4; // 0x20 + 0x10 + 0x10 = 0x40
} IndigoForce;

/**
 An Indigo Event for a Game Controller.
 */
typedef struct {
  IndigoQuad dpad; // 0x20 + 0x10 + 0x0 = 0x30
  IndigoQuad face; // 0x20 + 0x10 + 0x20 = 0x50
  IndigoQuad shoulder; // 0x20 + 0x10 + 0x40 = 0x70
  IndigoQuad joystick; // 0x20 + 0x10 + 0x60 = 0x90
} IndigoGameController;

/**
 A Union of all possible event types.
 The eventType to use is identified in the header.
 */
typedef union {
  IndigoTouch touch;
  IndigoWheel wheel;
  IndigoButton button;
  IndigoAccelerometer accelerometer;
  IndigoForce force;
  IndigoGameController gameController;
} IndigoEvent;

/**
 The Payload embedded inside an Message.
 Embedded below the usual mach_msg headers.
 */
typedef struct {
  unsigned int field1; // 0x20 + 0x0 = 0x20:
  unsigned long long timestamp; // 0x20 + 0x04 = 0x24: This is a mach_absolute_time (uint64_t).
  unsigned int field3; // 0x20 + 0x10 = 0x2c
  IndigoEvent event; // 0x20 + 0x10 = 0x30
} IndigoPayload;

/**
 The Indigo Message sent over the wire with mach_msg_send.
 */
typedef struct {
    MachMessageHeader header; // 0x0
    unsigned int innerSize; // 0x18
    unsigned char eventType; // 0x1c
    IndigoPayload payload; // 0x20
} IndigoMessage;

#define IndigoEventTypeButton 1
#define IndigoEventTypeTouch 2
#define IndigoEventTypeUnknown 3

#pragma pack(pop)
