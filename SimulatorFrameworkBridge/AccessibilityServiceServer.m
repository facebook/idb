/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityServiceServer.h"

#import "AccessibilityService.h"
#import "AccessibilityService+Testing.h"
#import "AccessibilityService_Private.h"
#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

int FBAXBridgeServe(NSString *socketPath, NSArray<NSString *> *arguments)
{
  int idleTimeout = [FBAXBridgeArguments idleTimeoutWithArguments:arguments fallback:FBAXBridgeServer.defaultIdleTimeoutSeconds];
  BOOL exitOnDisconnect = [FBAXBridgeArguments exitOnDisconnectWithArguments:arguments];
  return [FBAXBridgeServer serveWithSocketPath:socketPath
                            idleTimeoutSeconds:idleTimeout
                              exitOnDisconnect:exitOnDisconnect
                                prepareRuntime:^{ FBAXBridgePrepareRuntime(); }
                                 handleRequest:^FBAXBridgeSocketResponse *(NSData *request) {
                                   BOOL shutdown = NO;
                                   NSDictionary<NSString *, id> *response = FBAXBridgeHandleRequestData(request, &shutdown);
                                   return [[FBAXBridgeSocketResponse alloc] initWithData:FBAXBridgeSerializeResponse(response) shutdown:shutdown];
                                 }];
}

int FBAXBridgeServeBacklogForTesting(void)
{
  return FBAXBridgeServer.serveBacklog;
}

int FBAXBridgeIdleTimeoutForTesting(NSArray<NSString *> *arguments, int fallback)
{
  return [FBAXBridgeArguments idleTimeoutWithArguments:arguments fallback:fallback];
}

int FBAXBridgeDefaultIdleTimeoutForTesting(void)
{
  return FBAXBridgeServer.defaultIdleTimeoutSeconds;
}

BOOL FBAXBridgeExitOnDisconnectForTesting(NSArray<NSString *> *arguments)
{
  return [FBAXBridgeArguments exitOnDisconnectWithArguments:arguments];
}
