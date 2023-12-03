/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@class NSArray, NSDate, XCTSpindumpRequestSpecification;

@protocol XCTMessagingRole_DiagnosticsCollection
- (id)_IDE_requestSpindumpWithSpecification:(XCTSpindumpRequestSpecification *)arg1;
- (id)_IDE_requestSpindump;
- (id)_IDE_requestLogArchiveWithStartDate:(NSDate *)arg1;
- (id)_IDE_collectNewCrashReportsInDirectories:(NSArray *)arg1 matchingProcessNames:(NSArray *)arg2;
@end

