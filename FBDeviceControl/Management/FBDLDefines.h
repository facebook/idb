/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#pragma mark - AMDevice API

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"

/**
 Derived from DLDeviceListenerSet* functions.
 Has a size of 0x38/56.
 */
typedef struct {
  void *attachedCallback; // 0x0
  void *detachedCallback; // 0x8
  void *stoppedCallback; // 0x10
  void *context; // 0x18
  void *unknown0; // 0x20
  CFArrayRef callbackArray; // 0x28
  void *unknown1; // 0x30
} DLDeviceListener;

/**
 Derived from DLDeviceGet* functions.
 Has a size of 0x20/32
 */
typedef struct {
  CFDictionaryRef info; // 0x0
  CFArrayRef endpoints; // 0x8
  CFTypeRef amDevice; // 0x10
  void *unknown0; // 0x18
} DLDevice;

/**
 Derived from DLCreateDeviceLinkConnection.
 */
typedef struct {
  void *incomingConnectionCallback; // 0x0
  void *connectionMadeCallback; // 0x8
  void *connectionFailedCallback; // 0x10
  void *acceptFailedCallback; // 0x18
  void *disconnectCallback; // 0x20
  void *connectionLostCallback; // 0x28
  void *processMessageCallback; // 0x30
  void *pingCallback; // 0x38
  void *requestFileCallback; // 0x40
  void *sendFileCallback; // 0x48
  void *context; // 0x50. This value is not set so is assumed to be a context pointer
  void *deviceReadyCallback; // 0x58
  intptr_t padding[14]; // 0x60 - 0xd0
} DLDeviceConnectionCallbacks;

/**
 Derived from DLDeviceConnection functions.
 Has a combined size of 208/0xd0.
 */
typedef struct {
  void *padding0[5]; // 0x0 - 0x20
  DLDeviceConnectionCallbacks *callbacks; // 0x28
  void *padding1[3]; // 0x30 - 0x40
  CFStringRef name; // 0x48
  CFMessagePortRef receivePort; // 0x50
  void *padding3; // 0x58
  CFMessagePortRef sendPort; // 0x60
  void *unknown12; // 0x68
  void *unknown13; // 0x70
  void *unknown14; // 0x78
  void *condition; // 0x80
  void *unknown17; // 0x88
  void *unknown18; // 0x90
  void *unknown19; // 0x98
  CFNumberRef number0; // 0xa0
  CFNumberRef number1; // 0xa8
  void *unknown20; // 0xb0
  void *unknown21; // 0xb8
  void *unknown22; // 0xc0
  void *unknown23; // 0xc8
} DLDeviceConnection;

#pragma mark DeviceLink APIs

typedef struct {
  // Management
  void * (*CopyConnectedDeviceArray)(DLDeviceListener *deviceListener);
  DLDeviceListener * (*ListenerCreateWithCallbacks)(void *deviceAttachedCallback, void *deviceDetachedCallback, void *deviceListenerStoppedCallback, void *context);

  // Getters
  NSString * (*CreateDescription)(DLDevice *device, DLDeviceListener *deviceListener);
  NSString * (*GetUDID)(DLDevice *device);
  void * (*GetWithUDID)(DLDeviceListener *deviceListener, CFStringRef udid);

  // Setters
  void *(*ListenerSetContext)(DLDeviceListener *listener, void *context);

  // Connections
  int (*CreateDeviceLinkConnectionForComputer)(int arg0, DLDeviceConnectionCallbacks *callback, int arg2, DLDeviceConnection **connectionOut, CFStringRef *errorDescriptionOut);
  int (*ConnectToServiceOnDevice)(DLDeviceConnection *connection, DLDevice *device, CFStringRef serviceName, CFStringRef *errorDescriptionOut);
  int (*ProcessMessage)(DLDeviceConnection *connection, CFDictionaryRef requestDictionary, CFStringRef *errorDescriptionOut);
  int (*Disconnect)(DLDeviceConnection *connection, CFStringRef message, CFStringRef *errorDescriptionOut);

  // Memory Management
  void *(*Retain)(DLDevice *device);
  void  (*Release)(DLDevice *device);
} DLDeviceCalls;

#pragma clang diagnostic pop
