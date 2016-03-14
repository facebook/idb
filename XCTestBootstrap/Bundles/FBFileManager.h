// Copyright 2004-present Facebook. All Rights Reserved.

#import <Foundation/Foundation.h>

/**
 Used for file IO
 */
@protocol FBFileManager <NSObject>

/**
 Creates a directory with given attributes at the specified path.

 @param path A path string identifying the directory to create. You may specify a full path or a path that is relative to the current working directory. This parameter must not be nil.
 @param createIntermediates If YES, this method creates any non-existent parent directories as part of creating the directory in path. If NO, this method fails if any of the intermediate parent directories does not exist. This method also fails if any of the intermediate path elements corresponds to a file and not a directory.
 @param attributes The file attributes for the new directory and any newly created intermediate directories. You can set the owner and group numbers, file permissions, and modification date. If you specify nil for this parameter or omit a particular value, one or more default values are used as described in the discussion. For a list of keys you can include in this dictionary, see Constants section lists the global constants used as keys in the attributes dictionary. Some of the keys, such as NSFileHFSCreatorCode and NSFileHFSTypeCode, do not apply to directories.
 @param error On input, a pointer to an error object. If an error occurs, this pointer is set to an actual error object containing the error information. You may specify nil for this parameter if you do not want the error information.
 @return YES if the directory was created, YES if createIntermediates is set and the directory already exists), or NO if an error occurred.
 */
- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates attributes:(NSDictionary<NSString *, id> *)attributes error:(NSError **)error NS_AVAILABLE(10_5, 2_0);

/**
 Copies the item at the specified path to a new location synchronously.

 @param srcPath The path to the file or directory you want to move. This parameter must not be nil.
 @param dstPath The path at which to place the copy of srcPath. This path must include the name of the file or directory in its new location. This parameter must not be nil.
 @param error On input, a pointer to an error object. If an error occurs, this pointer is set to an actual error object containing the error information. You may specify nil for this parameter if you do not want the error information.
 @return YES if the item was copied successfully
 */
- (BOOL)copyItemAtPath:(NSString *)srcPath toPath:(NSString *)dstPath error:(NSError **)error NS_AVAILABLE(10_5, 2_0);

/**
 Writes the bytes in the data to the file specified by a given path.

 @param data data that should be written
 @param toFile The location to which to write data.
 @param options A mask that specifies options for writing the data. Constant components are described in "NSDataWritingOptions".
 @param error If there is an error writing out the data, upon return contains an NSError object that describes the problem.
 @return YES if the operation succeeds, otherwise NO.
 */
- (BOOL)writeData:(NSData *)data toFile:(NSString *)toFile options:(NSDataWritingOptions)options error:(NSError **)error;
/**
 Creates and returns a dictionary using the keys and values found in a file specified by a given path.
 A new dictionary that contains the dictionary at path, or nil if there is a file error or if the contents of the file are an invalid representation of a dictionary.

 @param path A full or relative pathname. The file identified by path must contain a string representation of a property list whose root object is a dictionary.
 @return A new dictionary that contains the dictionary at path, or nil if there is a file error or if the contents of the file are an invalid representation of a dictionary.
 */
- (NSDictionary *)dictionaryWithPath:(NSString *)path;

@end
