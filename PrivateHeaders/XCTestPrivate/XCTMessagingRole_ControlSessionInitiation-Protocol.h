/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTCapabilities;

@protocol XCTMessagingRole_ControlSessionInitiation
- (id)_IDE_authorizeTestSessionWithProcessID:(NSNumber *)arg1;
- (id)_IDE_initiateControlSessionWithCapabilities:(XCTCapabilities *)arg1;
- (id)_IDE_initiateControlSessionWithProtocolVersion:(NSNumber *)arg1;
- (id)_IDE_initiateControlSessionForTestProcessID:(NSNumber *)arg1 protocolVersion:(NSNumber *)arg2;
- (id)_IDE_initiateControlSessionForTestProcessID:(NSNumber *)arg1;
@end

