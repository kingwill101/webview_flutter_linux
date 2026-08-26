// Copyright 2026 The webview_flutter_linux authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

//! WPE WebKit runtime and C ABI for individual Linux WebViews.
//!
//! Each successful [`webview_flutter_linux_view_create`] call inserts one
//! [`NativeView`] into the platform thread's `VIEWS` registry and returns a
//! monotonically increasing, non-zero handle. Every later FFI function resolves
//! that handle rather than dereferencing a Dart-owned pointer. Disposing a view
//! removes it from the registry first, making stale or repeated calls fail
//! without accessing released browser state.
//!
//! ## Thread affinity and callbacks
//!
//! GLib, WebKit, and WPE objects are not `Send`. The registry is therefore
//! thread-local and all Dart calls must originate from Flutter's Linux platform
//! thread. Signal closures capture `Weak<NativeView>` references: they cannot
//! keep a disposed browser alive, and they can detect teardown before touching
//! texture or menu state. Only [`crate::linux_texture::TextureState`] crosses
//! to Flutter's raster thread through `Arc`, atomics, and mutexes.
//!
//! ## Buffer lifetime
//!
//! WPE owns every `WpeBuffer` and its DMA-BUF file descriptors. During
//! `buffer-rendered`, this module waits for WPE's rendering fence, synchronously
//! copies the borrowed planes into an application-owned GL ring, then calls
//! `wpe_view_buffer_released` exactly once. No buffer pointer or borrowed file
//! descriptor is retained after the callback.
//!
//! ## Return values
//!
//! Commands return `0` on success. Negative values identify invalid arguments,
//! invalid handles, unavailable native objects, or lower-level WPE/texture
//! failures. Accessors return zero (or `-1` where negative is representable)
//! when a handle or requested value is unavailable. The Dart wrapper converts
//! command failures into `StateError`s.

use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::{CStr, c_char},
    os::fd::{FromRawFd, OwnedFd},
    rc::{Rc, Weak},
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

// Opaque declarations for the WPE/WebKit/GIO types used by the hand-written
// ABI. Rust never constructs or dereferences these zero-sized marker types; it
// only passes pointers back to the library that created them. Ownership and
// transfer annotations for individual calls are recorded at their call sites.
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
    // Constructors returning transfer-full GObjects are wrapped immediately in
    // glib ownership or explicitly unref'd on failure. All `get_*` functions
    // below return transfer-none pointers tied to their parent object.
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

/// Strong owner for the WebKit object and its transfer-none WPE children.
///
/// `webview` keeps `view` and `toplevel` alive. The raw child pointers must
/// never be used after the owning `glib::Object` is dropped.
struct WpeRuntime {
    webview: glib::Object,
    view: *mut WpeView,
    toplevel: *mut WpeToplevel,
}

#[derive(Default)]
/// Per-view counters and latest-frame metadata exposed by diagnostic accessors.
///
/// Atomics let callbacks publish scalar state without retaining a borrow of the
/// thread-local handle registry across a WPE or texture operation.
struct WpeMetrics {
    frame_generation: AtomicU64,
    paint_count: AtomicU64,
    valid_paint_count: AtomicU64,
    plane_count: AtomicU32,
    format: AtomicU32,
    modifier: AtomicU64,
    width: AtomicU32,
    height: AtomicU32,
    first_plane_stride: AtomicU32,
    context_menu_generation: AtomicU64,
}

/// Ownership root for one public native handle.
///
/// Browser/menu state uses `RefCell` because it remains platform-thread local.
/// Texture state uses `Arc` because Irondash also retains it for raster-thread
/// callbacks. The registry and signal closures share this object via `Rc` and
/// `Weak`; the browser object itself never crosses threads.
struct NativeView {
    runtime: RefCell<Option<WpeRuntime>>,
    context_menu: RefCell<Option<ContextMenuSnapshot>>,
    metrics: WpeMetrics,
    texture: std::sync::Arc<crate::linux_texture::TextureState>,
}

/// Flutter-readable copy of the current WebKit context menu.
///
/// Coordinates are physical WPE pixels; Dart converts them back to logical
/// Flutter coordinates using the current device scale factor.
struct ContextMenuSnapshot {
    x: f64,
    y: f64,
    items: Vec<ContextMenuItemSnapshot>,
}

/// One retained context-menu action.
///
/// The title is copied immediately. `action` and optional `target` receive
/// native references so Flutter may activate them after WebKit's signal ends.
struct ContextMenuItemSnapshot {
    title: Vec<u8>,
    is_separator: bool,
    action: *mut GAction,
    target: *mut GVariant,
}

impl Drop for ContextMenuItemSnapshot {
    fn drop(&mut self) {
        // Balance the native references acquired while snapshotting the menu.
        // Separators and targetless actions legitimately store null pointers.
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
    // WPE/GLib objects may only be accessed on their creation thread. Calls
    // from another thread see a distinct empty registry instead of unsafely
    // treating NativeView as Send.
    static VIEWS: RefCell<HashMap<u64, Rc<NativeView>>> = RefCell::new(HashMap::new());
    // Handles are identifiers, not pointers. Zero is permanently reserved for
    // “no view” and is also the fallback returned by read-only accessors.
    static NEXT_HANDLE: RefCell<u64> = const { RefCell::new(1) };
}

/// Resolves a public handle and clones its platform-thread `Rc`.
///
/// The registry borrow ends before the returned object is used, which permits
/// GLib signal re-entrancy without a nested `RefCell` borrow of `VIEWS`.
fn native_view(handle: u64) -> Option<Rc<NativeView>> {
    if handle == 0 {
        return None;
    }
    VIEWS.with_borrow(|views| views.get(&handle).cloned())
}

/// Allocates the next non-zero process-local handle.
///
/// Wrapping is handled defensively. Exhausting the complete `u64` space in one
/// process is not realistic, and zero remains reserved after wraparound.
fn next_handle() -> u64 {
    NEXT_HANDLE.with_borrow_mut(|next| {
        let handle = (*next).max(1);
        *next = handle.wrapping_add(1).max(1);
        handle
    })
}

/// Copies a caller-owned NUL-terminated UTF-8 string into Rust storage.
///
/// The returned `String` does not borrow the FFI pointer. `-1` denotes null and
/// `-2` invalid UTF-8.
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

/// Constructs a headless WPE display, ephemeral network session, and WebView.
///
/// The returned `glib::Object` is the sole strong browser owner. `WpeView` and
/// `WpeToplevel` are transfer-none children. Signal handlers receive only a
/// weak reference to the surrounding [`NativeView`] so they stop operating as
/// soon as the public handle is disposed.
fn build_webview(
    native_view: Weak<NativeView>,
) -> Result<(glib::Object, *mut WpeView, *mut WpeToplevel), i32> {
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
    connect_context_menu(&webview, native_view.clone());
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
    connect_buffer_rendered(view, native_view);
    Ok((webview, view, toplevel))
}

/// Replaces WebKit's native menu with a retained snapshot consumed by Flutter.
///
/// Returning `true` suppresses the WPE-native presentation. Menu action and
/// target references are retained until Flutter activates/dismisses the menu or
/// the view is disposed.
fn connect_context_menu(webview: &glib::Object, native_view: Weak<NativeView>) {
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
            let Some(native_view) = native_view.upgrade() else {
                return true;
            };
            native_view
                .metrics
                .context_menu_generation
                .fetch_add(1, Ordering::AcqRel);
            native_view.context_menu.replace(Some(ContextMenuSnapshot {
                x: f64::from(x),
                y: f64::from(y),
                items,
            }));
            true
        }),
    );
}

/// Connects WPE's `buffer-rendered` signal to the per-view texture transport.
///
/// Every callback releases the WPE buffer exactly once, including callbacks
/// that race with view disposal or receive unsupported buffer types. Supported
/// DMA-BUFs are copied synchronously before release.
fn connect_buffer_rendered(view: *mut WpeView, native_view: Weak<NativeView>) {
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
            let Some(native_view) = native_view.upgrade() else {
                unsafe { wpe_view_buffer_released(view, raw_buffer) };
                return;
            };
            native_view
                .metrics
                .paint_count
                .fetch_add(1, Ordering::AcqRel);
            if buffer.type_().is_a(dma_buf_type) {
                // The callback owns the buffer until it explicitly releases it.
                // Import and complete the GPU copy synchronously in that window.
                let status = unsafe { copy_rendered_dma_buf(&native_view, raw_buffer) };
                if status == 0 {
                    native_view
                        .metrics
                        .valid_paint_count
                        .fetch_add(1, Ordering::AcqRel);
                    native_view.texture.mark_frame_available();
                }
            }
            // SAFETY: WPE emitted this buffer for this view; every callback path
            // releases it exactly once after any borrowed-fd work is complete.
            unsafe { wpe_view_buffer_released(view, raw_buffer) };
        }),
    );
}

/// Converts one callback-scoped WPE DMA-BUF into
/// [`DmaBufFrame`](crate::linux_texture::DmaBufFrame) metadata and forwards it
/// to the owning texture state.
///
/// The rendering fence is consumed and waited for before plane metadata is
/// read. This prevents EGL from importing producer-incomplete content.
///
/// # Safety
///
/// `buffer` must be a live `WpeBufferDmaBuf` emitted for `native_view` and must
/// remain owned by WPE for this call. The caller is responsible for invoking
/// `wpe_view_buffer_released` after this function returns.
unsafe fn copy_rendered_dma_buf(native_view: &NativeView, buffer: *mut WpeBuffer) -> i32 {
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

    let generation = native_view
        .metrics
        .frame_generation
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

    native_view
        .metrics
        .plane_count
        .store(plane_count, Ordering::Release);
    native_view
        .metrics
        .format
        .store(frame.format, Ordering::Release);
    native_view
        .metrics
        .modifier
        .store(frame.modifier, Ordering::Release);
    native_view
        .metrics
        .width
        .store(width as u32, Ordering::Release);
    native_view
        .metrics
        .height
        .store(height as u32, Ordering::Release);
    native_view
        .metrics
        .first_plane_stride
        .store(frame.strides[0], Ordering::Release);

    let resize_status = native_view.texture.resize(width as u32, height as u32);
    if resize_status != 0 {
        return resize_status;
    }
    native_view.texture.copy_dma_buf(&frame)
}

#[unsafe(no_mangle)]
/// Creates one independently owned browser and Flutter texture.
///
/// Creation is transactional: the handle is inserted only after texture
/// registration, WPE construction, signal connection, and initial navigation
/// all succeed. On success `output_handle` receives a non-zero identifier and
/// the function returns `0`. Negative values report invalid pointers/strings or
/// the propagated texture/WPE construction failure.
///
/// # Safety
///
/// `initial_url` must point to a readable NUL-terminated byte sequence for the
/// duration of this call. `output_handle` must point to writable, properly
/// aligned storage for one `u64`. The call must run on Flutter's Linux platform
/// thread and `engine_handle` must identify the live engine supplied by
/// Irondash.
pub unsafe extern "C" fn webview_flutter_linux_view_create(
    engine_handle: i64,
    initial_url: *const c_char,
    output_handle: *mut u64,
) -> i32 {
    if output_handle.is_null() {
        return -1;
    }
    let initial_url = match required_c_string(initial_url) {
        Ok(value) => value,
        Err(status) => return status,
    };
    let texture = match crate::linux_texture::TextureState::new(engine_handle) {
        Ok(texture) => texture,
        Err(status) => return status,
    };
    let native_view = Rc::new(NativeView {
        runtime: RefCell::new(None),
        context_menu: RefCell::new(None),
        metrics: WpeMetrics::default(),
        texture,
    });
    let (webview, view, toplevel) = match build_webview(Rc::downgrade(&native_view)) {
        Ok(parts) => parts,
        Err(status) => return status,
    };
    let raw_webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&webview).0
        as *mut WebKitWebView;
    let url = match std::ffi::CString::new(initial_url) {
        Ok(url) => url,
        Err(_) => return -2,
    };
    // SAFETY: raw_webview is borrowed from webview; WebKit copies the URI.
    unsafe { webkit_web_view_load_uri(raw_webview, url.as_ptr()) };
    native_view.runtime.replace(Some(WpeRuntime {
        webview,
        view,
        toplevel,
    }));
    let handle = next_handle();
    VIEWS.with_borrow_mut(|views| {
        views.insert(handle, native_view);
    });
    unsafe { output_handle.write(handle) };
    0
}

#[unsafe(no_mangle)]
/// Removes a handle from the registry and tears down its browser and texture.
///
/// Registry removal happens first so re-entrant or repeated calls cannot find
/// partially destroyed state. WPE/menu objects are dropped before the texture
/// is unregistered. Returns `-1` for zero, unknown, or already disposed handles.
pub extern "C" fn webview_flutter_linux_view_dispose(handle: u64) -> i32 {
    let native_view = VIEWS.with_borrow_mut(|views| views.remove(&handle));
    let Some(native_view) = native_view else {
        return -1;
    };
    native_view.context_menu.take();
    native_view.runtime.take();
    native_view.texture.shutdown()
}

#[unsafe(no_mangle)]
/// Returns the Flutter texture ID for `handle`, or zero if it is invalid.
pub extern "C" fn webview_flutter_linux_texture_id(handle: u64) -> i64 {
    native_view(handle).map_or(0, |view| view.texture.id())
}

#[unsafe(no_mangle)]
/// Returns the current physical texture width, or zero for an invalid handle.
pub extern "C" fn webview_flutter_linux_texture_width(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.texture.width())
}

#[unsafe(no_mangle)]
/// Returns the current physical texture height, or zero for an invalid handle.
pub extern "C" fn webview_flutter_linux_texture_height(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.texture.height())
}

#[unsafe(no_mangle)]
/// Returns the generation incremented after each effective texture resize.
pub extern "C" fn webview_flutter_linux_texture_generation(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| view.texture.generation())
}

#[unsafe(no_mangle)]
/// Marks this handle's Irondash texture as having a new frame.
///
/// Returns `-1` for an invalid/disposed handle or texture, and `-2` for a
/// poisoned texture lock.
pub extern "C" fn webview_flutter_linux_texture_request_frame(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| view.texture.mark_frame_available())
}

#[unsafe(no_mangle)]
/// Returns the number of successful DMA-BUF-to-GL copies for this view.
pub extern "C" fn webview_flutter_linux_texture_dma_buf_copy_count(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| view.texture.dma_buf_copy_count())
}

/// Resolves one retained menu item while keeping fallback behavior uniform for
/// invalid handles, absent menus, and out-of-range indices.
fn with_context_menu_item<T: Copy>(
    handle: u64,
    index: u32,
    fallback: T,
    operation: impl FnOnce(&ContextMenuItemSnapshot) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    native_view
        .context_menu
        .borrow()
        .as_ref()
        .map_or(fallback, |snapshot| {
            snapshot
                .items
                .get(index as usize)
                .map_or(fallback, operation)
        })
}

/// Resolves the clipboard belonging to a handle's WPE display.
///
/// WPE clipboard objects are transfer-none. `operation` must not retain the
/// pointer beyond the closure call.
fn with_clipboard<T>(
    handle: u64,
    fallback: T,
    operation: impl FnOnce(*mut WpeClipboard) -> T,
) -> T {
    let Some(native_view) = native_view(handle) else {
        return fallback;
    };
    {
        let runtime = native_view.runtime.borrow();
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
    }
}

const UTF8_TEXT_FORMAT: &[u8] = b"text/plain;charset=utf-8\0";

#[unsafe(no_mangle)]
/// Returns WPE's monotonically increasing clipboard change count.
///
/// Dart compares this value with the last observed count to avoid repeatedly
/// copying unchanged browser clipboard text. Returns `-1` when unavailable.
pub extern "C" fn webview_flutter_linux_wpe_clipboard_change_count(handle: u64) -> i64 {
    with_clipboard(handle, -1, |clipboard| unsafe {
        wpe_clipboard_get_change_count(clipboard)
    })
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 byte length of the current plain-text clipboard value.
///
/// WPE allocates a temporary read buffer; this function frees it after reading
/// the length. Dart uses the result to allocate the exact destination buffer.
pub extern "C" fn webview_flutter_linux_wpe_clipboard_text_length(handle: u64) -> isize {
    with_clipboard(handle, -1, |clipboard| {
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
/// Copies the current plain-text clipboard value into caller-owned storage.
///
/// Returns the number of bytes copied. `-1` denotes a null destination, `-2`
/// an unavailable view/clipboard, `-3` insufficient destination capacity, and
/// `-4` a failed WPE text read.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes. It may not
/// alias memory managed by WPE. The pointer is used only during this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_clipboard_copy_text(
    handle: u64,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_clipboard(handle, -2, |clipboard| {
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
/// Replaces the browser clipboard with caller-provided UTF-8 plain text.
///
/// WPE copies the string into a new `WpeClipboardContent`; the caller retains
/// ownership of `text`. Returns `-1` for null/invalid UTF-8, `-2` when the
/// clipboard is unavailable, and `-3` if content allocation fails.
///
/// # Safety
///
/// `text` must point to a readable NUL-terminated byte sequence for the
/// duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_clipboard_set_text(
    handle: u64,
    text: *const c_char,
) -> i32 {
    if text.is_null() || unsafe { CStr::from_ptr(text) }.to_str().is_err() {
        return -1;
    }
    with_clipboard(handle, -2, |clipboard| {
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
/// Returns the generation of the latest Flutter-owned context-menu snapshot.
///
/// Zero means no context menu has ever been captured for this handle.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_generation(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.metrics.context_menu_generation.load(Ordering::Acquire)
    })
}

#[unsafe(no_mangle)]
/// Returns the context-menu X position in physical WPE pixels.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_x(handle: u64) -> f64 {
    native_view(handle).map_or(0.0, |view| {
        view.context_menu
            .borrow()
            .as_ref()
            .map_or(0.0, |menu| menu.x)
    })
}

#[unsafe(no_mangle)]
/// Returns the context-menu Y position in physical WPE pixels.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_y(handle: u64) -> f64 {
    native_view(handle).map_or(0.0, |view| {
        view.context_menu
            .borrow()
            .as_ref()
            .map_or(0.0, |menu| menu.y)
    })
}

#[unsafe(no_mangle)]
/// Returns the number of entries in the retained menu snapshot.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.context_menu
            .borrow()
            .as_ref()
            .map_or(0, |snapshot| snapshot.items.len() as u32)
    })
}

#[unsafe(no_mangle)]
/// Returns the UTF-8 title length for a retained menu entry.
///
/// Separators, invalid indices, and missing menus return zero.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_title_length(
    handle: u64,
    index: u32,
) -> usize {
    with_context_menu_item(handle, index, 0, |item| item.title.len())
}

#[unsafe(no_mangle)]
/// Copies one retained menu title into caller-owned storage.
///
/// Returns the byte count, `-1` for a null destination, `-2` for an unavailable
/// item, or `-3` when the provided capacity is too small.
///
/// # Safety
///
/// `destination` must be writable for `destination_length` bytes and remain
/// valid for the duration of this call.
pub unsafe extern "C" fn webview_flutter_linux_wpe_context_menu_item_copy_title(
    handle: u64,
    index: u32,
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    with_context_menu_item(handle, index, -2, |item| {
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
/// Returns one when the indexed context-menu entry is a separator.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_is_separator(
    handle: u64,
    index: u32,
) -> i32 {
    with_context_menu_item(handle, index, 0, |item| i32::from(item.is_separator))
}

#[unsafe(no_mangle)]
/// Returns one when the indexed menu entry owns an enabled `GAction`.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_item_is_enabled(
    handle: u64,
    index: u32,
) -> i32 {
    with_context_menu_item(handle, index, 0, |item| {
        if item.action.is_null() {
            0
        } else {
            unsafe { i32::from(g_action_get_enabled(item.action) != 0) }
        }
    })
}

#[unsafe(no_mangle)]
/// Activates a retained WebKit context-menu action and clears the snapshot.
///
/// Returns `-2` for a missing item and `-3` for a separator or disabled action.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_activate(handle: u64, index: u32) -> i32 {
    let status = with_context_menu_item(handle, index, -2, |item| {
        if item.action.is_null() || unsafe { g_action_get_enabled(item.action) } == 0 {
            return -3;
        }
        unsafe { g_action_activate(item.action, item.target) };
        0
    });
    if status == 0
        && let Some(native_view) = native_view(handle)
    {
        native_view.context_menu.take();
    }
    status
}

#[unsafe(no_mangle)]
/// Clears the retained context menu without activating an action.
///
/// Returns zero when a menu was dismissed, one when no menu was pending, and
/// `-1` for an invalid handle.
pub extern "C" fn webview_flutter_linux_wpe_context_menu_dismiss(handle: u64) -> i32 {
    native_view(handle).map_or(-1, |view| i32::from(view.context_menu.take().is_none()))
}

#[unsafe(no_mangle)]
/// Advances the default GLib main context without blocking.
///
/// Flutter calls this from a short periodic timer because this experiment does
/// not integrate WPE's event source into the Flutter runner. The bounded loop
/// processes at most eight currently pending iterations so one view cannot
/// monopolize Flutter's platform thread. The context is process-global, so a
/// pump requested by any valid handle may advance events for every view.
pub extern "C" fn webview_flutter_linux_wpe_pump(handle: u64) -> i32 {
    if native_view(handle).is_none() {
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
/// Starts a main-frame navigation for one WebView.
///
/// WebKit copies the URI before this function returns. Returns `-1`/`-2` for
/// invalid caller strings and `-3` for an invalid or torn-down handle.
pub extern "C" fn webview_flutter_linux_wpe_navigate(handle: u64, url: *const c_char) -> i32 {
    let url =
        match required_c_string(url).and_then(|url| std::ffi::CString::new(url).map_err(|_| -2)) {
            Ok(url) => url,
            Err(status) => return status,
        };
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        let webview = ToGlibPtr::<*mut glib::gobject_ffi::GObject>::to_glib_none(&runtime.webview).0
            as *mut WebKitWebView;
        // SAFETY: webview is borrowed from the live runtime; WebKit copies URI.
        unsafe { webkit_web_view_load_uri(webview, url.as_ptr()) };
        0
    }
}

#[unsafe(no_mangle)]
/// Resizes both the WPE toplevel and its child view in physical pixels.
///
/// Dimensions must be within `1..=16384`. The texture allocation is resized
/// later from actual rendered-buffer dimensions, keeping browser and producer
/// sizes synchronized without allocating here.
pub extern "C" fn webview_flutter_linux_wpe_resize(handle: u64, width: u32, height: u32) -> i32 {
    if width == 0 || height == 0 || width > 16_384 || height > 16_384 {
        return -1;
    }
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    {
        let runtime = native_view.runtime.borrow();
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
    }
}

#[unsafe(no_mangle)]
/// Sends focus-in or focus-out to the WPE view for this handle.
pub extern "C" fn webview_flutter_linux_wpe_set_focus(handle: u64, focused: i32) -> i32 {
    with_view(handle, |view| unsafe {
        if focused != 0 {
            wpe_view_focus_in(view);
        } else {
            wpe_view_focus_out(view);
        }
    })
}

#[unsafe(no_mangle)]
/// Sets whether WPE should consider this view visible.
///
/// Flutter lifecycle changes use this to let WebKit throttle hidden pages.
pub extern "C" fn webview_flutter_linux_wpe_set_visibility(handle: u64, visible: i32) -> i32 {
    with_view(handle, |view| unsafe {
        wpe_view_set_visible(view, i32::from(visible != 0))
    })
}

/// Translates Flutter/CEF-compatible modifier bits into WPE modifier bits.
///
/// The Dart side intentionally uses DOM/CEF-style flags. Keeping the mapping at
/// this boundary isolates WPE's bit layout from Flutter keyboard code.
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

/// Converts Flutter's USB HID physical-key usage into the XKB keycode expected
/// by WPE (evdev code plus XKB's historical offset of eight).
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

/// Encodes a Unicode scalar as an XKB keysym.
///
/// Latin-1 values map directly; other scalars use XKB's `0x01000000 | codepoint`
/// convention. Invalid Unicode values return zero.
fn unicode_to_xkb_keyval(character: u32) -> u32 {
    match character {
        0 => 0,
        1..=0xff => character,
        0x100..=0x10ffff => 0x0100_0000 | character,
        _ => 0,
    }
}

/// Chooses the XKB keysym for a Flutter key event.
///
/// Printable event text wins when present. Physical HID usages cover letters,
/// digits, and punctuation when shortcuts such as Ctrl+A suppress text. The
/// final Windows/DOM key-code table handles navigation and function keys.
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

/// Runs a synchronous operation with a transfer-none WPE view pointer.
///
/// The runtime borrow and strong `Rc` remain live for the complete operation,
/// preventing disposal from invalidating the pointer during re-entrant code.
fn with_view(handle: u64, operation: impl FnOnce(*mut WpeView)) -> i32 {
    let Some(native_view) = native_view(handle) else {
        return -3;
    };
    {
        let runtime = native_view.runtime.borrow();
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        operation(runtime.view);
        0
    }
}

/// Delivers one newly allocated WPE event and releases its caller reference.
///
/// # Safety
///
/// `view` must be live for the duration of the call. A non-null `event` must
/// have been created for that exact view and carry one reference owned by this
/// function. Null events are ignored because WPE constructors may fail.
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
/// Sends an absolute pointer-move event in physical view coordinates.
///
/// WPE has no corresponding synthetic leave constructor in this path, so leave
/// notifications are intentionally accepted as no-ops.
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_move(
    handle: u64,
    x: i32,
    y: i32,
    modifiers: u32,
    mouse_leave: i32,
) -> i32 {
    if mouse_leave != 0 {
        return 0;
    }
    with_view(handle, |view| {
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
/// Sends a pointer-button press or release.
///
/// Dart button indices `0..=2` are converted to WPE's `1..=3` numbering.
/// Press counts outside `1..=3` are rejected before constructing the event.
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_button(
    handle: u64,
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
    with_view(handle, |view| {
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
/// Sends a precise two-axis scroll event at the supplied physical position.
pub extern "C" fn webview_flutter_linux_wpe_send_mouse_wheel(
    handle: u64,
    x: i32,
    y: i32,
    modifiers: u32,
    delta_x: i32,
    delta_y: i32,
) -> i32 {
    with_view(handle, |view| {
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
/// Translates and sends a Flutter keyboard event to WPE.
///
/// Dart event types `0`, `1`, and `3` are key-down variants; `2` is key-up.
/// Modifier, USB HID, DOM Windows key code, and Unicode data are combined into
/// the XKB keycode/keysym pair expected by WPE.
pub extern "C" fn webview_flutter_linux_wpe_send_key(
    handle: u64,
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
    with_view(handle, |view| {
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
/// Returns the generation assigned to the latest accepted WPE frame.
pub extern "C" fn webview_flutter_linux_wpe_frame_generation(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.metrics.frame_generation.load(Ordering::Acquire)
    })
}

#[unsafe(no_mangle)]
/// Returns the number of `buffer-rendered` signals observed for this view.
pub extern "C" fn webview_flutter_linux_wpe_paint_count(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| view.metrics.paint_count.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the number of rendered buffers successfully copied to the GL ring.
pub extern "C" fn webview_flutter_linux_wpe_valid_paint_count(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| {
        view.metrics.valid_paint_count.load(Ordering::Acquire)
    })
}

#[unsafe(no_mangle)]
/// Returns the plane count reported by the latest accepted DMA-BUF.
pub extern "C" fn webview_flutter_linux_wpe_plane_count(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.metrics.plane_count.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the DRM format reported by the latest accepted DMA-BUF.
pub extern "C" fn webview_flutter_linux_wpe_format(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.metrics.format.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the DRM modifier reported by the latest accepted DMA-BUF.
pub extern "C" fn webview_flutter_linux_wpe_modifier(handle: u64) -> u64 {
    native_view(handle).map_or(0, |view| view.metrics.modifier.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the width of the latest accepted WPE buffer.
pub extern "C" fn webview_flutter_linux_wpe_width(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.metrics.width.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the height of the latest accepted WPE buffer.
pub extern "C" fn webview_flutter_linux_wpe_height(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| view.metrics.height.load(Ordering::Acquire))
}

#[unsafe(no_mangle)]
/// Returns the first-plane stride of the latest accepted DMA-BUF.
pub extern "C" fn webview_flutter_linux_wpe_first_plane_stride(handle: u64) -> u32 {
    native_view(handle).map_or(0, |view| {
        view.metrics.first_plane_stride.load(Ordering::Acquire)
    })
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
