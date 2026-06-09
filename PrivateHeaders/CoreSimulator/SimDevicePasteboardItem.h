/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimPasteboardItem.h>
#import <CoreSimulator/SimPasteboardItemDataProvider-Protocol.h>

@class NSString, SimDevicePasteboardConnection;

/**
 Removed from CoreSimulator as of Xcode 27 (CoreSimulator 1155.4): part of the simulator pasteboard / clipboard sync subsystem. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimDevicePasteboardItem : SimPasteboardItem <SimPasteboardItemDataProvider>
{
  SimDevicePasteboardConnection *_connection;
  unsigned long long _pasteboardChangeCount;
  unsigned long long _pasteboardItemIndex;
}

@property (nonatomic, assign) unsigned long long pasteboardItemIndex;
@property (nonatomic, assign) unsigned long long pasteboardChangeCount;
@property (nonatomic, retain) SimDevicePasteboardConnection *connection;

- (id)transformValueWithType:(id)arg1 value:(id)arg2;
- (void)pasteboard:(id)arg1 item:(id)arg2 provideDataForType:(id)arg3;
- (id)retrieveValueForSimPasteboardItem:(id)arg1 type:(id)arg2;
- (id)nsPasteboardRepresentation;
- (id)initWithConnection:(id)arg1 changeCount:(unsigned long long)arg2 itemIndex:(unsigned long long)arg3 itemData:(id)arg4;

// Remaining properties
@property (atomic, readonly, copy) NSString *debugDescription;
@property (atomic, readonly) NSUInteger hash;
@property (atomic, readonly) Class superclass;

@end
