/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AppKit/NSPasteboardItem.h>

@interface NSPasteboardItem (SimPasteboardItem)
- (void)resolveAllTypes;
- (BOOL)setSimPBItemValue:(id)arg1 forType:(id)arg2;
@end
