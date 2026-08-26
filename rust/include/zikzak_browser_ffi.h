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
typedef void (*zikzak_flutter_texture_frame_callback)(void *user_data);
typedef struct zikzak_dma_buf_frame {
  uint64_t generation;
  uint32_t plane_count;
  int32_t fds[4];
  uint32_t strides[4];
  uint64_t offsets[4];
  uint64_t sizes[4];
  uint64_t modifier;
  uint32_t format;
  int32_t coded_width;
  int32_t coded_height;
  int32_t visible_x;
  int32_t visible_y;
  int32_t visible_width;
  int32_t visible_height;
} zikzak_dma_buf_frame;
typedef int32_t (*zikzak_dma_buf_copy_callback)(
    const zikzak_dma_buf_frame *frame, void *user_data);
int32_t
zikzak_flutter_texture_attach(int64_t texture_id,
                              zikzak_flutter_texture_frame_callback callback,
                              void *user_data);
void zikzak_flutter_texture_detach(int64_t texture_id);
int64_t zikzak_flutter_texture_id(void);
int32_t zikzak_flutter_texture_resize(uint32_t width, uint32_t height);
uint32_t zikzak_flutter_texture_width(void);
uint32_t zikzak_flutter_texture_height(void);
uint64_t zikzak_flutter_texture_generation(void);
int32_t zikzak_flutter_texture_request_frame(void);
int32_t zikzak_flutter_texture_publish_gl_state(uint32_t name, uint32_t width,
                                                uint32_t height,
                                                uintptr_t egl_display,
                                                uintptr_t egl_context);
uint32_t zikzak_flutter_texture_gl_name(void);
uintptr_t zikzak_flutter_texture_egl_display(void);
uintptr_t zikzak_flutter_texture_egl_context(void);
void zikzak_flutter_texture_publish_dma_buf_result(uint64_t generation,
                                                   int32_t status,
                                                   uint64_t copy_micros,
                                                   int32_t fence_fallback);
uint64_t zikzak_flutter_texture_dma_buf_generation(void);
int32_t zikzak_flutter_texture_dma_buf_status(void);
uint64_t zikzak_flutter_texture_dma_buf_copy_count(void);
uint64_t zikzak_flutter_texture_dma_buf_last_copy_micros(void);
uint64_t zikzak_flutter_texture_dma_buf_max_copy_micros(void);
uint64_t zikzak_flutter_texture_dma_buf_fence_fallback_count(void);
int32_t zikzak_flutter_texture_render_test_frame(uint8_t *destination,
                                                 size_t destination_length,
                                                 uint32_t width,
                                                 uint32_t height,
                                                 uint64_t generation);
int32_t zikzak_render_test_frame(uint8_t *destination,
                                 size_t destination_length,
                                 uint64_t frame_number);
int32_t zikzak_cef_initialize(const char *runtime_directory,
                              const char *initial_url);
int32_t zikzak_cef_initialize_with_options(const char *runtime_directory,
                                           const char *initial_url,
                                           uint32_t transport);
int32_t zikzak_cef_shutdown(void);
int32_t zikzak_cef_pump(void);
uint64_t zikzak_cef_accelerated_paint_count(void);
uint64_t zikzak_cef_accelerated_valid_paint_count(void);
uint32_t zikzak_cef_accelerated_plane_count(void);
uint32_t zikzak_cef_accelerated_format(void);
uint64_t zikzak_cef_accelerated_modifier(void);
int32_t zikzak_cef_accelerated_coded_width(void);
int32_t zikzak_cef_accelerated_coded_height(void);
int32_t zikzak_cef_accelerated_visible_width(void);
int32_t zikzak_cef_accelerated_visible_height(void);
uint32_t zikzak_cef_accelerated_first_plane_stride(void);
uint64_t zikzak_cef_dma_buf_generation(void);
int32_t zikzak_cef_dma_buf_copy_attach(zikzak_dma_buf_copy_callback callback,
                                       void *user_data);
void zikzak_cef_dma_buf_copy_detach(void *user_data);
uint64_t zikzak_cef_frame_generation(void);
uint32_t zikzak_cef_frame_width(void);
uint32_t zikzak_cef_frame_height(void);
size_t zikzak_cef_frame_byte_length(void);
int32_t zikzak_cef_copy_latest_frame(uint8_t *destination,
                                     size_t destination_length);
int32_t zikzak_cef_navigate(const char *url);
int32_t zikzak_cef_resize(uint32_t logical_width, uint32_t logical_height,
                          float device_scale_factor);
int32_t zikzak_cef_set_focus(int32_t focused);
int32_t zikzak_cef_set_visibility(int32_t visible);
int32_t zikzak_cef_send_mouse_move(int32_t x, int32_t y, uint32_t modifiers,
                                   int32_t mouse_leave);
int32_t zikzak_cef_send_mouse_button(int32_t x, int32_t y, uint32_t modifiers,
                                     uint32_t button, int32_t mouse_up,
                                     int32_t click_count);
int32_t zikzak_cef_send_mouse_wheel(int32_t x, int32_t y, uint32_t modifiers,
                                    int32_t delta_x, int32_t delta_y);
int32_t zikzak_cef_send_key(uint32_t event_type, uint32_t modifiers,
                            int32_t windows_key_code, int32_t native_key_code,
                            uint32_t character, uint32_t unmodified_character);

#ifdef __cplusplus
}
#endif

#endif // ZIKZAK_BROWSER_FFI_H_
