/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "KeyedArchiveReference.h"

#import <dlfcn.h>

#import "Private/KeyedArchivePrivate.h"

@implementation FBKeyedArchiveReference
+ (NSNumber *)indexOfObject:(id)object
{
  static FBKeyedArchiverUIDGetTypeIDFn getTypeID;
  static FBKeyedArchiverUIDGetValueFn getValue;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    getTypeID = (FBKeyedArchiverUIDGetTypeIDFn)dlsym(RTLD_DEFAULT, "_CFKeyedArchiverUIDGetTypeID");
    getValue = (FBKeyedArchiverUIDGetValueFn)dlsym(RTLD_DEFAULT, "_CFKeyedArchiverUIDGetValue");
    if (!getTypeID || !getValue) {
      NSLog(@"[DeliveredNotifications] CoreFoundation does not export the keyed-archive UID accessors; no archive can be read");
    }
  });
  if (!object || !getTypeID || !getValue) {
    return nil;
  }
  if (CFGetTypeID((__bridge CFTypeRef)object) != getTypeID()) {
    return nil;
  }
  return @(getValue((__bridge const void *)object));
}

@end
