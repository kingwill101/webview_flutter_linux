// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

use std::{
    f32::consts::TAU,
    sync::atomic::{AtomicI64, AtomicU32, AtomicU64, AtomicUsize, Ordering},
};

#[cfg(target_os = "linux")]
mod linux_texture;
#[cfg(all(target_os = "linux", feature = "wpe-runtime"))]
mod wpe_runtime;

const API_VERSION: u32 = 1;
const WIDTH: usize = 800;
const HEIGHT: usize = 450;
const BYTES_PER_PIXEL: usize = 4;
const MAX_DYNAMIC_FRAME_BYTE_LENGTH: usize = 512 * 1024 * 1024;

pub(crate) static FLUTTER_TEXTURE_ID: AtomicI64 = AtomicI64::new(0);
pub(crate) static FLUTTER_TEXTURE_WIDTH: AtomicU32 = AtomicU32::new(WIDTH as u32);
pub(crate) static FLUTTER_TEXTURE_HEIGHT: AtomicU32 = AtomicU32::new(HEIGHT as u32);
pub(crate) static FLUTTER_TEXTURE_GENERATION: AtomicU64 = AtomicU64::new(1);
pub(crate) static FLUTTER_TEXTURE_GL_NAME: AtomicU32 = AtomicU32::new(0);
pub(crate) static FLUTTER_TEXTURE_EGL_DISPLAY: AtomicUsize = AtomicUsize::new(0);
pub(crate) static FLUTTER_TEXTURE_EGL_CONTEXT: AtomicUsize = AtomicUsize::new(0);
pub(crate) static FLUTTER_TEXTURE_DMA_BUF_GENERATION: AtomicU64 = AtomicU64::new(0);
pub(crate) static FLUTTER_TEXTURE_DMA_BUF_STATUS: AtomicI64 = AtomicI64::new(0);
pub(crate) static FLUTTER_TEXTURE_DMA_BUF_COPY_COUNT: AtomicU64 = AtomicU64::new(0);
pub(crate) static FLUTTER_TEXTURE_DMA_BUF_LAST_COPY_MICROS: AtomicU64 = AtomicU64::new(0);
pub(crate) static FLUTTER_TEXTURE_DMA_BUF_MAX_COPY_MICROS: AtomicU64 = AtomicU64::new(0);
pub(crate) static FLUTTER_TEXTURE_DMA_BUF_FENCE_FALLBACK_COUNT: AtomicU64 = AtomicU64::new(0);

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_api_version() -> u32 {
    API_VERSION
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_initialize(engine_handle: i64) -> i32 {
    #[cfg(target_os = "linux")]
    {
        linux_texture::initialize(engine_handle)
    }
    #[cfg(not(target_os = "linux"))]
    {
        let _ = engine_handle;
        -20
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_shutdown() -> i32 {
    #[cfg(all(target_os = "linux", feature = "wpe-runtime"))]
    let wpe_status = wpe_runtime::webview_flutter_linux_wpe_shutdown();
    #[cfg(not(all(target_os = "linux", feature = "wpe-runtime")))]
    let wpe_status = 1;

    #[cfg(target_os = "linux")]
    let texture_status = linux_texture::shutdown();
    #[cfg(not(target_os = "linux"))]
    let texture_status = 0;

    if wpe_status < 0 {
        wpe_status
    } else {
        texture_status
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_id() -> i64 {
    FLUTTER_TEXTURE_ID.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_resize(width: u32, height: u32) -> i32 {
    if checked_dynamic_frame_byte_length(width, height).is_none() {
        return -1;
    }
    let old_width = FLUTTER_TEXTURE_WIDTH.swap(width, Ordering::AcqRel);
    let old_height = FLUTTER_TEXTURE_HEIGHT.swap(height, Ordering::AcqRel);
    if old_width != width || old_height != height {
        FLUTTER_TEXTURE_GENERATION.fetch_add(1, Ordering::AcqRel);
    }
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_width() -> u32 {
    FLUTTER_TEXTURE_WIDTH.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_height() -> u32 {
    FLUTTER_TEXTURE_HEIGHT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_generation() -> u64 {
    FLUTTER_TEXTURE_GENERATION.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_request_frame() -> i32 {
    #[cfg(target_os = "linux")]
    {
        linux_texture::mark_frame_available()
    }
    #[cfg(not(target_os = "linux"))]
    {
        -20
    }
}

pub(crate) fn notify_flutter_texture_frame() -> i32 {
    webview_flutter_linux_texture_request_frame()
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_dma_buf_generation() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_GENERATION.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_dma_buf_status() -> i32 {
    FLUTTER_TEXTURE_DMA_BUF_STATUS.load(Ordering::Acquire) as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_dma_buf_copy_count() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_COPY_COUNT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_dma_buf_last_copy_micros() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_LAST_COPY_MICROS.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_dma_buf_max_copy_micros() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_MAX_COPY_MICROS.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_dma_buf_fence_fallback_count() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_FENCE_FALLBACK_COUNT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_gl_name() -> u32 {
    FLUTTER_TEXTURE_GL_NAME.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_egl_display() -> usize {
    FLUTTER_TEXTURE_EGL_DISPLAY.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_texture_egl_context() -> usize {
    FLUTTER_TEXTURE_EGL_CONTEXT.load(Ordering::Acquire)
}

pub(crate) fn checked_dynamic_frame_byte_length(width: u32, height: u32) -> Option<usize> {
    let width = usize::try_from(width).ok()?;
    let height = usize::try_from(height).ok()?;
    if width == 0 || height == 0 {
        return None;
    }
    let length = width.checked_mul(height)?.checked_mul(BYTES_PER_PIXEL)?;
    (length <= MAX_DYNAMIC_FRAME_BYTE_LENGTH).then_some(length)
}

pub(crate) fn render_flutter_texture_test_frame(
    pixels: &mut [u8],
    width: usize,
    height: usize,
    generation: u64,
) {
    let accent = (generation % 96) as u8;
    for y in 0..height {
        for x in 0..width {
            let offset = (y * width + x) * BYTES_PER_PIXEL;
            let grid = x % 32 == 0 || y % 32 == 0;
            let checker = ((x / 32) + (y / 32)) % 2 == 0;
            let diagonal = x * height / width.max(1) == y;
            let rgba = if diagonal {
                [255, 205, 92, 255]
            } else if grid {
                [69, 220, 185, 255]
            } else if checker {
                [27, 34 + accent / 3, 57 + accent / 2, 255]
            } else {
                [18, 23, 39 + accent / 4, 255]
            };
            pixels[offset..offset + BYTES_PER_PIXEL].copy_from_slice(&rgba);
        }
    }

    let radius = width.min(height) as f32 * 0.16;
    let center_x = width as f32 * 0.72;
    let center_y = height as f32 * 0.48;
    let phase = generation as f32 * 0.035;
    for step in 0..180 {
        let angle = step as f32 / 180.0 * TAU + phase;
        let x = (center_x + angle.cos() * radius) as isize;
        let y = (center_y + angle.sin() * radius) as isize;
        if x < 0 || y < 0 || x >= width as isize || y >= height as isize {
            continue;
        }
        let offset = (y as usize * width + x as usize) * BYTES_PER_PIXEL;
        pixels[offset..offset + BYTES_PER_PIXEL].copy_from_slice(&[255, 118, 97, 255]);
    }
}
