/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A single typed item on a simulator pasteboard.

 This is the in-process CoreSimulator pasteboard item present up to and including
 Xcode 26.2. Apple removed it in later CoreSimulator (the pasteboard was reimplemented
 in the Swift SimPasteboardPlus framework). It is therefore referenced only behind a
 runtime availability guard, and the declarations below are a subset of the original
 class limited to the members used for plain-text get/set.
 */
@interface SimPasteboardItem : NSObject

- (instancetype)init;

/// The data flavours (UTIs) carried by the item, e.g. @"public.utf8-plain-text".
@property (atomic, copy, readonly) NSArray<NSString *> *types;

/// The value stored for a UTI. For text flavours this is an NSString (or NSData of UTF-8 bytes).
- (nullable id)valueForType:(NSString *)type;

/// Stores a value for a UTI. Returns NO if the value could not be set.
- (BOOL)setValue:(id)value forType:(NSString *)type;

@end

NS_ASSUME_NONNULL_END
