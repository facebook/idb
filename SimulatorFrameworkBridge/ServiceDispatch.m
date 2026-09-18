/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ServiceDispatch.h"

#import <dlfcn.h>

#import "AccessibilityService.h"
#import "DnsService.h"
#import "DynamicStoreService.h"
#import "NotificationSettingsService.h"
#import "PhotoLibraryService.h"
#import "ProxyService.h"
#if !TARGET_OS_TV
 #import "ContactsService.h"
 #import "DeliveredNotificationsService.h"
 #import "HealthSettingsService.h"
#endif
#if __has_include(<SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>)
 #import <SimulatorFrameworkBridgeSupport/SimulatorFrameworkBridgeSupport-Swift.h>
#else
 #import "SimulatorFrameworkBridgeSupport-Swift.h"
#endif

@interface FBBridgeServices : NSObject <FBBridgeServiceHandling>
@end

@implementation FBBridgeServices

#if !TARGET_OS_TV
- (int32_t)contacts:(NSString *)action
{
  return handleContactsAction(action);
}

- (int32_t)health:(NSString *)action bundleID:(NSString *)bundleID typeIDs:(NSArray<NSString *> *)typeIDs
{
  return handleHealthSettingsAction(action, bundleID, typeIDs);
}

#endif

- (int32_t)dns:(NSString *)action arguments:(NSArray<NSString *> *)arguments
{
  return handleDnsAction(action, arguments);
}

- (int32_t)dynamicStore:(NSString *)action arguments:(NSArray<NSString *> *)arguments
{
  return handleDynamicStoreAction(action, arguments);
}

- (int32_t)photos:(NSString *)action
{
  return handlePhotoLibraryAction(action);
}

- (int32_t)notifications:(NSString *)action bundleID:(NSString *)bundleID
{
  // `list` on this service means "list the apps' settings", so the delivered notifications of
  // one app are read with their own verb.
  if ([action isEqualToString:@"delivered"]) {
  #if TARGET_OS_TV
    NSLog(@"The notifications delivered action is not available in a tvOS guest");
    return 1;
  #else
    return handleDeliveredNotificationsAction(action, bundleID);
  #endif
  }
  return handleNotificationSettingsAction(action, bundleID);
}

- (int32_t)proxy:(NSString *)action arguments:(NSArray<NSString *> *)arguments
{
  return handleProxyAction(action, arguments);
}

- (int32_t)accessibility:(NSString *)action arguments:(NSArray<NSString *> *)arguments
{
  return handleAccessibilityAction(action, arguments);
}

- (int32_t)repl:(NSString *)socketPath libraryPath:(NSString *)libraryPath
{
  // The socket server and injected IDB API must use libRepl's one control connection.
  void *handle = dlopen(libraryPath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
  if (!handle) {
    NSLog(@"Failed to load libRepl at %@: %s", libraryPath, dlerror());
    return 1;
  }
  int (*serve)(NSString *, NSArray<NSString *> *, BOOL) = dlsym(handle, "FBReplServeSocket");
  if (!serve) {
    NSLog(@"libRepl is missing FBReplServeSocket: %s", dlerror());
    return 1;
  }
  // The bridge exits when the session ends, so serve a single connection.
  return serve(socketPath, @[], NO);
}

@end

int dispatchService(NSString *service, NSString *action, NSArray<NSString *> *arguments)
{
  return [FBBridgeCommand dispatchWithService:service action:action arguments:arguments services:[FBBridgeServices new]];
}

int runBridgeCommand(NSArray<NSString *> *arguments)
{
  return [FBBridgeCommand runWithArguments:arguments services:[FBBridgeServices new]];
}
