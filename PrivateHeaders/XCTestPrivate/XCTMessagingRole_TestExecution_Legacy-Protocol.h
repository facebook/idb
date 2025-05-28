/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@protocol XCTMessagingRole_TestExecution_Legacy
- (id)_IDE_executeTestIdentifiers:(NSSet *)arg1 skippingTestIdentifiers:(NSSet *)arg2;
- (id)_IDE_fetchDiscoveredTestClasses;
@end

