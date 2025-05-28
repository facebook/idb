/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class XCTTestIdentifierSet;

@protocol XCTMessagingRole_TestExecution
- (id)_IDE_shutdown;
- (id)_IDE_executeTestsWithIdentifiersToRun:(XCTTestIdentifierSet *)arg1 identifiersToSkip:(XCTTestIdentifierSet *)arg2;
- (id)_IDE_fetchParallelizableTestIdentifiers;
- (id)_IDE_startExecutingTestPlanWithProtocolVersion:(NSNumber *)arg1;
@end

