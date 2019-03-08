/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimPasteboardItem.h>

#import <CoreSimulator/SimPasteboardItemDataProvider-Protocol.h>

@class NSString;

@interface SimNSPasteboardItem : SimPasteboardItem <SimPasteboardItemDataProvider>
{
}

- (id)retrieveValueForSimPasteboardItem:(id)arg1 type:(id)arg2;
- (id)nsPasteboardRepresentation;
- (id)initWithNSPasteboardItem:(id)arg1 resolvedCount:(long long)arg2;

// Remaining properties
@property (atomic, copy, readonly) NSString *debugDescription;
@property (atomic, readonly) unsigned long long hash;
@property (atomic, readonly) Class superclass;

@end
