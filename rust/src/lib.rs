// SPDX-License-Identifier: UNLICENSED

use std::f32::consts::TAU;

#[cfg(feature = "cef-runtime")]
mod cef_runtime;

const API_VERSION: u32 = 2;
const WIDTH: usize = 800;
const HEIGHT: usize = 450;
const BYTES_PER_PIXEL: usize = 4;
const FRAME_BYTE_LENGTH: usize = WIDTH * HEIGHT * BYTES_PER_PIXEL;

#[unsafe(no_mangle)]
pub extern "C" fn zikzak_api_version() -> u32 {
    API_VERSION
}

#[unsafe(no_mangle)]
pub extern "C" fn zikzak_frame_width() -> u32 {
    WIDTH as u32
}

#[unsafe(no_mangle)]
pub extern "C" fn zikzak_frame_height() -> u32 {
    HEIGHT as u32
}

#[unsafe(no_mangle)]
pub extern "C" fn zikzak_frame_byte_length() -> usize {
    FRAME_BYTE_LENGTH
}

/// Renders a deterministic RGBA test frame into memory owned by the caller.
///
/// This ownership model is intentional: the future CEF callback can publish its
/// latest frame into the same destination without handing Dart a borrowed Rust
/// pointer whose lifetime could end while Flutter is uploading it.
///
/// Returns zero on success, -1 for a null destination, and -2 if the supplied
/// destination is smaller than a complete frame.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn zikzak_render_test_frame(
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
        let result = unsafe { zikzak_render_test_frame(pixels.as_mut_ptr(), pixels.len(), 30) };

        assert_eq!(result, 0);
        assert!(pixels.iter().any(|component| *component != 0));
        assert_eq!(pixels.len(), zikzak_frame_byte_length());
    }

    #[test]
    fn rejects_a_short_destination() {
        let mut pixels = vec![0; FRAME_BYTE_LENGTH - 1];
        let result = unsafe { zikzak_render_test_frame(pixels.as_mut_ptr(), pixels.len(), 0) };

        assert_eq!(result, -2);
    }
}
