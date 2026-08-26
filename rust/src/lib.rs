// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

use std::f32::consts::TAU;

#[cfg(target_os = "linux")]
mod linux_texture;
#[cfg(all(target_os = "linux", feature = "wpe-runtime"))]
mod wpe_runtime;

const API_VERSION: u32 = 2;
pub(crate) const WIDTH: usize = 800;
pub(crate) const HEIGHT: usize = 450;
const BYTES_PER_PIXEL: usize = 4;
const MAX_DYNAMIC_FRAME_BYTE_LENGTH: usize = 512 * 1024 * 1024;

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_api_version() -> u32 {
    API_VERSION
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
