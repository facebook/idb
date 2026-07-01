/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ServiceDispatch.h"

#import <dlfcn.h>

#import "ContactsService.h"
#import "DnsService.h"
#import "HealthSettingsService.h"
#import "NotificationSettingsService.h"
#import "PhotoLibraryService.h"
#import "ProxyService.h"

int dispatchService(NSString *service, NSString *action, NSArray<NSString *> *arguments)
{
  if ([service isEqualToString:@"contacts"]) {
    return handleContactsAction(action);
  } else if ([service isEqualToString:@"dns"]) {
    return handleDnsAction(action, arguments);
  } else if ([service isEqualToString:@"photos"]) {
    return handlePhotoLibraryAction(action);
  } else if ([service isEqualToString:@"notifications"]) {
    NSString *bundleID = arguments.count > 0 ? arguments[0] : nil;
    return handleNotificationSettingsAction(action, bundleID);
  } else if ([service isEqualToString:@"health"]) {
    NSString *bundleID = arguments.count > 0 ? arguments[0] : nil;
    NSArray<NSString *> *typeIDs = arguments.count > 1
    ? [arguments subarrayWithRange:NSMakeRange(1, arguments.count - 1)]
    : @[];
    return handleHealthSettingsAction(action, bundleID, typeIDs);
  } else if ([service isEqualToString:@"proxy"]) {
    return handleProxyAction(action, arguments);
  } else if ([service isEqualToString:@"repl"]) {
    if ([action isEqualToString:@"start"]) {
      // Serve the REPL control socket via libRepl, which the bridge loads on
      // demand (only when a repl session starts). libRepl exports the socket
      // server -- and the IDB API that injected code calls -- so serving through
      // its copy keeps both on the same control-socket connection, and injected
      // `import IDB` symbols resolve against it. Arguments: the socket path, then
      // libRepl's path. The simulator context has no in-process probe, so it
      // generates no interfaces (the companion reports the pre-built one).
      NSString *socketPath = arguments.count > 0 ? arguments[0] : nil;
      NSString *libReplPath = arguments.count > 1 ? arguments[1] : nil;
      if (libReplPath.length == 0) {
        NSLog(@"repl start requires the libRepl path as its second argument");
        return 1;
      }
      void *handle = dlopen(libReplPath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
      if (!handle) {
        NSLog(@"Failed to load libRepl at %@: %s", libReplPath, dlerror());
        return 1;
      }
      int (*serve)(NSString *, NSArray<NSString *> *) = dlsym(handle, "FBReplServeSocket");
      if (!serve) {
        NSLog(@"libRepl is missing FBReplServeSocket: %s", dlerror());
        return 1;
      }
      return serve(socketPath, @[]);
    }
    NSLog(@"Unknown repl action: %@", action);
    return 1;
  } else {
    NSLog(@"Unknown service: %@", service);
    NSLog(@"Available services: contacts, dns, photos, notifications, health, proxy");
    return 1;
  }
}
