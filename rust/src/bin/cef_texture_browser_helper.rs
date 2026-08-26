// SPDX-License-Identifier: UNLICENSED

use cef::{args::Args, *};

fn main() -> std::process::ExitCode {
    let _ = api_hash(sys::CEF_API_VERSION_LAST, 0);
    let args = Args::new();
    let exit_code = execute_process(Some(args.as_main_args()), None, std::ptr::null_mut());

    if exit_code < 0 {
        eprintln!("cef_texture_browser_helper was launched without a CEF process type");
        return std::process::ExitCode::FAILURE;
    }

    std::process::ExitCode::from(exit_code as u8)
}
