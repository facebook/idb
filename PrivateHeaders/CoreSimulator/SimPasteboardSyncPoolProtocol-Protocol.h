/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSObject, NSUUID;
@protocol SimPasteboard;

@protocol SimPasteboardSyncPoolProtocol
@property (readonly, retain, nonatomic) NSUUID *poolIdentifier;
- (BOOL)removePasteboard:(NSObject<SimPasteboard> *)arg1 withError:(id *)arg2;
- (BOOL)addPasteboard:(NSObject<SimPasteboard> *)arg1 withError:(id *)arg2;
@end
