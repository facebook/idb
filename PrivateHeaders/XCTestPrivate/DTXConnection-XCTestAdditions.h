/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DTXConnectionServices/DTXConnection.h"

@interface DTXConnection (XCTestAdditions)
- (id)xct_makeProxyChannelWithRemoteInterface:(id)arg1 exportedInterface:(id)arg2;
- (void)xct_handleProxyRequestForInterface:(id)arg1 peerInterface:(id)arg2 handler:(id)arg3;
@end
