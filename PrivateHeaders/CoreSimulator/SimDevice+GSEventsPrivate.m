/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "SimDevice+GSEventsPrivate.h"

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>

NSMachPort *gsEventsPort(SimDevice* self, SEL _cmd);
dispatch_queue_t gsEventsQueue(SimDevice *self, SEL _cmd);

NSMachPort *gsEventsPort(SimDevice* self, SEL _cmd)
{
  NSMachPort *gsEventsPort = objc_getAssociatedObject(self, _cmd);
  if (gsEventsPort.isValid) {
    return gsEventsPort;
  }

  NSError *error;
  mach_port_name_t purpleWorkspacePort = [self lookup:@"PurpleWorkspacePort" error:&error];
  gsEventsPort = (NSMachPort*)[NSMachPort portWithMachPort:purpleWorkspacePort options:NSMachPortDeallocateSendRight];
  if (!gsEventsPort) {
    mach_port_deallocate(mach_task_self(), purpleWorkspacePort);
    return nil;
  }

  objc_setAssociatedObject(self, _cmd, gsEventsPort, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  return gsEventsPort;
}

dispatch_queue_t gsEventsQueue(SimDevice *self, SEL _cmd)
{
  dispatch_queue_t gsEventsQueue = objc_getAssociatedObject(self, _cmd);
  if (gsEventsQueue) {
    return gsEventsQueue;
  }

  @synchronized (self) {
    gsEventsQueue = objc_getAssociatedObject(self, _cmd);
    if (gsEventsQueue) {
      return gsEventsQueue;
    }

    gsEventsQueue =  dispatch_queue_create("com.apple.iphonesimulator.SimDeviceSimulatorBridge.gsEventsQueue", DISPATCH_QUEUE_SERIAL);
    if (!gsEventsQueue) {
      return nil;
    }
    
    objc_setAssociatedObject(self, _cmd, gsEventsQueue, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return gsEventsQueue;
  }
}

FBFuture<NSNull *> *sendPurpleMessage(SimDevice *self, PurpleMessage *purpleMessage)
{
  return [FBFuture onQueue:gsEventsQueue(self, @selector(gsEventsQueue)) resolve:^FBFuture *{
    if (!MACH_PORT_VALID(purpleMessage->header.msgh_remote_port)) {
      NSMachPort *port = gsEventsPort(self, @selector(gsEventsPort));
      purpleMessage->header.msgh_remote_port = [port machPort];
    }
    mach_msg_return_t result = mach_msg_send((mach_msg_header_t*)&purpleMessage->header);
    free(purpleMessage);
    if (result != MACH_MSG_SUCCESS) {
      return [[FBControlCoreError
        describeFormat:@"Could not send purple message, mach_msg_send() failed with %0x08x", result]
        failFuture];
    }
    return FBFuture.empty;
  }];
}
