/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTCapabilities;

@protocol XCTMessagingRole_RunnerSessionInitiation
- (id)_IDE_initiateSessionWithIdentifier:(NSUUID *)arg1 forClient:(NSString *)arg2 atPath:(NSString *)arg3 protocolVersion:(NSNumber *)arg4;
- (id)_IDE_initiateSessionWithIdentifier:(NSUUID *)arg1 capabilities:(XCTCapabilities *)arg2;
@end

