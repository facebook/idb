# ZstdDecompress

The decompressor of [Zstandard](https://github.com/facebook/zstd) v1.5.7, as the single file its `build/single_file_libs/create_single_file_decoder.sh` generates, with the library's public headers and license. It lets idb read zstd streams without a `zstd` binary on the host.

To update it, run that script from a zstd checkout and copy `zstddeclib.c`, `lib/zstd.h`, `lib/zstd_errors.h` and `LICENSE` over the files here, then put back the `@generated` first line of the `.c` and `.h` files, which keeps formatters and license checks from rewriting upstream code.
