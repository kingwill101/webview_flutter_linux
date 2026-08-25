// SPDX-License-Identifier: UNLICENSED

use cef::{
    self, Browser, ImplApp, ImplClient, ImplRenderHandler, PaintElementType, Rect, RenderHandler,
    WrapApp, WrapClient, WrapRenderHandler, args::Args, rc::Rc, *,
};
use std::{
    cell::RefCell,
    ffi::{CStr, c_char},
    path::PathBuf,
    sync::{Arc, Mutex},
};

use crate::{FRAME_BYTE_LENGTH, HEIGHT, WIDTH};

#[derive(Default)]
struct LatestFrame {
    generation: u64,
    rgba: Vec<u8>,
}

#[derive(Clone)]
struct CpuRenderHandler {
    latest_frame: Arc<Mutex<LatestFrame>>,
}

wrap_render_handler! {
    struct RenderHandlerBuilder {
        handler: CpuRenderHandler,
    }

    impl RenderHandler {
        fn view_rect(&self, _browser: Option<&mut Browser>, rect: Option<&mut Rect>) {
            if let Some(rect) = rect {
                rect.x = 0;
                rect.y = 0;
                rect.width = WIDTH as i32;
                rect.height = HEIGHT as i32;
            }
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
            if type_ != PaintElementType::default()
                || buffer.is_null()
                || width != WIDTH as i32
                || height != HEIGHT as i32
            {
                return;
            }

            // CEF owns this BGRA buffer only for the duration of OnPaint, so
            // copy and convert it before returning from the callback.
            let bgra = unsafe { std::slice::from_raw_parts(buffer, FRAME_BYTE_LENGTH) };
            let Ok(mut frame) = self.handler.latest_frame.lock() else {
                return;
            };
            frame.rgba.resize(FRAME_BYTE_LENGTH, 0);
            for (source, destination) in bgra.chunks_exact(4).zip(frame.rgba.chunks_exact_mut(4)) {
                destination.copy_from_slice(&[source[2], source[1], source[0], source[3]]);
            }
            frame.generation = frame.generation.wrapping_add(1).max(1);
        }
    }
}

impl RenderHandlerBuilder {
    fn build(handler: CpuRenderHandler) -> RenderHandler {
        Self::new(handler)
    }
}

wrap_client! {
    struct ClientBuilder {
        render_handler: RenderHandler,
    }

    impl Client {
        fn render_handler(&self) -> Option<RenderHandler> {
            Some(self.render_handler.clone())
        }
    }
}

impl ClientBuilder {
    fn build(handler: CpuRenderHandler) -> Client {
        Self::new(RenderHandlerBuilder::build(handler))
    }
}

#[derive(Clone)]
struct BrowserApp;

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
            command_line.append_switch(Some(&"disable-gpu".into()));
            command_line.append_switch(Some(&"disable-gpu-compositing".into()));
            command_line.append_switch(Some(&"disable-dev-shm-usage".into()));
            command_line.append_switch(Some(&"no-sandbox".into()));
        }
    }
}

impl AppBuilder {
    fn build() -> App {
        Self::new(BrowserApp)
    }
}

struct CefRuntime {
    _app: App,
    browser: Browser,
    latest_frame: Arc<Mutex<LatestFrame>>,
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

#[unsafe(no_mangle)]
pub extern "C" fn zikzak_cef_initialize(
    runtime_directory: *const c_char,
    initial_url: *const c_char,
) -> i32 {
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

    let helper_path = runtime_directory.join("zikzak_cef_helper");
    let locales_path = runtime_directory.join("locales");
    let libcef_path = runtime_directory.join("libcef.so");
    if !helper_path.is_file() || !locales_path.is_dir() || !libcef_path.is_file() {
        return -3;
    }

    let _ = cef::api_hash(cef::sys::CEF_API_VERSION_LAST, 0);
    let args = Args::new();
    let mut app = AppBuilder::build();
    let process_result = cef::execute_process(
        Some(args.as_main_args()),
        Some(&mut app),
        std::ptr::null_mut(),
    );
    if process_result != -1 {
        return -4;
    }

    let cache_path = std::env::temp_dir().join(format!("zikzak-cef-cache-{}", std::process::id()));
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
    let window_info = cef::WindowInfo {
        windowless_rendering_enabled: true as _,
        shared_texture_enabled: false as _,
        external_begin_frame_enabled: false as _,
        ..Default::default()
    };
    let browser_settings = cef::BrowserSettings {
        windowless_frame_rate: 30,
        ..Default::default()
    };
    let browser = cef::browser_host_create_browser_sync(
        Some(&window_info),
        Some(&mut ClientBuilder::build(CpuRenderHandler {
            latest_frame: latest_frame.clone(),
        })),
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
        });
    });
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn zikzak_cef_pump() -> i32 {
    if !RUNTIME.with_borrow(|runtime| runtime.is_some()) {
        return -1;
    }
    cef::do_message_loop_work();
    0
}

#[unsafe(no_mangle)]
pub extern "C" fn zikzak_cef_frame_generation() -> u64 {
    RUNTIME.with_borrow(|runtime| {
        runtime
            .as_ref()
            .and_then(|runtime| runtime.latest_frame.lock().ok())
            .map_or(0, |frame| frame.generation)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zikzak_cef_copy_latest_frame(
    destination: *mut u8,
    destination_length: usize,
) -> i32 {
    if destination.is_null() {
        return -1;
    }
    if destination_length < FRAME_BYTE_LENGTH {
        return -2;
    }

    RUNTIME.with_borrow(|runtime| {
        let Some(runtime) = runtime.as_ref() else {
            return -3;
        };
        let Ok(frame) = runtime.latest_frame.lock() else {
            return -4;
        };
        if frame.generation == 0 || frame.rgba.len() != FRAME_BYTE_LENGTH {
            return 0;
        }
        // SAFETY: The caller declared at least FRAME_BYTE_LENGTH writable
        // bytes, and the source vector has exactly that many initialized bytes.
        unsafe {
            std::ptr::copy_nonoverlapping(frame.rgba.as_ptr(), destination, FRAME_BYTE_LENGTH);
        }
        1
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn zikzak_cef_navigate(url: *const c_char) -> i32 {
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
