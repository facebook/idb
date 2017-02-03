/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <AppKit/NSPasteboardItem.h>

@interface NSPasteboardItem (SimPasteboardItem)
- (void)resolveAllTypes;
- (BOOL)setSimPBItemValue:(id)arg1 forType:(id)arg2;
@end
