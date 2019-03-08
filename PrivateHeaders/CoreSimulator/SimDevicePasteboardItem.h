/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/SimPasteboardItem.h>

#import <CoreSimulator/SimPasteboardItemDataProvider-Protocol.h>

@class NSString, SimDevicePasteboardConnection;

@interface SimDevicePasteboardItem : SimPasteboardItem <SimPasteboardItemDataProvider>
{
    SimDevicePasteboardConnection *_connection;
    unsigned long long _pasteboardChangeCount;
    unsigned long long _pasteboardItemIndex;
}

@property (nonatomic, assign) unsigned long long pasteboardItemIndex;
@property (nonatomic, assign) unsigned long long pasteboardChangeCount;
@property (retain, nonatomic) SimDevicePasteboardConnection *connection;

- (id)transformValueWithType:(id)arg1 value:(id)arg2;
- (void)pasteboard:(id)arg1 item:(id)arg2 provideDataForType:(id)arg3;
- (id)retrieveValueForSimPasteboardItem:(id)arg1 type:(id)arg2;
- (id)nsPasteboardRepresentation;
- (id)initWithConnection:(id)arg1 changeCount:(unsigned long long)arg2 itemIndex:(unsigned long long)arg3 itemData:(id)arg4;

// Remaining properties
@property (atomic, copy, readonly) NSString *debugDescription;
@property (atomic, readonly) unsigned long long hash;
@property (atomic, readonly) Class superclass;

@end
