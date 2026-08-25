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

#ifdef __cplusplus
}
#endif

#endif  // ZIKZAK_BROWSER_FFI_H_
