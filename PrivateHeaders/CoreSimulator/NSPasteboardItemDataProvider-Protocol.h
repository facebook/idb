/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreSimulator/NSObject-Protocol.h>

@class NSPasteboard, NSPasteboardItem, NSString;

@protocol NSPasteboardItemDataProvider <NSObject>
- (void)pasteboard:(NSPasteboard *)arg1 item:(NSPasteboardItem *)arg2 provideDataForType:(NSString *)arg3;

@optional
- (void)pasteboardFinishedWithDataProvider:(NSPasteboard *)arg1;
@end
