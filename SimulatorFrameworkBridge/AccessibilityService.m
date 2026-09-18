/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityService.h"
#import "AccessibilityService+Testing.h"

#import "AccessibilityServiceServer.h"
#import "AccessibilityService_Private.h"

#if __has_include(<SimulatorFrameworkBridgeRuntime/AccessibilityClientProvider.h>)
 #import <SimulatorFrameworkBridgeRuntime/AccessibilityClientProvider.h>
#else
 #import "Runtime/AccessibilityClientProvider.h"
#endif
#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

void FBAXBridgePrepareRuntime(void)
{
  [FBAXClientProvider prepare];
}

void FBAXBridgeSetRuntimeForTesting(id<FBAXRuntime> runtime)
{
  [FBAXClientProvider setRuntimeForTesting:runtime];
}

void FBAXBridgeSetRuntimeFactoryForTesting(FBAXRuntimeFactory factory)
{
  [FBAXClientProvider setRuntimeFactoryForTesting:factory];
}

NSDictionary<NSString *, id> *FBAXBridgeHandleRequest(NSDictionary<NSString *, id> *request)
{
  return [AccessibilityServiceStaticFuncs handleRequest:request];
}

NSDictionary<NSString *, id> *FBAXBridgeHandleRequestData(NSData *data, BOOL *shutdownRequested)
{
  return [AccessibilityServiceStaticFuncs handleRequestData:data shutdownRequested:shutdownRequested];
}

NSData *FBAXBridgeSerializeResponse(NSDictionary<NSString *, id> *response)
{
  return [AccessibilityServiceStaticFuncs serializeResponse:response];
}

NSDictionary<NSString *, NSString *> *FBAXBridgeModalDescriptor(NSDictionary<NSString *, id> *tree)
{
  return [AccessibilityServiceStaticFuncs modalDescriptor:tree];
}

NSDictionary<NSString *, NSString *> *FBAXBridgeWireConstantsForTesting(void)
{
  return [AccessibilityServiceStaticFuncs wireConstantsForTesting];
}

NSDictionary<NSString *, id> *FBAXBridgeRequestFromArguments(NSString *action, NSArray<NSString *> *arguments)
{
  return [FBAXBridgeArguments requestWithAction:action arguments:arguments];
}

int handleAccessibilityAction(NSString *action, NSArray<NSString *> *arguments)
{
  return [AccessibilityServiceStaticFuncs handleAction:action
                                             arguments:arguments
                                                 serve:^int32_t (NSString *socketPath, NSArray<NSString *> *serveArguments) {
                                                   return FBAXBridgeServe(socketPath, serveArguments);
                                                 }
                                         writeResponse:^(NSData *data) {
                                           fwrite(data.bytes, 1, data.length, stdout);
                                           fputc('\n', stdout);
                                         }];
}
