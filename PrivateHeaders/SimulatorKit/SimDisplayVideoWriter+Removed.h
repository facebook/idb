/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <SimulatorKit/SimDisplayVideoWriter.h>

/**
 For methods that have been removed from the video writer.
 */
@interface SimDisplayVideoWriter (Removed)

/**
 Both Removed in Xcode 8.3 Beta 2.
 */
+ (id)videoWriterForURL:(id)arg1 fileType:(id)arg2;
+ (id)videoWriterForDispatchIO:(id)arg1 fileType:(id)arg2;

@end
