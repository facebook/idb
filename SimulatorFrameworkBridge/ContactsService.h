/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 * Manages contacts on the simulator via the Contacts framework.
 * Requires TCC authorization for AddressBook access (granted via
 * the binary's entitlements).
 *
 * Usage:
 *   handleContactsAction(@"clear")  // Delete all contacts
 *
 * @param action "clear"
 * @return 0 on success, 1 on failure
 */
int handleContactsAction(NSString *action);
