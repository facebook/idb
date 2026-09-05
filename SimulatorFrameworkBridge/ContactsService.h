/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 * Clears the simulator's contacts via the Contacts framework. Needs TCC AddressBook authorization,
 * granted by the binary's entitlements. Returns 0 on success.
 */
int handleContactsAction(NSString *action);
