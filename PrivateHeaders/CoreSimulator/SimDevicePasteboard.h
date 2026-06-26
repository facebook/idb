/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SimPasteboardItem;

/**
 The simulator's device pasteboard, vended by -[SimDevice pasteboard].

 Present in CoreSimulator up to Xcode 26.2, this provides one-shot get/set against the
 device pasteboard with no host syncing. Apple removed it in later CoreSimulator (the
 pasteboard moved to the Swift SimPasteboardPlus framework, whose only surface is
 snapshot/autosync based). Both this class and -[SimDevice pasteboard] are therefore
 referenced only behind a runtime availability guard (-[SimDevice respondsToSelector:@selector(pasteboard)]);
 the class symbols are weak-linked, so they resolve at link time and are absent (nil) at runtime
 on newer CoreSimulator.

 Only the subset of methods used for plain-text get/set is declared. Both methods import into Swift
 as `throws` via the standard NSError convention (the change-count return is preserved alongside).
 */
@interface SimDevicePasteboard : NSObject

/// Replaces the pasteboard contents with the given items. Returns the new change count; throws on failure.
- (unsigned long long)setPasteboardWithItems:(NSArray<SimPasteboardItem *> *)items error:(NSError **)error
    NS_SWIFT_NAME(setItems(_:)) __attribute__((swift_error(nonnull_error)));

/// Returns the items currently on the pasteboard that carry one of the requested UTIs.
/// `nullable` (rather than relying on the audit) so the trailing `error:` keeps the Swift
/// throwing-bridge: a nil return signals the thrown error.
- (nullable NSArray<SimPasteboardItem *> *)itemsFromPasteboardWithTypes:(NSArray<NSString *> *)types error:(NSError **)error NS_SWIFT_NAME(items(forTypes:));

@end

NS_ASSUME_NONNULL_END
