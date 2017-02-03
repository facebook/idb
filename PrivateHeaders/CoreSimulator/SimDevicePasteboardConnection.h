/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class NSMachPort;

@interface SimDevicePasteboardConnection : NSObject
{
    NSMachPort *_pasteboardSupportPort;
}

@property (retain, nonatomic) NSMachPort *pasteboardSupportPort;

- (void)refreshPasteboard;
- (id)convertDataWithType:(id)arg1 data:(id)arg2 toType:(id)arg3 error:(id *)arg4;
- (id)readDataWithType:(id)arg1 itemIndex:(unsigned long long)arg2 changeCount:(unsigned long long)arg3 error:(id *)arg4;
- (unsigned long long)writeDataArray:(id)arg1 dataProviderPort:(id)arg2 error:(id *)arg3;
- (id)readDataArrayWithTypes:(id)arg1 changeCount:(unsigned long long *)arg2 error:(id *)arg3;
- (BOOL)subscribeWithCallbackPort:(id)arg1 changeCount:(unsigned long long *)arg2 itemsDatatypes:(id *)arg3 error:(id *)arg4;
- (id)createPasteboardSupportPortWithDevice:(id)arg1;
- (id)initWithDevice:(id)arg1;

@end
