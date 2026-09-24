/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DeliveredNotificationsService.h"
#import "DeliveredNotificationsService+Testing.h"

#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

static NSString *gDirectoryForTesting = nil;
static NSTimeInterval gTimeoutForTesting = 0;

int handleDeliveredNotificationsAction(NSString *action, NSString *bundleID)
{
  return [FBDeliveredNotificationsService handleAction:action bundleID:bundleID directory:gDirectoryForTesting timeout:gTimeoutForTesting];
}

int handleDeliveredNotificationsActionWithCenter(NSString *action, NSString *bundleID, id<FBDeliveredNotificationsCenter> center)
{
  return [FBDeliveredNotificationsService handleActionWithCenter:action bundleID:bundleID center:center directory:gDirectoryForTesting timeout:gTimeoutForTesting];
}

int clearDeliveredNotificationsWithRemover(NSString *bundleID, id<FBDeliveredNotificationsRemover> remover)
{
  return [FBDeliveredNotificationsService clearWithBundleID:bundleID remover:remover directory:gDirectoryForTesting timeout:gTimeoutForTesting];
}

void FBDeliveredNotificationsSetDirectoryForTesting(NSString *directory)
{
  gDirectoryForTesting = [directory copy];
}

void FBDeliveredNotificationsSetTimeoutForTesting(NSTimeInterval timeout)
{
  gTimeoutForTesting = timeout;
}
