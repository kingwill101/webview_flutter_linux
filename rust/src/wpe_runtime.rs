// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

use std::{
    cell::RefCell,
    ffi::{CStr, c_char},
    os::fd::{FromRawFd, OwnedFd},
    sync::atomic::{AtomicU32, AtomicU64, Ordering},
};

use glib::{
    MainContext,
    prelude::*,
    translate::{FromGlib, ToGlibPtr, from_glib_full},
};

const MAX_PLANES: usize = 4;
const RENDER_FENCE_TIMEOUT_MS: i32 = 100;

const WPE_EVENT_POINTER_DOWN: i32 = 1;
const WPE_EVENT_POINTER_UP: i32 = 2;
const WPE_EVENT_POINTER_MOVE: i32 = 3;
const WPE_EVENT_KEYBOARD_KEY_DOWN: i32 = 7;
const WPE_EVENT_KEYBOARD_KEY_UP: i32 = 8;
const WPE_INPUT_SOURCE_MOUSE: i32 = 0;
const WPE_INPUT_SOURCE_KEYBOARD: i32 = 2;

const WPE_MODIFIER_KEYBOARD_CONTROL: u32 = 1 << 0;
const WPE_MODIFIER_KEYBOARD_SHIFT: u32 = 1 << 1;
const WPE_MODIFIER_KEYBOARD_ALT: u32 = 1 << 2;
const WPE_MODIFIER_KEYBOARD_META: u32 = 1 << 3;
const WPE_MODIFIER_KEYBOARD_CAPS_LOCK: u32 = 1 << 4;
const WPE_MODIFIER_POINTER_BUTTON1: u32 = 1 << 8;
const WPE_MODIFIER_POINTER_BUTTON2: u32 = 1 << 9;
const WPE_MODIFIER_POINTER_BUTTON3: u32 = 1 << 10;

#[repr(C)]
struct WpeDisplay {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WpeView {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WpeToplevel {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WpeBuffer {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WpeBufferDmaBuf {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WpeEvent {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WpeClipboard {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WpeClipboardContent {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WebKitWebView {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WebKitNetworkSession {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WebKitSettings {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WebKitContextMenu {
    _opaque: [u8; 0],
}

#[repr(C)]
struct WebKitContextMenuItem {
    _opaque: [u8; 0],
}

#[repr(C)]
struct GAction {
    _opaque: [u8; 0],
}

#[repr(C)]
struct GVariant {
    _opaque: [u8; 0],
}

unsafe extern "C" {
    fn wpe_display_headless_new() -> *mut WpeDisplay;
    fn wpe_display_get_clipboard(display: *mut WpeDisplay) -> *mut WpeClipboard;
    fn wpe_clipboard_get_change_count(clipboard: *mut WpeClipboard) -> i64;
    fn wpe_clipboard_set_content(clipboard: *mut WpeClipboard, content: *mut WpeClipboardContent);
    fn wpe_clipboard_read_text(
        clipboard: *mut WpeClipboard,
        format: *const c_char,
        size: *mut usize,
    ) -> *mut c_char;
    fn wpe_clipboard_content_new() -> *mut WpeClipboardContent;
    fn wpe_clipboard_content_unref(content: *mut WpeClipboardContent);
    fn wpe_clipboard_content_set_text(content: *mut WpeClipboardContent, text: *const c_char);
    fn webkit_network_session_new_ephemeral() -> *mut WebKitNetworkSession;
    fn webkit_web_view_get_type() -> glib::ffi::GType;
    fn webkit_web_view_get_display(web_view: *mut WebKitWebView) -> *mut WpeDisplay;
    fn webkit_web_view_get_wpe_view(web_view: *mut WebKitWebView) -> *mut WpeView;
    fn webkit_web_view_get_settings(web_view: *mut WebKitWebView) -> *mut WebKitSettings;
    fn webkit_web_view_set_is_muted(web_view: *mut WebKitWebView, muted: i32);
    fn webkit_web_view_load_uri(web_view: *mut WebKitWebView, uri: *const c_char);
    fn webkit_settings_set_enable_media(settings: *mut WebKitSettings, enabled: i32);
    fn webkit_settings_set_enable_webaudio(settings: *mut WebKitSettings, enabled: i32);
    fn webkit_settings_set_media_playback_requires_user_gesture(
        settings: *mut WebKitSettings,
        enabled: i32,
    );
    fn webkit_context_menu_get_n_items(menu: *mut WebKitContextMenu) -> u32;
    fn webkit_context_menu_get_item_at_position(
        menu: *mut WebKitContextMenu,
        position: u32,
    ) -> *mut WebKitContextMenuItem;
    fn webkit_context_menu_get_position(
        menu: *mut WebKitContextMenu,
        x: *mut i32,
        y: *mut i32,
    ) -> i32;
    fn webkit_context_menu_item_get_title(item: *mut WebKitContextMenuItem) -> *const c_char;
    fn webkit_context_menu_item_is_separator(item: *mut WebKitContextMenuItem) -> i32;
    fn webkit_context_menu_item_get_gaction(item: *mut WebKitContextMenuItem) -> *mut GAction;
    fn webkit_context_menu_item_get_gaction_target(
        item: *mut WebKitContextMenuItem,
    ) -> *mut GVariant;
    fn g_action_get_enabled(action: *mut GAction) -> i32;
    fn g_action_activate(action: *mut GAction, parameter: *mut GVariant);
    fn g_variant_ref(value: *mut GVariant) -> *mut GVariant;
    fn g_variant_unref(value: *mut GVariant);

    fn wpe_view_get_toplevel(view: *mut WpeView) -> *mut WpeToplevel;
    fn wpe_toplevel_resize(toplevel: *mut WpeToplevel, width: i32, height: i32) -> i32;
    fn wpe_view_resized(view: *mut WpeView, width: i32, height: i32);
    fn wpe_view_buffer_released(view: *mut WpeView, buffer: *mut WpeBuffer);
    fn wpe_view_event(view: *mut WpeView, event: *mut WpeEvent);
    fn wpe_view_focus_in(view: *mut WpeView);
    fn wpe_view_focus_out(view: *mut WpeView);
    fn wpe_view_set_visible(view: *mut WpeView, visible: i32);

    fn wpe_buffer_get_width(buffer: *mut WpeBuffer) -> i32;
    fn wpe_buffer_get_height(buffer: *mut WpeBuffer) -> i32;
    fn wpe_buffer_take_rendering_fence(buffer: *mut WpeBuffer) -> i32;
    fn wpe_buffer_dma_buf_get_type() -> glib::ffi::GType;
    fn wpe_buffer_dma_buf_get_format(buffer: *mut WpeBufferDmaBuf) -> u32;
    fn wpe_buffer_dma_buf_get_n_planes(buffer: *mut WpeBufferDmaBuf) -> u32;
    fn wpe_buffer_dma_buf_get_fd(buffer: *mut WpeBufferDmaBuf, plane: u32) -> i32;
    fn wpe_buffer_dma_buf_get_offset(buffer: *mut WpeBufferDmaBuf, plane: u32) -> u32;
    fn wpe_buffer_dma_buf_get_stride(buffer: *mut WpeBufferDmaBuf, plane: u32) -> u32;
    fn wpe_buffer_dma_buf_get_modifier(buffer: *mut WpeBufferDmaBuf) -> u64;

    fn wpe_event_keyboard_new(
        event_type: i32,
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        keycode: u32,
        keyval: u32,
    ) -> *mut WpeEvent;
    fn wpe_event_pointer_button_new(
        event_type: i32,
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        button: u32,
        x: f64,
        y: f64,
        press_count: u32,
    ) -> *mut WpeEvent;
    fn wpe_event_pointer_move_new(
        event_type: i32,
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        x: f64,
        y: f64,
        delta_x: f64,
        delta_y: f64,
    ) -> *mut WpeEvent;
    fn wpe_event_scroll_new(
        view: *mut WpeView,
        source: i32,
        time: u32,
        modifiers: u32,
        delta_x: f64,
        delta_y: f64,
        precise: i32,
        is_stop: i32,
        x: f64,
        y: f64,
    ) -> *mut WpeEvent;
    fn wpe_event_unref(event: *mut WpeEvent);
}

static FRAME_GENERATION: AtomicU64 = AtomicU64::new(0);
static PAINT_COUNT: AtomicU64 = AtomicU64::new(0);
static VALID_PAINT_COUNT: AtomicU64 = AtomicU64::new(0);
static PLANE_COUNT: AtomicU32 = AtomicU32::new(0);
static FORMAT: AtomicU32 = AtomicU32::new(0);
static MODIFIER: AtomicU64 = AtomicU64::new(0);
static WIDTH_PX: AtomicU32 = AtomicU32::new(0);
static HEIGHT_PX: AtomicU32 = AtomicU32::new(0);
static FIRST_PLANE_STRIDE: AtomicU32 = AtomicU32::new(0);
static CONTEXT_MENU_GENERATION: AtomicU64 = AtomicU64::new(0);

struct WpeRuntime {
    webview: glib::Object,
    view: *mut WpeView,
    toplevel: *mut WpeToplevel,
}

struct ContextMenuSnapshot {
    x: f64,
    y: f64,
    items: Vec<ContextMenuItemSnapshot>,
}

struct ContextMenuItemSnapshot {
    title: Vec<u8>,
    is_separator: bool,
    action: *mut GAction,
    target: *mut GVariant,
}

impl Drop for ContextMenuItemSnapshot {
    fn drop(&mut self) {
        unsafe {
            if !self.action.is_null() {
                glib::gobject_ffi::g_object_unref(self.action.cast());
            }
            if !self.target.is_null() {
                g_variant_unref(self.target);
            }
        }
    }
}

thread_local! {
    static RUNTIME: RefCell<Option<WpeRuntime>> = const { RefCell::new(None) };
    static CONTEXT_MENU: RefCell<Option<ContextMenuSnapshot>> = const { RefCell::new(None) };
}

fn required_c_string(pointer: *const c_char) -> Result<String, i32> {
    if pointer.is_null() {
        return Err(-1);
    }
    // SAFETY: FFI callers must provide a NUL-terminated string for this call.
    unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| -2)
}

fn reset_metrics() {
    FRAME_GENERATION.store(0, Ordering::Release);
    PAINT_COUNT.store(0, Ordering::Release);
    VALID_PAINT_COUNT.store(0, Ordering::Release);
    PLANE_COUNT.store(0, Ordering::Release);
    FORMAT.store(0, Ordering::Release);
    MODIFIER.store(0, Ordering::Release);
    WIDTH_PX.store(0, Ordering::Release);
    HEIGHT_PX.store(0, Ordering::Release);
    FIRST_PLANE_STRIDE.store(0, Ordering::Release);
    CONTEXT_MENU_GENERATION.store(0, Ordering::Release);
    CONTEXT_MENU.with_borrow_mut(|menu| menu.take());
}

fn build_webview() -> Result<(glib::Object, *mut WpeView, *mut WpeToplevel), i32> {
    // SAFETY: WPE constructors return transfer-full GObject pointers.
    let display = unsafe { wpe_display_headless_new() };
    if display.is_null() {
        return Err(-3);
    }
    // SAFETY: Same transfer-full constructor contract as the display.
    let network_session = unsafe { webkit_network_session_new_ephemeral() };
    if network_session.is_null() {
        // SAFETY: display is a valid owned GObject pointer.
        unsafe { glib::gobject_ffi::g_object_unref(display.cast()) };
        return Err(-4);
    }

    // SAFETY: The variadic property list matches WebKitWebView's construct
    // properties and is terminated by a null property name.
    let object = unsafe {
        glib::gobject_ffi::g_object_new(
            webkit_web_view_get_type(),
            c"display".as_ptr(),
            display,
            c"network-session".as_ptr(),
            network_session,
            std::ptr::null::<c_char>(),
        )
    };
    if object.is_null() {
        // SAFETY: Both pointers remain owned because construction failed.
        unsafe {
            glib::gobject_ffi::g_object_unref(display.cast());
            glib::gobject_ffi::g_object_unref(network_session.cast());
        }
        return Err(-5);
    }
    // SAFETY: g_object_new returned a transfer-full GObject.
    let webview: glib::Object = unsafe { from_glib_full(object) };
    // WebView retained the construct-property objects; release constructor refs.
    unsafe {
        glib::gobject_ffi::g_object_unref(display.cast());
        glib::gobject_ffi::g_object_unref(network_session.cast());
    }

    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&webview).0
        as *mut WebKitWebView;
    // Explicitly preserve the normal browser media defaults. Audio is routed
    // by WebKit/GStreamer and does not pass through the texture transport.
    unsafe {
        webkit_web_view_set_is_muted(raw_webview, 0);
        let settings = webkit_web_view_get_settings(raw_webview);
        if !settings.is_null() {
            webkit_settings_set_enable_media(settings, 1);
            webkit_settings_set_enable_webaudio(settings, 1);
            webkit_settings_set_media_playback_requires_user_gesture(settings, 0);
        }
    }
    connect_context_menu(&webview);
    // SAFETY: raw_webview is borrowed from the owned WebView.
    if unsafe { webkit_web_view_get_display(raw_webview) } != display {
        return Err(-6);
    }
    // SAFETY: raw_webview remains alive through webview.
    let view = unsafe { webkit_web_view_get_wpe_view(raw_webview) };
    if view.is_null() {
        return Err(-7);
    }
    // SAFETY: view is a valid transfer-none WPEView pointer.
    let toplevel = unsafe { wpe_view_get_toplevel(view) };
    if toplevel.is_null() {
        return Err(-8);
    }
    connect_buffer_rendered(view);
    Ok((webview, view, toplevel))
}

fn connect_context_menu(webview: &glib::Object) {
    webview.connect_closure(
        "context-menu",
        false,
        glib::closure_local!(move |_webview: glib::Object,
                                   menu: glib::Object,
                                   _hit_test: glib::Object|
              -> bool {
            let raw_menu = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&menu).0
                as *mut WebKitContextMenu;
            let mut x = 0;
            let mut y = 0;
            unsafe { webkit_context_menu_get_position(raw_menu, &mut x, &mut y) };
            let item_count = unsafe { webkit_context_menu_get_n_items(raw_menu) };
            let mut items = Vec::with_capacity(item_count as usize);
            for index in 0..item_count {
                let item = unsafe { webkit_context_menu_get_item_at_position(raw_menu, index) };
                if item.is_null() {
                    continue;
                }
                let title = unsafe { webkit_context_menu_item_get_title(item) };
                let title = if title.is_null() {
                    Vec::new()
                } else {
                    unsafe { CStr::from_ptr(title) }.to_bytes().to_vec()
                };
                let action = unsafe { webkit_context_menu_item_get_gaction(item) };
                let action = if action.is_null() {
                    std::ptr::null_mut()
                } else {
                    unsafe { glib::gobject_ffi::g_object_ref(action.cast()) }.cast()
                };
                let target = unsafe { webkit_context_menu_item_get_gaction_target(item) };
                let target = if target.is_null() {
                    std::ptr::null_mut()
                } else {
                    unsafe { g_variant_ref(target) }
                };
                items.push(ContextMenuItemSnapshot {
                    title,
                    is_separator: unsafe { webkit_context_menu_item_is_separator(item) != 0 },
                    action,
                    target,
                });
            }
            CONTEXT_MENU_GENERATION.fetch_add(1, Ordering::AcqRel);
            CONTEXT_MENU.with_borrow_mut(|snapshot| {
                snapshot.replace(ContextMenuSnapshot {
                    x: f64::from(x),
                    y: f64::from(y),
                    items,
                });
            });
            true
        }),
    );
}

fn connect_buffer_rendered(view: *mut WpeView) {
    // SAFETY: view is a transfer-none GObject kept alive by the WebView.
    let view_object: glib::Object = unsafe { glib::translate::from_glib_none(view.cast()) };
    // SAFETY: The WPE type function returns a registered GType.
    let dma_buf_type = unsafe { glib::Type::from_glib(wpe_buffer_dma_buf_get_type()) };
    let raw_view = view as usize;
    view_object.connect_closure(
        "buffer-rendered",
        false,
        glib::closure_local!(move |_view: glib::Object, buffer: glib::Object| {
            let raw_buffer = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&buffer).0
                as *mut WpeBuffer;
            let view = raw_view as *mut WpeView;
            PAINT_COUNT.fetch_add(1, Ordering::AcqRel);
            if buffer.type_().is_a(dma_buf_type) {
                // The callback owns the buffer until it explicitly releases it.
                // Import and complete the GPU copy synchronously in that window.
                let status = unsafe { copy_rendered_dma_buf(raw_buffer) };
                if status == 0 {
                    VALID_PAINT_COUNT.fetch_add(1, Ordering::AcqRel);
                    crate::notify_flutter_texture_frame();
                }
            }
            // SAFETY: WPE emitted this buffer for this view; every callback path
            // releases it exactly once after any borrowed-fd work is complete.
            unsafe { wpe_view_buffer_released(view, raw_buffer) };
        }),
    );
}

unsafe fn copy_rendered_dma_buf(buffer: *mut WpeBuffer) -> i32 {
    let dma_buf = buffer.cast::<WpeBufferDmaBuf>();
    let width = unsafe { wpe_buffer_get_width(buffer) };
    let height = unsafe { wpe_buffer_get_height(buffer) };
    let plane_count = unsafe { wpe_buffer_dma_buf_get_n_planes(dma_buf) };
    if width <= 0 || height <= 0 || plane_count == 0 || plane_count as usize > MAX_PLANES {
        return -20;
    }

    let rendering_fence = unsafe { wpe_buffer_take_rendering_fence(buffer) };
    if rendering_fence >= 0 {
        // SAFETY: take_rendering_fence transfers ownership to the caller.
        let owned_fence = unsafe { OwnedFd::from_raw_fd(rendering_fence) };
        let mut poll_fd = libc::pollfd {
            fd: rendering_fence,
            events: libc::POLLIN,
            revents: 0,
        };
        // A sync_file becomes readable when the producer's rendering completes.
        let poll_status = unsafe { libc::poll(&mut poll_fd, 1, RENDER_FENCE_TIMEOUT_MS) };
        drop(owned_fence);
        if poll_status <= 0 {
            return -21;
        }
    }

    let generation = FRAME_GENERATION
        .fetch_add(1, Ordering::AcqRel)
        .wrapping_add(1)
        .max(1);
    let mut frame = crate::linux_texture::DmaBufFrame {
        generation,
        plane_count,
        fds: [-1; MAX_PLANES],
        strides: [0; MAX_PLANES],
        offsets: [0; MAX_PLANES],
        modifier: unsafe { wpe_buffer_dma_buf_get_modifier(dma_buf) },
        format: unsafe { wpe_buffer_dma_buf_get_format(dma_buf) },
        coded_width: width,
        coded_height: height,
        visible_x: 0,
        visible_y: 0,
        visible_width: width,
        visible_height: height,
    };
    for plane in 0..plane_count {
        let index = plane as usize;
        frame.fds[index] = unsafe { wpe_buffer_dma_buf_get_fd(dma_buf, plane) };
        frame.offsets[index] = u64::from(unsafe { wpe_buffer_dma_buf_get_offset(dma_buf, plane) });
        frame.strides[index] = unsafe { wpe_buffer_dma_buf_get_stride(dma_buf, plane) };
        if frame.fds[index] < 0 || frame.strides[index] == 0 {
            return -22;
        }
    }

    PLANE_COUNT.store(plane_count, Ordering::Release);
    FORMAT.store(frame.format, Ordering::Release);
    MODIFIER.store(frame.modifier, Ordering::Release);
    WIDTH_PX.store(width as u32, Ordering::Release);
    HEIGHT_PX.store(height as u32, Ordering::Release);
    FIRST_PLANE_STRIDE.store(frame.strides[0], Ordering::Release);

    let resize_status = crate::webview_flutter_linux_texture_resize(width as u32, height as u32);
    if resize_status != 0 {
        return resize_status;
    }
    crate::linux_texture::copy_dma_buf(&frame)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_initialize(initial_url: *const c_char) -> i32 {
    let initial_url = match required_c_string(initial_url) {
        Ok(value) => value,
        Err(status) => return status,
    };
    if RUNTIME.with_borrow(|runtime| runtime.is_some()) {
        return 1;
    }
    let (webview, view, toplevel) = match build_webview() {
        Ok(parts) => parts,
        Err(status) => return status,
    };
    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&webview).0
        as *mut WebKitWebView;
    let url = match std::ffi::CString::new(initial_url) {
        Ok(url) => url,
        Err(_) => return -2,
    };
    reset_metrics();
    // SAFETY: raw_webview is borrowed from webview; WebKit copies the URI.
    unsafe { webkit_web_view_load_uri(raw_webview, url.as_ptr()) };
    RUNTIME.with_borrow_mut(|runtime| {
        runtime.replace(WpeRuntime {
            webview,
            view,
            toplevel,
        });
    });
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_shutdown() -> i32 {
    CONTEXT_MENU.with_borrow_mut(|menu| menu.take());
    if RUNTIME.with_borrow_mut(Option::take).is_some() {
        0
    } else {
        1
    }
}

fn with_context_menu_item<T>(
    index: u32,
    fallback: T,
    operation: impl FnOnce(&ContextMenuItemSnapshot) -> T,
) -> T {
    CONTEXT_MENU.with_borrow(|snapshot| {
        let Some(snapshot) = snapshot.as_ref() else {
            return fallback;
        };
        snapshot
            .items
            .get(index as usize)
            .map_or(fallback, operation)
    })
}

fn with_clipboard<T>(fallback: T, operation: impl FnOnce(*mut WpeClipboard) -> T) -> T {
    RUNTIME.with_borrow(|runtime| {
        let Some(runtime) = runtime.as_ref() else {
            return fallback;
        };
        let raw_webview =
            ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
                as *mut WebKitWebView;
        let display = unsafe { webkit_web_view_get_display(raw_webview) };
        if display.is_null() {
            return fallback;
        }
        let clipboard = unsafe { wpe_display_get_clipboard(display) };
        if clipboard.is_null() {
            fallback
        } else {
            operation(clipboard)
        }
    })
}

const UTF8_TEXT_FORMAT: &[u8] = b"text/plain;charset=utf-8\0";

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_clipboard_change_count() -> i64 {
    with_clipboard(-1, |clipboard| unsafe {
        wpe_clipboard_get_change_count(clipboard)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_clipboard_text_length() -> isize {
    with_clipboard(-1, |clipboard| {
        let mut length = 0;
        let text = unsafe {
            wpe_clipboard_read_text(clipboard, UTF8_TEXT_FORMAT.as_ptr().cast(), &mut length)
        };
        if text.is_null() {
            -1
        } else {
            unsafe { glib::ffi::g_free(text.cast()) };
            length.min(isize::MAX as usize) as isize
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn webview_flutter_linux_wpe_clipboard_copy_text(
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_clipboard(-2, |clipboard| {
        let mut length = 0;
        let text = unsafe {
            wpe_clipboard_read_text(clipboard, UTF8_TEXT_FORMAT.as_ptr().cast(), &mut length)
        };
        if text.is_null() {
            return -4;
        }
        if destination_length < length || length > i32::MAX as usize {
            unsafe { glib::ffi::g_free(text.cast()) };
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(text.cast(), destination, length);
            glib::ffi::g_free(text.cast());
        }
        length as i32
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn webview_flutter_linux_wpe_clipboard_set_text(text: *const c_char) -> i32 {
    if text.is_null() || unsafe { CStr::from_ptr(text) }.to_str().is_err() {
        return -1;
    }
    with_clipboard(-2, |clipboard| {
        let content = unsafe { wpe_clipboard_content_new() };
        if content.is_null() {
            return -3;
        }
        unsafe {
            wpe_clipboard_content_set_text(content, text);
            wpe_clipboard_set_content(clipboard, content);
            wpe_clipboard_content_unref(content);
        }
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_generation() -> u64 {
    CONTEXT_MENU_GENERATION.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_x() -> f64 {
    CONTEXT_MENU.with_borrow(|menu| menu.as_ref().map_or(0.0, |menu| menu.x))
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_y() -> f64 {
    CONTEXT_MENU.with_borrow(|menu| menu.as_ref().map_or(0.0, |menu| menu.y))
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_count() -> u32 {
    CONTEXT_MENU.with_borrow(|snapshot| {
        snapshot
            .as_ref()
            .map_or(0, |snapshot| snapshot.items.len() as u32)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_title_length(index: u32) -> usize {
    with_context_menu_item(index, 0, |item| item.title.len())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn webview_flutter_linux_wpe_context_menu_item_copy_title(
    index: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_context_menu_item(index, -2, |item| {
        if destination_length < item.title.len() {
            return -3;
        }
        unsafe {
            std::ptr::copy_nonoverlapping(item.title.as_ptr(), destination, item.title.len())
        };
        item.title.len().min(i32::MAX as usize) as i32
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_is_separator(index: u32) -> i32 {
    with_context_menu_item(index, 0, |item| i32::from(item.is_separator))
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_is_enabled(index: u32) -> i32 {
    with_context_menu_item(index, 0, |item| {
        if item.action.is_null() {
            0
        } else {
            unsafe { i32::from(g_action_get_enabled(item.action) != 0) }
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_activate(index: u32) -> i32 {
    let status = with_context_menu_item(index, -2, |item| {
        if item.action.is_null() || unsafe { g_action_get_enabled(item.action) } == 0 {
            return -3;
        }
        unsafe { g_action_activate(item.action, item.target) };
        0
    });
    if status == 0 {
        CONTEXT_MENU.with_borrow_mut(|menu| menu.take());
    }
    status
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_context_menu_dismiss() -> i32 {
    i32::from(CONTEXT_MENU.with_borrow_mut(|menu| menu.take()).is_none())
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_pump() -> i32 {
    if !RUNTIME.with_borrow(|runtime| runtime.is_some()) {
        return -1;
    }
    let context = MainContext::default();
    for _ in 0..8 {
        if !context.pending() {
            break;
        }
        context.iteration(false);
    }
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_navigate(url: *const c_char) -> i32 {
    let url =
        match required_c_string(url).and_then(|url| std::ffi::CString::new(url).map_err(|_| -2)) {
            Ok(url) => url,
            Err(status) => return status,
        };
    RUNTIME.with_borrow(|runtime| {
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
            as *mut WebKitWebView;
        // SAFETY: webview is borrowed from the live runtime; WebKit copies URI.
        unsafe { webkit_web_view_load_uri(webview, url.as_ptr()) };
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_resize(width: u32, height: u32) -> i32 {
    if width == 0 || height == 0 || width > 16_384 || height > 16_384 {
        return -1;
    }
    RUNTIME.with_borrow(|runtime| {
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        // SAFETY: Both pointers are transfer-none children of the live WebView.
        let resized = unsafe { wpe_toplevel_resize(runtime.toplevel, width as i32, height as i32) };
        if resized == 0 {
            return -4;
        }
        unsafe { wpe_view_resized(runtime.view, width as i32, height as i32) };
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_set_focus(focused: i32) -> i32 {
    with_view(|view| unsafe {
        if focused != 0 {
            wpe_view_focus_in(view);
        } else {
            wpe_view_focus_out(view);
        }
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_set_visibility(visible: i32) -> i32 {
    with_view(|view| unsafe { wpe_view_set_visible(view, i32::from(visible != 0)) })
}

fn wpe_modifiers(modifiers: u32) -> u32 {
    let mut result = 0;
    if modifiers & (1 << 2) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_CONTROL;
    }
    if modifiers & (1 << 1) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_SHIFT;
    }
    if modifiers & (1 << 3) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_ALT;
    }
    if modifiers & (1 << 7) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_META;
    }
    if modifiers & (1 << 0) != 0 {
        result |= WPE_MODIFIER_KEYBOARD_CAPS_LOCK;
    }
    if modifiers & (1 << 4) != 0 {
        result |= WPE_MODIFIER_POINTER_BUTTON1;
    }
    if modifiers & (1 << 5) != 0 {
        result |= WPE_MODIFIER_POINTER_BUTTON2;
    }
    if modifiers & (1 << 6) != 0 {
        result |= WPE_MODIFIER_POINTER_BUTTON3;
    }
    result
}

fn xkb_keycode_from_usb_hid(native_key_code: i32) -> u32 {
    let usage = native_key_code as u32;
    if usage >> 16 != 0x07 {
        return 0;
    }
    match usage & 0xffff {
        0x04 => 0x26,                                  // KeyA
        0x05 => 0x38,                                  // KeyB
        0x06 => 0x36,                                  // KeyC
        0x07 => 0x28,                                  // KeyD
        0x08 => 0x1a,                                  // KeyE
        0x09 => 0x29,                                  // KeyF
        0x0a => 0x2a,                                  // KeyG
        0x0b => 0x2b,                                  // KeyH
        0x0c => 0x1f,                                  // KeyI
        0x0d => 0x2c,                                  // KeyJ
        0x0e => 0x2d,                                  // KeyK
        0x0f => 0x2e,                                  // KeyL
        0x10 => 0x3a,                                  // KeyM
        0x11 => 0x39,                                  // KeyN
        0x12 => 0x20,                                  // KeyO
        0x13 => 0x21,                                  // KeyP
        0x14 => 0x18,                                  // KeyQ
        0x15 => 0x1b,                                  // KeyR
        0x16 => 0x27,                                  // KeyS
        0x17 => 0x1c,                                  // KeyT
        0x18 => 0x1e,                                  // KeyU
        0x19 => 0x37,                                  // KeyV
        0x1a => 0x19,                                  // KeyW
        0x1b => 0x35,                                  // KeyX
        0x1c => 0x1d,                                  // KeyY
        0x1d => 0x34,                                  // KeyZ
        0x1e..=0x26 => 0x0a + (usage & 0xffff) - 0x1e, // Digit1..9
        0x27 => 0x13,                                  // Digit0
        0x28 => 0x24,                                  // Enter
        0x29 => 0x09,                                  // Escape
        0x2a => 0x16,                                  // Backspace
        0x2b => 0x17,                                  // Tab
        0x2c => 0x41,                                  // Space
        0x2d => 0x14,                                  // Minus
        0x2e => 0x15,                                  // Equal
        0x2f => 0x22,                                  // BracketLeft
        0x30 => 0x23,                                  // BracketRight
        0x31 => 0x33,                                  // Backslash
        0x32 => 0x5e,                                  // IntlBackslash
        0x33 => 0x2f,                                  // Semicolon
        0x34 => 0x30,                                  // Quote
        0x35 => 0x31,                                  // Backquote
        0x36 => 0x3b,                                  // Comma
        0x37 => 0x3c,                                  // Period
        0x38 => 0x3d,                                  // Slash
        0x39 => 0x42,                                  // CapsLock
        0x3a..=0x43 => 0x43 + (usage & 0xffff) - 0x3a, // F1..F10
        0x44 => 0x5f,                                  // F11
        0x45 => 0x60,                                  // F12
        0x46 => 0x6b,                                  // PrintScreen
        0x47 => 0x4e,                                  // ScrollLock
        0x48 => 0x7f,                                  // Pause
        0x49 => 0x76,                                  // Insert
        0x4a => 0x6e,                                  // Home
        0x4b => 0x70,                                  // PageUp
        0x4c => 0x77,                                  // Delete
        0x4d => 0x73,                                  // End
        0x4e => 0x75,                                  // PageDown
        0x4f => 0x72,                                  // ArrowRight
        0x50 => 0x71,                                  // ArrowLeft
        0x51 => 0x74,                                  // ArrowDown
        0x52 => 0x6f,                                  // ArrowUp
        0x53 => 0x4d,                                  // NumLock
        0x54 => 0x6a,                                  // NumpadDivide
        0x55 => 0x3f,                                  // NumpadMultiply
        0x56 => 0x52,                                  // NumpadSubtract
        0x57 => 0x56,                                  // NumpadAdd
        0x58 => 0x68,                                  // NumpadEnter
        0x59 => 0x57,                                  // Numpad1
        0x5a => 0x58,                                  // Numpad2
        0x5b => 0x59,                                  // Numpad3
        0x5c => 0x53,                                  // Numpad4
        0x5d => 0x54,                                  // Numpad5
        0x5e => 0x55,                                  // Numpad6
        0x5f => 0x4f,                                  // Numpad7
        0x60 => 0x50,                                  // Numpad8
        0x61 => 0x51,                                  // Numpad9
        0x62 => 0x5a,                                  // Numpad0
        0x63 => 0x5b,                                  // NumpadDecimal
        0x64 => 0x5e,                                  // IntlBackslash
        0x65 => 0x87,                                  // ContextMenu
        0x67 => 0x7d,                                  // NumpadEqual
        0xe0 => 0x25,                                  // ControlLeft
        0xe1 => 0x32,                                  // ShiftLeft
        0xe2 => 0x40,                                  // AltLeft
        0xe3 => 0x85,                                  // MetaLeft
        0xe4 => 0x69,                                  // ControlRight
        0xe5 => 0x3e,                                  // ShiftRight
        0xe6 => 0x6c,                                  // AltRight
        0xe7 => 0x86,                                  // MetaRight
        _ => 0,
    }
}

fn unicode_to_xkb_keyval(character: u32) -> u32 {
    match character {
        0 => 0,
        1..=0xff => character,
        0x100..=0x10ffff => 0x0100_0000 | character,
        _ => 0,
    }
}

fn xkb_keyval(windows_key_code: i32, native_key_code: i32, character: u32) -> u32 {
    let character_keyval = unicode_to_xkb_keyval(character);
    if character_keyval != 0 {
        return character_keyval;
    }
    if (0x41..=0x5a).contains(&windows_key_code) {
        return windows_key_code as u32 + 0x20;
    }
    if (0x30..=0x39).contains(&windows_key_code) {
        return windows_key_code as u32;
    }
    match windows_key_code {
        0x08 => 0xff08, // Backspace
        0x09 => 0xff09, // Tab
        0x0d => 0xff0d, // Return
        0x10 => match native_key_code as u32 & 0xffff {
            0xe5 => 0xffe2,
            _ => 0xffe1,
        },
        0x11 => match native_key_code as u32 & 0xffff {
            0xe4 => 0xffe4,
            _ => 0xffe3,
        },
        0x12 => match native_key_code as u32 & 0xffff {
            0xe6 => 0xffea,
            _ => 0xffe9,
        },
        0x14 => 0xffe5,                                         // CapsLock
        0x1b => 0xff1b,                                         // Escape
        0x20 => 0x20,                                           // Space
        0x21 => 0xff55,                                         // PageUp
        0x22 => 0xff56,                                         // PageDown
        0x23 => 0xff57,                                         // End
        0x24 => 0xff50,                                         // Home
        0x25 => 0xff51,                                         // ArrowLeft
        0x26 => 0xff52,                                         // ArrowUp
        0x27 => 0xff53,                                         // ArrowRight
        0x28 => 0xff54,                                         // ArrowDown
        0x2d => 0xff63,                                         // Insert
        0x2e => 0xffff,                                         // Delete
        0x5b => 0xffeb,                                         // MetaLeft / SuperLeft
        0x5c => 0xffec,                                         // MetaRight / SuperRight
        0x70..=0x7b => 0xffbe + windows_key_code as u32 - 0x70, // F1..F12
        0x90 => 0xff7f,                                         // NumLock
        0x91 => 0xff14,                                         // ScrollLock
        _ => 0,
    }
}

fn with_view(operation: impl FnOnce(*mut WpeView)) -> i32 {
    RUNTIME.with_borrow(|runtime| {
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        operation(runtime.view);
        0
    })
}

unsafe fn dispatch_event(view: *mut WpeView, event: *mut WpeEvent) {
    if event.is_null() {
        return;
    }
    unsafe {
        wpe_view_event(view, event);
        wpe_event_unref(event);
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_move(
    x: i32,
    y: i32,
    modifiers: u32,
    mouse_leave: i32,
) -> i32 {
    if mouse_leave != 0 {
        return 0;
    }
    with_view(|view| {
        // SAFETY: event is created for this live view and consumed by event().
        let event = unsafe {
            wpe_event_pointer_move_new(
                WPE_EVENT_POINTER_MOVE,
                view,
                WPE_INPUT_SOURCE_MOUSE,
                0,
                wpe_modifiers(modifiers),
                x as f64,
                y as f64,
                0.0,
                0.0,
            )
        };
        unsafe { dispatch_event(view, event) };
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_button(
    x: i32,
    y: i32,
    modifiers: u32,
    button: u32,
    mouse_up: i32,
    click_count: i32,
) -> i32 {
    if button > 2 || !(1..=3).contains(&click_count) {
        return -1;
    }
    with_view(|view| {
        let event_type = if mouse_up != 0 {
            WPE_EVENT_POINTER_UP
        } else {
            WPE_EVENT_POINTER_DOWN
        };
        let event = unsafe {
            wpe_event_pointer_button_new(
                event_type,
                view,
                WPE_INPUT_SOURCE_MOUSE,
                0,
                wpe_modifiers(modifiers),
                button + 1,
                x as f64,
                y as f64,
                if mouse_up != 0 { 0 } else { click_count as u32 },
            )
        };
        unsafe { dispatch_event(view, event) };
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_wheel(
    x: i32,
    y: i32,
    modifiers: u32,
    delta_x: i32,
    delta_y: i32,
) -> i32 {
    with_view(|view| {
        let event = unsafe {
            wpe_event_scroll_new(
                view,
                WPE_INPUT_SOURCE_MOUSE,
                0,
                wpe_modifiers(modifiers),
                delta_x as f64,
                delta_y as f64,
                1,
                0,
                x as f64,
                y as f64,
            )
        };
        unsafe { dispatch_event(view, event) };
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_send_key(
    event_type: u32,
    modifiers: u32,
    windows_key_code: i32,
    native_key_code: i32,
    character: u32,
    _unmodified_character: u32,
) -> i32 {
    let event_type = match event_type {
        0 | 1 | 3 => WPE_EVENT_KEYBOARD_KEY_DOWN,
        2 => WPE_EVENT_KEYBOARD_KEY_UP,
        _ => return -1,
    };
    with_view(|view| {
        let event = unsafe {
            wpe_event_keyboard_new(
                event_type,
                view,
                WPE_INPUT_SOURCE_KEYBOARD,
                0,
                wpe_modifiers(modifiers),
                xkb_keycode_from_usb_hid(native_key_code),
                xkb_keyval(windows_key_code, native_key_code, character),
            )
        };
        unsafe { dispatch_event(view, event) };
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_frame_generation() -> u64 {
    FRAME_GENERATION.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_paint_count() -> u64 {
    PAINT_COUNT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_valid_paint_count() -> u64 {
    VALID_PAINT_COUNT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_plane_count() -> u32 {
    PLANE_COUNT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_format() -> u32 {
    FORMAT.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_modifier() -> u64 {
    MODIFIER.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_width() -> u32 {
    WIDTH_PX.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_height() -> u32 {
    HEIGHT_PX.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn webview_flutter_linux_wpe_first_plane_stride() -> u32 {
    FIRST_PLANE_STRIDE.load(Ordering::Acquire)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn translates_flutter_usb_hid_to_webkit_xkb_keycode() {
        assert_eq!(xkb_keycode_from_usb_hid(0x0007_0004), 0x26);
        assert_eq!(xkb_keycode_from_usb_hid(0x0007_0028), 0x24);
    }

    #[test]
    fn translates_ctrl_a_logical_key_without_text() {
        assert_eq!(xkb_keyval(0x41, 0x0007_0004, 0), u32::from(b'a'));
    }

    #[test]
    fn encodes_non_latin_unicode_keyvals() {
        assert_eq!(unicode_to_xkb_keyval(0x1f642), 0x0101_f642);
    }
}
