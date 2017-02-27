/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

@class NSObject, NSUUID;
@protocol SimPasteboard;

@protocol SimPasteboardSyncPoolProtocol
@property (readonly, retain, nonatomic) NSUUID *poolIdentifier;
- (BOOL)removePasteboard:(NSObject<SimPasteboard> *)arg1 withError:(id *)arg2;
- (BOOL)addPasteboard:(NSObject<SimPasteboard> *)arg1 withError:(id *)arg2;
@end
