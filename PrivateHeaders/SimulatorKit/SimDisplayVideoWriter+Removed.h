/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
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
