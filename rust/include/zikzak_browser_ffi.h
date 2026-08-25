/* SPDX-License-Identifier: UNLICENSED */

#ifndef ZIKZAK_BROWSER_FFI_H_
#define ZIKZAK_BROWSER_FFI_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

uint32_t zikzak_api_version(void);
uint32_t zikzak_frame_width(void);
uint32_t zikzak_frame_height(void);
size_t zikzak_frame_byte_length(void);
int32_t zikzak_render_test_frame(
    uint8_t* destination,
    size_t destination_length,
    uint64_t frame_number);
int32_t zikzak_cef_initialize(
    const char* runtime_directory,
    const char* initial_url);
int32_t zikzak_cef_pump(void);
uint64_t zikzak_cef_frame_generation(void);
int32_t zikzak_cef_copy_latest_frame(
    uint8_t* destination,
    size_t destination_length);
int32_t zikzak_cef_navigate(const char* url);

#ifdef __cplusplus
}
#endif

#endif  // ZIKZAK_BROWSER_FFI_H_
