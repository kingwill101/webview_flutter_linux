/* SPDX-License-Identifier: UNLICENSED */

#ifndef ZIKZAK_NATIVE_TEXTURE_BRIDGE_H_
#define ZIKZAK_NATIVE_TEXTURE_BRIDGE_H_

#include <flutter_linux/flutter_linux.h>

G_BEGIN_DECLS

typedef struct _ZikzakNativeTextureBridge ZikzakNativeTextureBridge;

// Registers the runner's narrow FlTextureGL-to-Rust FFI bridge.
//
// The bridge contains no browser or GTK rendering logic. Flutter owns the GL
// context and texture registration; Rust supplies texture state and pixels.
ZikzakNativeTextureBridge *zikzak_native_texture_bridge_new(FlView *view);

void zikzak_native_texture_bridge_free(ZikzakNativeTextureBridge *bridge);

G_END_DECLS

#endif // ZIKZAK_NATIVE_TEXTURE_BRIDGE_H_
