/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SimPasteboardInterface;

/**
 Delegate for a SimPasteboardInterface connection.

 Present in CoreSimulator from Xcode 26.6 onwards, in the Swift SimPasteboardPlus framework.
 All methods are optional; they report the progress of snapshot application as the managed
 NSPasteboard is synced to/from the connected device. The signatures are reverse-engineered
 from the ObjC type encodings emitted by the @objc Swift protocol.
 */
@protocol SimPasteboardDelegate <NSObject>

@optional

- (void)simPasteboardDidBecomeActive:(SimPasteboardInterface *)interface;
- (void)simPasteboardDidLoseConnection:(SimPasteboardInterface *)interface;
- (BOOL)simPasteboardShouldApplySnapshot:(SimPasteboardInterface *)interface
                                fromHost:(NSUUID *)host
                              generation:(long long)generation
                            toPasteboard:(NSPasteboard *)pasteboard;
- (void)simPasteboardDidApplySnapshot:(SimPasteboardInterface *)interface
                             fromHost:(NSUUID *)host
                   incomingGeneration:(long long)incomingGeneration
                         toPasteboard:(NSPasteboard *)pasteboard
                         atGeneration:(long long)atGeneration;
- (void)simPasteboardErrorApplyingSnapshot:(SimPasteboardInterface *)interface
                                  fromHost:(NSUUID *)host
                                generation:(long long)generation
                                     error:(NSError *)error
                              toPasteboard:(NSPasteboard *)pasteboard;
- (void)simPasteboardDidChangeAutoNotifyState:(SimPasteboardInterface *)interface
                                forPasteboard:(NSPasteboard *)pasteboard
                                     toStatus:(BOOL)status;

@end

NS_ASSUME_NONNULL_END
