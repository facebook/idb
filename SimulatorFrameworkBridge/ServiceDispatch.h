/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 * Dispatches to the appropriate service handler based on service name and action.
 *
 * Routes to one of:
 *   - "contacts"      → handleContactsAction(action)
 *   - "photos"        → handlePhotoLibraryAction(action)
 *   - "notifications" → handleNotificationSettingsAction(action, arguments[0])
 *   - "proxy"         → handleProxyAction(action, arguments)
 *
 * @param service The service name
 * @param action The action to perform (service-specific)
 * @param arguments Additional arguments beyond service and action
 * @return 0 on success, 1 on failure (including unknown service)
 */
int dispatchService(NSString *service, NSString *action, NSArray<NSString *> *arguments);
