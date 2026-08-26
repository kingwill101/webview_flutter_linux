// SPDX-License-Identifier: UNLICENSED

use cef::{
    self, Browser, ImplApp, ImplClient, ImplLifeSpanHandler, ImplRenderHandler, LifeSpanHandler,
    PaintElementType, Rect, RenderHandler, WrapApp, WrapClient, WrapLifeSpanHandler,
    WrapRenderHandler, args::Args, rc::Rc, *,
};
use std::{
    cell::RefCell,
    ffi::{CStr, c_char},
    path::PathBuf,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    time::{Duration, Instant},
};

use crate::{HEIGHT, WIDTH};

const MAX_FRAME_BYTE_LENGTH: usize = 512 * 1024 * 1024;

#[derive(Default)]
struct LatestFrame {
    generation: u64,
    width: u32,
    height: u32,
    rgba: Vec<u8>,
}

#[derive(Clone, Copy, Default)]
struct AcceleratedPaintSnapshot {
    paint_count: u64,
    valid_paint_count: u64,
    plane_count: u32,
    format: u32,
    modifier: u64,
    coded_width: i32,
    coded_height: i32,
    visible_width: i32,
    visible_height: i32,
    first_plane_stride: u32,
}

static DMA_BUF_GENERATION: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy)]
struct SurfaceMetrics {
    width: i32,
    height: i32,
    device_scale_factor: f32,
}

impl Default for SurfaceMetrics {
    fn default() -> Self {
        Self {
            width: WIDTH as i32,
            height: HEIGHT as i32,
            device_scale_factor: 1.0,
        }
    }
}

#[derive(Clone)]
struct BrowserRenderHandler {
    latest_frame: Arc<Mutex<LatestFrame>>,
    accelerated_paint: Arc<Mutex<AcceleratedPaintSnapshot>>,
    surface: Arc<Mutex<SurfaceMetrics>>,
}

wrap_render_handler! {
    struct RenderHandlerBuilder {
        handler: BrowserRenderHandler,
    }

    impl RenderHandler {
        fn view_rect(&self, _browser: Option<&mut Browser>, rect: Option<&mut Rect>) {
            if let (Some(rect), Ok(surface)) = (rect, self.handler.surface.lock()) {
                rect.x = 0;
                rect.y = 0;
                rect.width = surface.width;
                rect.height = surface.height;
            }
        }

        fn screen_info(
            &self,
            _browser: Option<&mut Browser>,
            screen_info: Option<&mut ScreenInfo>,
        ) -> ::std::os::raw::c_int {
            let (Some(screen_info), Ok(surface)) =
                (screen_info, self.handler.surface.lock())
            else {
                return false as _;
            };
            screen_info.device_scale_factor = surface.device_scale_factor;
            screen_info.rect = Rect {
                x: 0,
                y: 0,
                width: surface.width,
                height: surface.height,
            };
            screen_info.available_rect = screen_info.rect.clone();
            true as _
        }

        fn screen_point(
            &self,
            _browser: Option<&mut Browser>,
            view_x: ::std::os::raw::c_int,
            view_y: ::std::os::raw::c_int,
            screen_x: Option<&mut ::std::os::raw::c_int>,
            screen_y: Option<&mut ::std::os::raw::c_int>,
        ) -> ::std::os::raw::c_int {
            if let (Some(screen_x), Some(screen_y)) = (screen_x, screen_y) {
                *screen_x = view_x;
                *screen_y = view_y;
                return true as _;
            }
            false as _
        }

        fn on_paint(
            &self,
            _browser: Option<&mut Browser>,
            type_: PaintElementType,
            _dirty_rects: Option<&[Rect]>,
            buffer: *const u8,
            width: i32,
            height: i32,
        ) {
            if type_ != PaintElementType::default() || buffer.is_null() {
                return;
            }

            let Some(byte_length) = checked_frame_byte_length(width, height) else {
                return;
            };

            // CEF owns this BGRA buffer only for the duration of OnPaint, so
            // copy and convert it before returning from the callback.
            let bgra = unsafe { std::slice::from_raw_parts(buffer, byte_length) };
            let Ok(mut frame) = self.handler.latest_frame.lock() else {
                return;
            };
            frame.rgba.resize(byte_length, 0);
            for (source, destination) in bgra.chunks_exact(4).zip(frame.rgba.chunks_exact_mut(4)) {
                destination.copy_from_slice(&[source[2], source[1], source[0], source[3]]);
            }
            frame.width = width as u32;
            frame.height = height as u32;
            frame.generation = frame.generation.wrapping_add(1).max(1);
        }

        fn on_accelerated_paint(
            &self,
            _browser: Option<&mut Browser>,
            type_: PaintElementType,
            _dirty_rects: Option<&[Rect]>,
            info: Option<&AcceleratedPaintInfo>,
        ) {
            if type_ != PaintElementType::default() {
                return;
            }
            let Some(info) = info else {
                return;
            };
            let valid = accelerated_paint_info_is_valid(info);
            if let Ok(mut snapshot) = self.handler.accelerated_paint.lock() {
                snapshot.paint_count = snapshot.paint_count.wrapping_add(1).max(1);
                snapshot.plane_count = u32::try_from(info.plane_count).unwrap_or_default();
                snapshot.format = info.format.get_raw();
                snapshot.modifier = info.modifier;
                snapshot.coded_width = info.extra.coded_size.width;
                snapshot.coded_height = info.extra.coded_size.height;
                snapshot.visible_width = info.extra.visible_rect.width;
                snapshot.visible_height = info.extra.visible_rect.height;
                snapshot.first_plane_stride =
                    info.planes.first().map_or(0, |plane| plane.stride);
                if valid {
                    snapshot.valid_paint_count =
                        snapshot.valid_paint_count.wrapping_add(1).max(1);
                }
            }
            if valid {
                let generation = DMA_BUF_GENERATION
                    .fetch_add(1, Ordering::AcqRel)
                    .wrapping_add(1)
                    .max(1);
                copy_accelerated_frame_during_callback(info, generation);
                crate::notify_flutter_texture_frame();
            }
        }
    }
}

impl RenderHandlerBuilder {
    fn build(handler: BrowserRenderHandler) -> RenderHandler {
        Self::new(handler)
    }
}

fn accelerated_paint_info_is_valid(info: &AcceleratedPaintInfo) -> bool {
    let Ok(plane_count) = usize::try_from(info.plane_count) else {
        return false;
    };
    if !(1..=info.planes.len()).contains(&plane_count)
        || info.extra.coded_size.width <= 0
        || info.extra.coded_size.height <= 0
        || info.extra.visible_rect.width <= 0
        || info.extra.visible_rect.height <= 0
    {
        return false;
    }
    info.planes[..plane_count]
        .iter()
        .all(|plane| plane.fd >= 0 && plane.stride > 0 && plane.size > 0)
}

fn copy_accelerated_frame_during_callback(info: &AcceleratedPaintInfo, generation: u64) -> i32 {
    let plane_count = usize::try_from(info.plane_count).unwrap_or_default();
    let mut frame = crate::linux_texture::DmaBufFrame {
        generation,
        plane_count: info.plane_count as u32,
        fds: [-1; 4],
        strides: [0; 4],
        offsets: [0; 4],
        modifier: info.modifier,
        format: info.format.get_raw(),
        coded_width: info.extra.coded_size.width,
        coded_height: info.extra.coded_size.height,
        visible_x: info.extra.visible_rect.x,
        visible_y: info.extra.visible_rect.y,
        visible_width: info.extra.visible_rect.width,
        visible_height: info.extra.visible_rect.height,
    };
    for (index, plane) in info.planes[..plane_count].iter().enumerate() {
        frame.fds[index] = plane.fd;
        frame.strides[index] = plane.stride;
        frame.offsets[index] = plane.offset;
    }
    // The Rust texture layer synchronously imports and copies the borrowed
    // DMA-BUF before CEF returns from this callback.
    crate::linux_texture::copy_dma_buf(&frame)
}

wrap_context_menu_handler! {
    struct WindowlessContextMenuHandler;

    impl ContextMenuHandler {
        fn on_before_context_menu(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            _params: Option<&mut ContextMenuParams>,
            model: Option<&mut MenuModel>,
        ) {
            if let Some(model) = model {
                model.clear();
            }
        }

        fn run_context_menu(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            _params: Option<&mut ContextMenuParams>,
            _model: Option<&mut MenuModel>,
            callback: Option<&mut RunContextMenuCallback>,
        ) -> ::std::os::raw::c_int {
            if let Some(callback) = callback {
                callback.cancel();
            }
            true as _
        }
    }
}

wrap_life_span_handler! {
    struct WindowlessLifeSpanHandler {
        browser_closed: Arc<AtomicBool>,
    }

    impl LifeSpanHandler {
        fn on_before_close(&self, _browser: Option<&mut Browser>) {
            self.browser_closed.store(true, Ordering::Release);
        }
    }
}

wrap_client! {
    struct ClientBuilder {
        render_handler: RenderHandler,
        context_menu_handler: ContextMenuHandler,
        life_span_handler: LifeSpanHandler,
    }

    impl Client {
        fn render_handler(&self) -> Option<RenderHandler> {
            Some(self.render_handler.clone())
        }

        fn context_menu_handler(&self) -> Option<ContextMenuHandler> {
            Some(self.context_menu_handler.clone())
        }

        fn life_span_handler(&self) -> Option<LifeSpanHandler> {
            Some(self.life_span_handler.clone())
        }
    }
}

impl ClientBuilder {
    fn build(handler: BrowserRenderHandler, browser_closed: Arc<AtomicBool>) -> Client {
        Self::new(
            RenderHandlerBuilder::build(handler),
            WindowlessContextMenuHandler::new(),
            WindowlessLifeSpanHandler::new(browser_closed),
        )
    }
}

#[derive(Clone)]
struct BrowserApp {
    accelerated: bool,
    ozone_platform: String,
}

wrap_app! {
    struct AppBuilder {
        app: BrowserApp,
    }

    impl App {
        fn on_before_command_line_processing(
            &self,
            _process_type: Option<&cef::CefStringUtf16>,
            command_line: Option<&mut cef::CommandLine>,
        ) {
            let Some(command_line) = command_line else {
                return;
            };
            command_line.append_switch(Some(&"no-startup-window".into()));
            command_line.append_switch(Some(&"no-first-run".into()));
            command_line.append_switch(Some(&"disable-default-apps".into()));
            command_line.append_switch(Some(&"use-alloy-style".into()));
            command_line.append_switch(Some(&"disable-dev-shm-usage".into()));
            command_line.append_switch(Some(&"no-sandbox".into()));
            if self.app.accelerated {
                command_line.append_switch_with_value(
                    Some(&"use-angle".into()),
                    Some(&"gl-egl".into()),
                );
                command_line.append_switch_with_value(
                    Some(&"ozone-platform".into()),
                    Some(&self.app.ozone_platform.as_str().into()),
                );
            } else {
                command_line.append_switch(Some(&"disable-gpu".into()));
                command_line.append_switch(Some(&"disable-gpu-compositing".into()));
            }
        }
    }
}

impl AppBuilder {
    fn build(accelerated: bool) -> App {
        let override_value = std::env::var("CEF_TEXTURE_BROWSER_OZONE_PLATFORM").ok();
        let session_type = std::env::var("XDG_SESSION_TYPE").ok();
        let ozone_platform = select_ozone_platform(
            override_value.as_deref(),
            session_type.as_deref(),
            std::env::var_os("WAYLAND_DISPLAY").is_some(),
        );
        Self::new(BrowserApp {
            accelerated,
            ozone_platform,
        })
    }
}

fn select_ozone_platform(
    override_value: Option<&str>,
    session_type: Option<&str>,
    has_wayland_display: bool,
) -> String {
    if let Some(value @ ("x11" | "wayland")) = override_value {
        return value.to_owned();
    }
    if session_type == Some("wayland") && has_wayland_display {
        "wayland".to_owned()
    } else {
        "x11".to_owned()
    }
}

struct CefRuntime {
    _app: App,
    browser: Browser,
    latest_frame: Arc<Mutex<LatestFrame>>,
    accelerated_paint: Arc<Mutex<AcceleratedPaintSnapshot>>,
    surface: Arc<Mutex<SurfaceMetrics>>,
    browser_closed: Arc<AtomicBool>,
    accelerated: bool,
}

thread_local! {
    static RUNTIME: RefCell<Option<CefRuntime>> = const { RefCell::new(None) };
}

fn required_c_string(pointer: *const c_char) -> Result<String, i32> {
    if pointer.is_null() {
        return Err(-1);
    }
    // SAFETY: FFI callers must supply a pointer to a NUL-terminated string.
    let value = unsafe { CStr::from_ptr(pointer) };
    value.to_str().map(str::to_owned).map_err(|_| -2)
}

fn checked_frame_byte_length(width: i32, height: i32) -> Option<usize> {
    let width = usize::try_from(width).ok()?;
    let height = usize::try_from(height).ok()?;
    if width == 0 || height == 0 {
        return None;
    }
    let byte_length = width.checked_mul(height)?.checked_mul(4)?;
    (byte_length <= MAX_FRAME_BYTE_LENGTH).then_some(byte_length)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_initialize(
    runtime_directory: *const c_char,
    initial_url: *const c_char,
) -> i32 {
    cef_texture_browser_cef_initialize_with_options(runtime_directory, initial_url, 0)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_initialize_with_options(
    runtime_directory: *const c_char,
    initial_url: *const c_char,
    transport: u32,
) -> i32 {
    if transport > 1 {
        return -7;
    }
    let accelerated = transport == 1;
    let runtime_directory = match required_c_string(runtime_directory) {
        Ok(value) => PathBuf::from(value),
        Err(status) => return status,
    };
    let initial_url = match required_c_string(initial_url) {
        Ok(value) => value,
        Err(status) => return status,
    };

    if RUNTIME.with_borrow(|runtime| runtime.is_some()) {
        return 1;
    }
    DMA_BUF_GENERATION.store(0, Ordering::Release);

    let helper_path = runtime_directory.join("cef_texture_browser_helper");
    let locales_path = runtime_directory.join("locales");
    let libcef_path = runtime_directory.join("libcef.so");
    if !helper_path.is_file() || !locales_path.is_dir() || !libcef_path.is_file() {
        return -3;
    }

    let _ = cef::api_hash(cef::sys::CEF_API_VERSION_LAST, 0);
    let args = Args::new();
    let mut app = AppBuilder::build(accelerated);
    let process_result = cef::execute_process(
        Some(args.as_main_args()),
        Some(&mut app),
        std::ptr::null_mut(),
    );
    if process_result != -1 {
        return -4;
    }

    let cache_path =
        std::env::temp_dir().join(format!("cef-texture-browser-cache-{}", std::process::id()));
    let _ = std::fs::create_dir_all(&cache_path);
    let settings = cef::Settings {
        no_sandbox: true as _,
        browser_subprocess_path: helper_path.to_string_lossy().as_ref().into(),
        external_message_pump: true as _,
        windowless_rendering_enabled: true as _,
        cache_path: cache_path.to_string_lossy().as_ref().into(),
        root_cache_path: cache_path.to_string_lossy().as_ref().into(),
        resources_dir_path: runtime_directory.to_string_lossy().as_ref().into(),
        locales_dir_path: locales_path.to_string_lossy().as_ref().into(),
        log_severity: cef::LogSeverity::WARNING,
        ..Default::default()
    };
    if cef::initialize(
        Some(args.as_main_args()),
        Some(&settings),
        Some(&mut app),
        std::ptr::null_mut(),
    ) != 1
    {
        return -5;
    }

    let latest_frame = Arc::new(Mutex::new(LatestFrame::default()));
    let accelerated_paint = Arc::new(Mutex::new(AcceleratedPaintSnapshot::default()));
    let surface = Arc::new(Mutex::new(SurfaceMetrics::default()));
    let browser_closed = Arc::new(AtomicBool::new(false));
    let window_info = cef::WindowInfo {
        windowless_rendering_enabled: true as _,
        shared_texture_enabled: accelerated as _,
        external_begin_frame_enabled: accelerated as _,
        runtime_style: RuntimeStyle::ALLOY,
        ..Default::default()
    };
    let browser_settings = cef::BrowserSettings {
        windowless_frame_rate: 60,
        ..Default::default()
    };
    let browser = cef::browser_host_create_browser_sync(
        Some(&window_info),
        Some(&mut ClientBuilder::build(
            BrowserRenderHandler {
                latest_frame: latest_frame.clone(),
                accelerated_paint: accelerated_paint.clone(),
                surface: surface.clone(),
            },
            browser_closed.clone(),
        )),
        Some(&initial_url.as_str().into()),
        Some(&browser_settings),
        None,
        None,
    );
    let Some(browser) = browser else {
        cef::shutdown();
        return -6;
    };

    RUNTIME.with_borrow_mut(|runtime| {
        runtime.replace(CefRuntime {
            _app: app,
            browser,
            latest_frame,
            accelerated_paint,
            surface,
            browser_closed,
            accelerated,
        });
    });
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_shutdown() -> i32 {
    let Some((browser, browser_closed)) = RUNTIME.with_borrow(|runtime| {
        runtime
            .as_ref()
            .map(|runtime| (runtime.browser.clone(), runtime.browser_closed.clone()))
    }) else {
        return 1;
    };

    let Some(host) = browser.host() else {
        return -1;
    };
    host.close_browser(1);

    let deadline = Instant::now() + Duration::from_secs(5);
    while !browser_closed.load(Ordering::Acquire) && Instant::now() < deadline {
        cef::do_message_loop_work();
        std::thread::sleep(Duration::from_millis(1));
    }
    if !browser_closed.load(Ordering::Acquire) {
        return -2;
    }

    drop(host);
    drop(browser);
    let runtime = RUNTIME.with_borrow_mut(Option::take);
    drop(runtime);
    cef::shutdown();
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_pump() -> i32 {
    if !RUNTIME.with_borrow(|runtime| runtime.is_some()) {
        return -1;
    }
    cef::do_message_loop_work();
    RUNTIME.with_borrow(|runtime| {
        if let Some(runtime) = runtime.as_ref()
            && runtime.accelerated
            && let Some(host) = runtime.browser.host()
        {
            host.send_external_begin_frame();
        }
    });
    0
}

fn accelerated_stat<T: Default>(read: impl FnOnce(&AcceleratedPaintSnapshot) -> T) -> T {
    RUNTIME.with_borrow(|runtime| {
        runtime
            .as_ref()
            .and_then(|runtime| runtime.accelerated_paint.lock().ok())
            .map_or_else(T::default, |snapshot| read(&snapshot))
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_paint_count() -> u64 {
    accelerated_stat(|snapshot| snapshot.paint_count)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_valid_paint_count() -> u64 {
    accelerated_stat(|snapshot| snapshot.valid_paint_count)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_plane_count() -> u32 {
    accelerated_stat(|snapshot| snapshot.plane_count)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_format() -> u32 {
    accelerated_stat(|snapshot| snapshot.format)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_modifier() -> u64 {
    accelerated_stat(|snapshot| snapshot.modifier)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_coded_width() -> i32 {
    accelerated_stat(|snapshot| snapshot.coded_width)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_coded_height() -> i32 {
    accelerated_stat(|snapshot| snapshot.coded_height)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_visible_width() -> i32 {
    accelerated_stat(|snapshot| snapshot.visible_width)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_visible_height() -> i32 {
    accelerated_stat(|snapshot| snapshot.visible_height)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_accelerated_first_plane_stride() -> u32 {
    accelerated_stat(|snapshot| snapshot.first_plane_stride)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_dma_buf_generation() -> u64 {
    DMA_BUF_GENERATION.load(Ordering::Acquire)
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_frame_generation() -> u64 {
    RUNTIME.with_borrow(|runtime| {
        runtime
            .as_ref()
            .and_then(|runtime| runtime.latest_frame.lock().ok())
            .map_or(0, |frame| frame.generation)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_frame_width() -> u32 {
    RUNTIME.with_borrow(|runtime| {
        runtime
            .as_ref()
            .and_then(|runtime| runtime.latest_frame.lock().ok())
            .map_or(0, |frame| frame.width)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_frame_height() -> u32 {
    RUNTIME.with_borrow(|runtime| {
        runtime
            .as_ref()
            .and_then(|runtime| runtime.latest_frame.lock().ok())
            .map_or(0, |frame| frame.height)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_frame_byte_length() -> usize {
    RUNTIME.with_borrow(|runtime| {
        runtime
            .as_ref()
            .and_then(|runtime| runtime.latest_frame.lock().ok())
            .map_or(0, |frame| frame.rgba.len())
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cef_texture_browser_cef_copy_latest_frame(
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }

    RUNTIME.with_borrow(|runtime| {
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        let Ok(frame) = runtime.latest_frame.lock() else {
            return -4;
        };
        if frame.generation == 0 || frame.rgba.is_empty() {
            return 0;
        }
        if destination_length < frame.rgba.len() {
            return -2;
        }
        // SAFETY: The caller declared enough writable bytes for the complete
        // source frame, whose vector contains only initialized bytes.
        unsafe {
            std::ptr::copy_nonoverlapping(frame.rgba.as_ptr(), destination, frame.rgba.len());
        }
        1
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_navigate(url: *const c_char) -> i32 {
    let url = match required_c_string(url) {
        Ok(value) => value,
        Err(status) => return status,
    };

    RUNTIME.with_borrow_mut(|runtime| {
        let Some(runtime) = runtime.as_mut() else {
            return -3;
        };
        let Some(frame) = runtime.browser.main_frame() else {
            return -4;
        };
        frame.load_url(Some(&url.as_str().into()));
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_resize(
    logical_width: u32,
    logical_height: u32,
    device_scale_factor: f32,
) -> i32 {
    if logical_width == 0
        || logical_height == 0
        || logical_width > 8192
        || logical_height > 8192
        || !device_scale_factor.is_finite()
        || !(0.5..=4.0).contains(&device_scale_factor)
    {
        return -1;
    }

    RUNTIME.with_borrow_mut(|runtime| {
        let Some(runtime) = runtime.as_mut() else {
            return -3;
        };
        let Ok(mut surface) = runtime.surface.lock() else {
            return -4;
        };
        let scale_changed =
            (surface.device_scale_factor - device_scale_factor).abs() > f32::EPSILON;
        let size_changed =
            surface.width != logical_width as i32 || surface.height != logical_height as i32;
        if !size_changed && !scale_changed {
            return 0;
        }
        surface.width = logical_width as i32;
        surface.height = logical_height as i32;
        surface.device_scale_factor = device_scale_factor;
        drop(surface);

        let Some(host) = runtime.browser.host() else {
            return -5;
        };
        if scale_changed {
            host.notify_screen_info_changed();
        }
        host.was_resized();
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_set_focus(focused: i32) -> i32 {
    RUNTIME.with_borrow(|runtime| {
        let Some(host) = runtime.as_ref().and_then(|runtime| runtime.browser.host()) else {
            return -3;
        };
        host.set_focus((focused != 0) as i32);
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_set_visibility(visible: i32) -> i32 {
    RUNTIME.with_borrow(|runtime| {
        let Some(host) = runtime.as_ref().and_then(|runtime| runtime.browser.host()) else {
            return -3;
        };
        host.was_hidden((visible == 0) as i32);
        0
    })
}

fn mouse_event(x: i32, y: i32, modifiers: u32) -> MouseEvent {
    MouseEvent { x, y, modifiers }
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_send_mouse_move(
    x: i32,
    y: i32,
    modifiers: u32,
    mouse_leave: i32,
) -> i32 {
    RUNTIME.with_borrow(|runtime| {
        let Some(host) = runtime.as_ref().and_then(|runtime| runtime.browser.host()) else {
            return -3;
        };
        host.send_mouse_move_event(
            Some(&mouse_event(x, y, modifiers)),
            (mouse_leave != 0) as i32,
        );
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_send_mouse_button(
    x: i32,
    y: i32,
    modifiers: u32,
    button: u32,
    mouse_up: i32,
    click_count: i32,
) -> i32 {
    let button = match button {
        0 => MouseButtonType::LEFT,
        1 => MouseButtonType::MIDDLE,
        2 => MouseButtonType::RIGHT,
        _ => return -1,
    };
    if !(1..=3).contains(&click_count) {
        return -2;
    }
    RUNTIME.with_borrow(|runtime| {
        let Some(host) = runtime.as_ref().and_then(|runtime| runtime.browser.host()) else {
            return -3;
        };
        host.send_mouse_click_event(
            Some(&mouse_event(x, y, modifiers)),
            button,
            (mouse_up != 0) as i32,
            click_count,
        );
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_send_mouse_wheel(
    x: i32,
    y: i32,
    modifiers: u32,
    delta_x: i32,
    delta_y: i32,
) -> i32 {
    RUNTIME.with_borrow(|runtime| {
        let Some(host) = runtime.as_ref().and_then(|runtime| runtime.browser.host()) else {
            return -3;
        };
        host.send_mouse_wheel_event(Some(&mouse_event(x, y, modifiers)), delta_x, delta_y);
        0
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn cef_texture_browser_cef_send_key(
    event_type: u32,
    modifiers: u32,
    windows_key_code: i32,
    native_key_code: i32,
    character: u32,
    unmodified_character: u32,
) -> i32 {
    let type_ = match event_type {
        0 => KeyEventType::RAWKEYDOWN,
        1 => KeyEventType::KEYDOWN,
        2 => KeyEventType::KEYUP,
        3 => KeyEventType::CHAR,
        _ => return -1,
    };
    let Ok(character) = u16::try_from(character) else {
        return -2;
    };
    let Ok(unmodified_character) = u16::try_from(unmodified_character) else {
        return -2;
    };

    RUNTIME.with_borrow(|runtime| {
        let Some(host) = runtime.as_ref().and_then(|runtime| runtime.browser.host()) else {
            return -3;
        };
        host.send_key_event(Some(&KeyEvent {
            type_,
            modifiers,
            windows_key_code,
            native_key_code,
            character,
            unmodified_character,
            ..Default::default()
        }));
        0
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid_accelerated_paint_info() -> AcceleratedPaintInfo {
        let mut info = AcceleratedPaintInfo {
            plane_count: 1,
            ..Default::default()
        };
        info.planes[0].fd = 7;
        info.planes[0].stride = 2_560;
        info.planes[0].size = 1_228_800;
        info.extra.coded_size = Size {
            width: 640,
            height: 480,
        };
        info.extra.visible_rect = Rect {
            x: 0,
            y: 0,
            width: 640,
            height: 480,
        };
        info
    }

    #[test]
    fn computes_dynamic_frame_byte_length() {
        assert_eq!(checked_frame_byte_length(1280, 720), Some(3_686_400));
    }

    #[test]
    fn rejects_non_positive_frame_dimensions() {
        assert_eq!(checked_frame_byte_length(0, 720), None);
        assert_eq!(checked_frame_byte_length(1280, -1), None);
    }

    #[test]
    fn rejects_frames_above_the_memory_limit() {
        assert_eq!(checked_frame_byte_length(32_768, 32_768), None);
    }

    #[test]
    fn accepts_complete_accelerated_paint_metadata() {
        assert!(accelerated_paint_info_is_valid(
            &valid_accelerated_paint_info()
        ));
    }

    #[test]
    fn rejects_incomplete_accelerated_paint_metadata() {
        let mut info = valid_accelerated_paint_info();
        info.plane_count = 0;
        assert!(!accelerated_paint_info_is_valid(&info));

        info = valid_accelerated_paint_info();
        info.planes[0].size = 0;
        assert!(!accelerated_paint_info_is_valid(&info));

        info = valid_accelerated_paint_info();
        info.extra.visible_rect.width = 0;
        assert!(!accelerated_paint_info_is_valid(&info));
    }

    #[test]
    fn ozone_platform_prefers_valid_override_then_active_session() {
        assert_eq!(
            select_ozone_platform(Some("x11"), Some("wayland"), true),
            "x11"
        );
        assert_eq!(
            select_ozone_platform(None, Some("wayland"), true),
            "wayland"
        );
        assert_eq!(select_ozone_platform(None, Some("wayland"), false), "x11");
        assert_eq!(
            select_ozone_platform(Some("invalid"), Some("x11"), true),
            "x11"
        );
    }
}
