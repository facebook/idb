/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DnsService.h"

#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

NSDictionary<NSString *, id> *buildDnsDict(NSArray<NSString *> *servers)
{
  return [DnsServiceStaticFuncs buildDnsDict:servers];
}

NSDictionary<NSString *, id> *buildEmptyDnsDict(void)
{
  return [DnsServiceStaticFuncs buildEmptyDnsDict];
}

int handleDnsAction(NSString *action, NSArray<NSString *> *arguments)
{
  return (int)[DnsServiceStaticFuncs handleDnsAction:action arguments:arguments];
}
