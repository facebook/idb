/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreFoundation/CoreFoundation.h>

// SCDynamicStore is exported by the simulator runtime but unavailable in the iOS SDK.
// Create/Copy results are owned; all other parameters are borrowed.
typedef CFTypeRef (*ProbeStoreCreate)(CFAllocatorRef, CFStringRef, void *, void *);
typedef CFPropertyListRef (*ProbeStoreCopy)(CFTypeRef, CFStringRef);
typedef Boolean (*ProbeStoreSet)(CFTypeRef, CFStringRef, CFPropertyListRef);
typedef Boolean (*ProbeStoreRemove)(CFTypeRef, CFStringRef);
typedef Boolean (*ProbeStoreNotify)(CFTypeRef, CFStringRef);
typedef int (*ProbeSCError)(void);
