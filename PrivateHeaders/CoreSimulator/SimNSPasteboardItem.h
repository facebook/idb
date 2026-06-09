/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimPasteboardItem.h>
#import <CoreSimulator/SimPasteboardItemDataProvider-Protocol.h>

@class NSString;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimNSPasteboardItem : SimPasteboardItem <SimPasteboardItemDataProvider>
{}

- (id)retrieveValueForSimPasteboardItem:(id)arg1 type:(id)arg2;
- (id)nsPasteboardRepresentation;
- (id)initWithNSPasteboardItem:(id)arg1 resolvedCount:(long long)arg2;

// Remaining properties
@property (atomic, readonly, copy) NSString *debugDescription;
@property (atomic, readonly) NSUInteger hash;
@property (atomic, readonly) Class superclass;

@end
