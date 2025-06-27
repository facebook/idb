/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimDevice.h>
#import <SimulatorApp/Purple.h>
#import <FBControlCore/FBFuture.h>

#import <Foundation/Foundation.h>

@interface SimDevice (GSEventsPrivate)
- (NSMachPort*)gsEventsPort;
- (dispatch_queue_t)gsEventsQueue;
- (void)sendPurpleMessage:(PurpleMessage*)purpleMessage;
@end

FBFuture<NSNull *> *sendPurpleMessage(SimDevice *self, PurpleMessage *purpleMessage);
