// SPDX-License-Identifier: UNLICENSED

use std::{
    f32::consts::TAU,
    sync::atomic::{AtomicI64, AtomicU32, AtomicU64, AtomicUsize, Ordering},
};

#[cfg(feature = "cef-runtime")]
mod cef_runtime;
#[cfg(target_os = "linux")]
mod linux_texture;
#[cfg(all(target_os = "linux", feature = "wpe-runtime"))]
mod wpe_runtime;

const API_VERSION: u32 = 6;
const WIDTH: usize = 800;
const HEIGHT: usize = 450;
const BYTES_PER_PIXEL: usize = 4;
const FRAME_BYTE_LENGTH: usize = WIDTH * HEIGHT * BYTES_PER_PIXEL;
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
pub extern "C" fn cef_texture_browser_api_version() -> u32 {
    API_VERSION
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_browser_backend() -> u32 {
    #[cfg(feature = "wpe-runtime")]
    {
        return 2;
    }
    #[cfg(all(not(feature = "wpe-runtime"), feature = "cef-runtime"))]
    {
        return 1;
    }
    #[allow(unreachable_code)]
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_frame_width() -> u32 {
    WIDTH as u32
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_frame_height() -> u32 {
    HEIGHT as u32
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_frame_byte_length() -> usize {
    FRAME_BYTE_LENGTH
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_initialize(engine_handle: i64) -> i32 {
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
pub extern "C" fn cef_texture_browser_native_shutdown() -> i32 {
    #[cfg(feature = "cef-runtime")]
    let cef_status = cef_runtime::cef_texture_browser_cef_shutdown();
    #[cfg(not(feature = "cef-runtime"))]
    let cef_status = 1;

    #[cfg(all(target_os = "linux", feature = "wpe-runtime"))]
    let wpe_status = wpe_runtime::cef_texture_browser_wpe_shutdown();
    #[cfg(not(all(target_os = "linux", feature = "wpe-runtime")))]
    let wpe_status = 1;

    #[cfg(target_os = "linux")]
    let texture_status = linux_texture::shutdown();
    #[cfg(not(target_os = "linux"))]
    let texture_status = 0;

    if cef_status < 0 {
        cef_status
    } else if wpe_status < 0 {
        wpe_status
    } else {
        texture_status
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_id() -> i64 {
    FLUTTER_TEXTURE_ID.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_resize(width: u32, height: u32) -> i32 {
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
pub extern "C" fn cef_texture_browser_flutter_texture_width() -> u32 {
    FLUTTER_TEXTURE_WIDTH.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_height() -> u32 {
    FLUTTER_TEXTURE_HEIGHT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_generation() -> u64 {
    FLUTTER_TEXTURE_GENERATION.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_request_frame() -> i32 {
    #[cfg(target_os = "linux")]
    {
        linux_texture::mark_frame_available()
    }
    #[cfg(not(target_os = "linux"))]
    {
        -20
    }
}

#[cfg(any(feature = "cef-runtime", feature = "wpe-runtime"))]
pub(crate) fn notify_flutter_texture_frame() -> i32 {
    cef_texture_browser_flutter_texture_request_frame()
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_dma_buf_generation() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_GENERATION.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_dma_buf_status() -> i32 {
    FLUTTER_TEXTURE_DMA_BUF_STATUS.load(Ordering::Acquire) as i32
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_dma_buf_copy_count() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_COPY_COUNT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_dma_buf_last_copy_micros() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_LAST_COPY_MICROS.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_dma_buf_max_copy_micros() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_MAX_COPY_MICROS.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_dma_buf_fence_fallback_count() -> u64 {
    FLUTTER_TEXTURE_DMA_BUF_FENCE_FALLBACK_COUNT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_gl_name() -> u32 {
    FLUTTER_TEXTURE_GL_NAME.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_egl_display() -> usize {
    FLUTTER_TEXTURE_EGL_DISPLAY.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_flutter_texture_egl_context() -> usize {
    FLUTTER_TEXTURE_EGL_CONTEXT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
/// Renders the procedural startup frame into a dynamically sized caller buffer.
///
/// # Safety
///
/// `destination` must point to at least `destination_length` writable bytes and
/// remain valid for the duration of this call.
pub unsafe extern "C" fn cef_texture_browser_flutter_texture_render_test_frame(
    destination: *mut u8,
    destination_length: usize,
    width: u32,
    height: u32,
    generation: u64,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    let Some(byte_length) = checked_dynamic_frame_byte_length(width, height) else {
        return -2;
    };
    if destination_length < byte_length {
        return -3;
    }
    // SAFETY: The caller supplied a non-null pointer and declared at least the
    // validated complete-frame byte length as writable.
    let pixels = unsafe { std::slice::from_raw_parts_mut(destination, byte_length) };
    render_flutter_texture_test_frame(pixels, width as usize, height as usize, generation);
    0
}

fn checked_dynamic_frame_byte_length(width: u32, height: u32) -> Option<usize> {
    let width = usize::try_from(width).ok()?;
    let height = usize::try_from(height).ok()?;
    if width == 0 || height == 0 {
        return None;
    }
    let length = width.checked_mul(height)?.checked_mul(BYTES_PER_PIXEL)?;
    (length <= MAX_DYNAMIC_FRAME_BYTE_LENGTH).then_some(length)
}

fn render_flutter_texture_test_frame(
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
                [44 + accent / 6, 39, 92, 255]
            } else {
                [18, 22 + accent / 8, 42, 255]
            };
            pixels[offset..offset + BYTES_PER_PIXEL].copy_from_slice(&rgba);
        }
    }
}

/// Renders a deterministic RGBA test frame into memory owned by the caller.
///
/// This ownership model is intentional: the future CEF callback can publish its
/// latest frame into the same destination without handing Dart a borrowed Rust
/// pointer whose lifetime could end while Flutter is uploading it.
///
/// Returns zero on success, -1 for a null destination, and -2 if the supplied
/// destination is smaller than a complete frame.
///
/// # Safety
///
/// `destination` must point to at least `destination_length` writable bytes and
/// remain valid for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cef_texture_browser_render_test_frame(
    destination: *mut u8,
    destination_length: usize,
    frame_number: u64,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    if destination_length < FRAME_BYTE_LENGTH {
        return -2;
    }

    // SAFETY: The caller supplied a non-null pointer and declared that at least
    // FRAME_BYTE_LENGTH writable bytes are available at that address.
    let pixels = unsafe { std::slice::from_raw_parts_mut(destination, FRAME_BYTE_LENGTH) };
    render_frame(pixels, frame_number);
    0
}

fn render_frame(pixels: &mut [u8], frame_number: u64) {
    let time = frame_number as f32 / 60.0;

    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            let t = y as f32 / HEIGHT as f32;
            let grid = if x % 40 == 0 || y % 40 == 0 { 8 } else { 0 };
            put_pixel(
                pixels,
                x,
                y,
                [
                    (14.0 + 12.0 * t) as u8 + grid,
                    (18.0 + 14.0 * t) as u8 + grid,
                    (31.0 + 24.0 * t) as u8 + grid,
                    255,
                ],
            );
        }
    }

    fill_rounded_rect(pixels, 28, 24, 744, 402, 22, [29, 34, 54, 255]);
    fill_rounded_rect(pixels, 48, 44, 704, 48, 14, [17, 21, 36, 255]);
    fill_circle(pixels, 72, 68, 7, [255, 101, 113, 255]);
    fill_circle(pixels, 94, 68, 7, [250, 190, 74, 255]);
    fill_circle(pixels, 116, 68, 7, [62, 205, 133, 255]);
    fill_rounded_rect(pixels, 148, 54, 470, 28, 10, [42, 48, 71, 255]);
    fill_rounded_rect(pixels, 634, 54, 98, 28, 10, [91, 79, 207, 255]);

    fill_rounded_rect(pixels, 48, 112, 704, 286, 18, [239, 241, 249, 255]);
    fill_rounded_rect(pixels, 84, 146, 278, 18, 7, [45, 51, 75, 255]);
    fill_rounded_rect(pixels, 84, 178, 210, 9, 4, [142, 149, 174, 255]);
    fill_rounded_rect(pixels, 84, 198, 250, 9, 4, [170, 176, 198, 255]);
    fill_rounded_rect(pixels, 84, 218, 224, 9, 4, [170, 176, 198, 255]);
    fill_rounded_rect(pixels, 84, 256, 132, 42, 12, [102, 88, 232, 255]);

    let orbit_x = 585.0 + (time * 0.83).cos() * 54.0;
    let orbit_y = 250.0 + (time * 1.17).sin() * 42.0;
    fill_circle(pixels, 585, 250, 86, [103, 91, 225, 255]);
    fill_circle(
        pixels,
        orbit_x as isize,
        orbit_y as isize,
        35,
        [43, 207, 165, 220],
    );
    fill_circle(
        pixels,
        (585.0 + (time * TAU / 5.0).sin() * 26.0) as isize,
        (250.0 + (time * TAU / 7.0).cos() * 24.0) as isize,
        13,
        [255, 205, 92, 255],
    );

    let progress = ((frame_number % 240) as usize * 620) / 239;
    fill_rounded_rect(pixels, 84, 352, 620, 8, 4, [212, 216, 230, 255]);
    if progress > 0 {
        fill_rounded_rect(pixels, 84, 352, progress, 8, 4, [43, 207, 165, 255]);
    }
}

fn put_pixel(pixels: &mut [u8], x: usize, y: usize, rgba: [u8; 4]) {
    let offset = (y * WIDTH + x) * BYTES_PER_PIXEL;
    pixels[offset..offset + BYTES_PER_PIXEL].copy_from_slice(&rgba);
}

fn fill_circle(pixels: &mut [u8], center_x: isize, center_y: isize, radius: isize, rgba: [u8; 4]) {
    let radius_squared = radius * radius;
    for y in (center_y - radius).max(0)..=(center_y + radius).min(HEIGHT as isize - 1) {
        for x in (center_x - radius).max(0)..=(center_x + radius).min(WIDTH as isize - 1) {
            let dx = x - center_x;
            let dy = y - center_y;
            if dx * dx + dy * dy <= radius_squared {
                put_pixel(pixels, x as usize, y as usize, rgba);
            }
        }
    }
}

fn fill_rounded_rect(
    pixels: &mut [u8],
    left: usize,
    top: usize,
    width: usize,
    height: usize,
    radius: usize,
    rgba: [u8; 4],
) {
    let right = (left + width).min(WIDTH);
    let bottom = (top + height).min(HEIGHT);
    let radius = radius.min(width / 2).min(height / 2) as isize;
    let left = left as isize;
    let top = top as isize;
    let right_i = right as isize;
    let bottom_i = bottom as isize;

    for y in top as usize..bottom {
        for x in left as usize..right {
            let x = x as isize;
            let y = y as isize;
            let corner_x = if x < left + radius {
                left + radius
            } else if x >= right_i - radius {
                right_i - radius - 1
            } else {
                x
            };
            let corner_y = if y < top + radius {
                top + radius
            } else if y >= bottom_i - radius {
                bottom_i - radius - 1
            } else {
                y
            };
            let dx = x - corner_x;
            let dy = y - corner_y;
            if dx * dx + dy * dy <= radius * radius {
                put_pixel(pixels, x as usize, y as usize, rgba);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_a_complete_non_empty_frame() {
        let mut pixels = vec![0; FRAME_BYTE_LENGTH];
        let result =
            unsafe { cef_texture_browser_render_test_frame(pixels.as_mut_ptr(), pixels.len(), 30) };

        assert_eq!(result, 0);
        assert!(pixels.iter().any(|component| *component != 0));
        assert_eq!(pixels.len(), cef_texture_browser_frame_byte_length());
    }

    #[test]
    fn rejects_a_short_destination() {
        let mut pixels = vec![0; FRAME_BYTE_LENGTH - 1];
        let result =
            unsafe { cef_texture_browser_render_test_frame(pixels.as_mut_ptr(), pixels.len(), 0) };

        assert_eq!(result, -2);
    }

    #[test]
    fn renders_a_dynamic_flutter_texture_frame() {
        let length = checked_dynamic_frame_byte_length(97, 53).unwrap();
        let mut pixels = vec![0; length];
        let result = unsafe {
            cef_texture_browser_flutter_texture_render_test_frame(
                pixels.as_mut_ptr(),
                pixels.len(),
                97,
                53,
                7,
            )
        };

        assert_eq!(result, 0);
        assert_eq!(pixels.len(), 97 * 53 * BYTES_PER_PIXEL);
        assert!(pixels.chunks_exact(4).all(|pixel| pixel[3] == 255));
        assert!(pixels.chunks_exact(4).any(|pixel| pixel[0] == 255));
    }

    #[test]
    fn rejects_invalid_dynamic_flutter_texture_frames() {
        let mut byte = 0_u8;
        let result =
            unsafe { cef_texture_browser_flutter_texture_render_test_frame(&mut byte, 1, 0, 1, 0) };
        assert_eq!(result, -2);

        let result =
            unsafe { cef_texture_browser_flutter_texture_render_test_frame(&mut byte, 1, 2, 2, 0) };
        assert_eq!(result, -3);
    }
}
