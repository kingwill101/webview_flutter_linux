// SPDX-License-Identifier: UNLICENSED

fn main() {
    println!("cargo::rerun-if-changed=build.rs");

    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux") {
        // The texture implementation calls EGL and OpenGL through Rust FFI.
        // libepoxy provides context-aware dispatch for Flutter's GL context.
        println!("cargo::rustc-link-lib=epoxy");
        // CEF's Linux runtime files are installed beside the Rust native
        // asset and helper executable.
        println!("cargo::rustc-link-arg=-Wl,-rpath,$ORIGIN");
    }
}
