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
#import "NotificationSettingsService.h"
#import "PhotoLibraryService.h"
#import "ProxyService.h"
#if !TARGET_OS_TV
 #import "ContactsService.h"
 #import "DeliveredNotificationsService.h"
 #import "HealthSettingsService.h"
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

#if TARGET_OS_TV
static int unsupportedOnThisPlatform(NSString *service)
{
  NSLog(@"The %@ service is not available in a tvOS guest", service);
  return 1;
}

#endif

@implementation FBBridgeCommand

+ (int32_t)runWithArguments:(NSArray<NSString *> *)arguments services:(id<FBBridgeServiceHandling>)services
{
  if (arguments.count < 3) {
    NSLog(@"Usage: %@ <service> <action> [args...]", arguments.count > 0 ? arguments[0] : @"SimulatorFrameworkBridge");
    NSLog(@"Services: contacts, dns, photos, notifications, health, proxy, accessibility, repl");
    NSLog(@"Actions: clear, approve, revoke, check, set, list");
    return 1;
  }
  return [self dispatchWithService:arguments[1]
                            action:arguments[2]
                         arguments:[arguments subarrayWithRange:NSMakeRange(3, arguments.count - 3)]
                          services:services];
}

+ (int32_t)dispatchWithService:(NSString *)service action:(NSString *)action
                     arguments:(NSArray<NSString *> *)arguments services:(id<FBBridgeServiceHandling>)services
{
  if ([service isEqualToString:@"contacts"]) {
  #if TARGET_OS_TV
    return unsupportedOnThisPlatform(service);
  #else
    return [services contacts:action];
  #endif
  } else if ([service isEqualToString:@"dns"]) {
    return [services dns:action arguments:arguments];
  } else if ([service isEqualToString:@"photos"]) {
    return [services photos:action];
  } else if ([service isEqualToString:@"notifications"]) {
    NSString *bundleID = arguments.count > 0 ? arguments[0] : nil;
    return [services notifications:action bundleID:bundleID];
  } else if ([service isEqualToString:@"health"]) {
  #if TARGET_OS_TV
    return unsupportedOnThisPlatform(service);
  #else
    NSString *bundleID = arguments.count > 0 ? arguments[0] : nil;
    NSArray<NSString *> *typeIDs = arguments.count > 1
    ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]
    : @[];
    return [services health:action bundleID:bundleID typeIDs:typeIDs];
  #endif
  } else if ([service isEqualToString:@"proxy"]) {
    return [services proxy:action arguments:arguments];
  } else if ([service isEqualToString:@"accessibility"]) {
    return [services accessibility:action arguments:arguments];
  } else if ([service isEqualToString:@"repl"]) {
    if ([action isEqualToString:@"start"]) {
      // libRepl exports both the socket server and the IDB API injected code calls, so serving through
      // its copy keeps both on one connection and lets `import IDB` resolve. Arguments: socket path, then
      // libRepl path. The simulator context generates no interfaces; the companion reports the pre-built one.
      NSString *socketPath = arguments.count > 0 ? arguments[0] : nil;
      NSString *libReplPath = arguments.count > 1 ? arguments[1] : nil;
      if (libReplPath.length == 0) {
        NSLog(@"repl start requires the libRepl path as its second argument");
        return 1;
      }
      return [services repl:socketPath libraryPath:libReplPath];
    }
    NSLog(@"Unknown repl action: %@", action);
    return 1;
  } else {
    NSLog(@"Unknown service: %@", service);
    NSLog(@"Available services: contacts, dns, photos, notifications, health, proxy, accessibility, repl");
    return 1;
  }
}

@end
