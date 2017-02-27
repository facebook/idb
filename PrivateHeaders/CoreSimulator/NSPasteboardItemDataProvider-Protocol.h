/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <CoreSimulator/NSObject-Protocol.h>

@class NSPasteboard, NSPasteboardItem, NSString;

@protocol NSPasteboardItemDataProvider <NSObject>
- (void)pasteboard:(NSPasteboard *)arg1 item:(NSPasteboardItem *)arg2 provideDataForType:(NSString *)arg3;

@optional
- (void)pasteboardFinishedWithDataProvider:(NSPasteboard *)arg1;
@end
