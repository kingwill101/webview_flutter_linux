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
uint32_t zikzak_cef_frame_width(void);
uint32_t zikzak_cef_frame_height(void);
size_t zikzak_cef_frame_byte_length(void);
int32_t zikzak_cef_copy_latest_frame(
    uint8_t* destination,
    size_t destination_length);
int32_t zikzak_cef_navigate(const char* url);
int32_t zikzak_cef_resize(
    uint32_t logical_width,
    uint32_t logical_height,
    float device_scale_factor);
int32_t zikzak_cef_set_focus(int32_t focused);
int32_t zikzak_cef_send_mouse_move(
    int32_t x,
    int32_t y,
    uint32_t modifiers,
    int32_t mouse_leave);
int32_t zikzak_cef_send_mouse_button(
    int32_t x,
    int32_t y,
    uint32_t modifiers,
    uint32_t button,
    int32_t mouse_up,
    int32_t click_count);
int32_t zikzak_cef_send_mouse_wheel(
    int32_t x,
    int32_t y,
    uint32_t modifiers,
    int32_t delta_x,
    int32_t delta_y);
int32_t zikzak_cef_send_key(
    uint32_t event_type,
    uint32_t modifiers,
    int32_t windows_key_code,
    int32_t native_key_code,
    uint32_t character,
    uint32_t unmodified_character);

#ifdef __cplusplus
}
#endif

#endif  // ZIKZAK_BROWSER_FFI_H_
