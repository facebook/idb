/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/SimDisplayVideoWriter.h>

/**
 For methods that have been removed from the video writer.
 */
/**
 Removed from SimulatorKit as of Xcode 27 (CoreSimulator 1155.4): the (Removed) category on the now-removed SimDisplayVideoWriter class. No longer
 present in any Xcode 27 framework and not referenced by idb/FBSimulatorControl.
 Header retained for reference and for building against <= Xcode 26.x; scheduled
 for removal.
 */
@interface SimDisplayVideoWriter (Removed)

/**
 Both Removed in Xcode 8.3 Beta 2.
 */
+ (id)videoWriterForURL:(id)arg1 fileType:(id)arg2;
+ (id)videoWriterForDispatchIO:(id)arg1 fileType:(id)arg2;

@end
