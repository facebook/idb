/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

// `TestRepl` subclasses `XCTestCase`, whose class symbol is provided by the
// xctest host at runtime (it is not linked). Marking it `weak_import` makes the
// emitted superclass reference weak, so loading this dylib into a process
// *without* XCTest (e.g. SimulatorFrameworkBridge, which dlopens it to serve the
// REPL) resolves the symbol to null and simply skips realizing `TestRepl`,
// rather than failing the load with "Symbol not found: _OBJC_CLASS_$_XCTestCase".
__attribute__((weak_import))
@interface XCTest : NSObject
@end

__attribute__((weak_import))
@interface XCTestCase : XCTest
@end
