/**
 @name: 上游同步模块
 @Descripttion: 维护 Codenotch-Bridging-Header.h 的项目实现与上游兼容。
 @version: 1.0.0
 @Author: sm
 @Date: 2026-09-11 15:51:14
 @LastEditTime: 2026-09-11 15:51:14
 @FilePath: Sources/Codenotch-Bridging-Header.h
 */
// What the Swift side of the app can see of the C side.
//
// One entry, and it is expected to stay that way: the only C in this project is
// the vendored Zstandard decoder, needed because Claude Desktop's HTTP cache
// stores bodies as zstd and macOS ships no decoder for it. See
// Sources/Vendor/zstd/README.md.
#import "Vendor/zstd/CodenotchZstd.h"
