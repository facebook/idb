/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <CoreSimulator/NSPasteboardItemDataProvider-Protocol.h>

@class NSArray, NSMapTable, NSMutableArray, NSMutableDictionary, NSPasteboardItem, NSString;

@interface SimPasteboardItem : NSObject <NSPasteboardItemDataProvider>
{
  BOOL _typesAllResolved;
  NSMutableDictionary *_dataDictionary;
  NSMutableArray *_preferredOrderedTypes;
  NSMapTable *_promisedDataTypes;
  NSPasteboardItem *_nsPasteboardItem;
}

+ (id)itemFromNSPasteboardItem:(id)arg1 options:(id)arg2;
@property (nonatomic, assign) BOOL typesAllResolved;
@property (nonatomic, retain) NSPasteboardItem *nsPasteboardItem;
@property (nonatomic, retain) NSMapTable *promisedDataTypes;
@property (nonatomic, retain) NSMutableArray *preferredOrderedTypes;
@property (nonatomic, retain) NSMutableDictionary *dataDictionary;

- (void)resolveAllTypes;
- (void)pasteboard:(id)arg1 item:(id)arg2 provideDataForType:(id)arg3;
@property (atomic, readonly, copy) NSPasteboardItem *nsPasteboardRepresentation;
@property (atomic, readonly, copy) NSArray *types;
- (id)valueForType:(id)arg1;
- (BOOL)setValue:(id)arg1 forType:(id)arg2;
- (BOOL)setDataProvider:(id)arg1 forTypes:(id)arg2;
- (id)init;
@property (nonatomic, readonly, copy) NSArray *internalRepresentation;

// Remaining properties
@property (atomic, readonly, copy) NSString *debugDescription;
@property (atomic, readonly) unsigned long long hash;
@property (atomic, readonly) Class superclass;

@end
