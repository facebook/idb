/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/** Routes `<service> <action> [args...]` to the matching `handle*Action`. Returns 1 for an unknown service. */
int dispatchService(NSString *service, NSString *action, NSArray<NSString *> *arguments);
