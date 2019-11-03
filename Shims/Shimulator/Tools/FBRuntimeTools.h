/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/**
 Method used to retrieve pointer for given symbol 'name' from given 'binary'

 @param binary path to binary we want to retrieve symbols pointer from
 @param name name of the symbol
 @return pointer to symbol
 */
void *FBRetrieveSymbolFromBinary(const char *binary, const char *name);

/**
 Method used to retrieve pointer for given symbol 'name' from given 'binary'

 @param name name of the symbol
 @return pointer to symbol
 */
void *FBRetrieveXCTestSymbol(const char *name);
