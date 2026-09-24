/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ProxyService.h"

#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

NSDictionary<NSString *, id> *buildHTTPProxyDict(NSString *host, int port)
{
  return [FBProxyService buildHTTPProxyDict:host port:port];
}

NSDictionary<NSString *, id> *buildSOCKSProxyDict(NSString *host, int port)
{
  return [FBProxyService buildSOCKSProxyDict:host port:port];
}

NSDictionary<NSString *, id> *buildEmptyProxyDict(void)
{
  return [FBProxyService buildEmptyProxyDict];
}

int handleProxyAction(NSString *action, NSArray<NSString *> *arguments)
{
  return (int)[FBProxyService handleProxyAction:action arguments:arguments];
}
