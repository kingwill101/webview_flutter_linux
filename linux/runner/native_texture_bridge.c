/* SPDX-License-Identifier: UNLICENSED */

#include "native_texture_bridge.h"

#include <epoxy/egl.h>
#include <epoxy/gl.h>
#include <gmodule.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

#include "../../rust/include/zikzak_browser_ffi.h"

typedef int32_t (*ZikzakAttachFn)(
    int64_t texture_id, zikzak_flutter_texture_frame_callback callback,
    void *user_data);
typedef void (*ZikzakDetachFn)(int64_t texture_id);
typedef uint32_t (*ZikzakDimensionFn)(void);
typedef uint64_t (*ZikzakGenerationFn)(void);
typedef int32_t (*ZikzakRenderFrameFn)(uint8_t *destination,
                                       size_t destination_length,
                                       uint32_t width, uint32_t height,
                                       uint64_t generation);
typedef int32_t (*ZikzakPublishGlStateFn)(uint32_t name, uint32_t width,
                                          uint32_t height,
                                          uintptr_t egl_display,
                                          uintptr_t egl_context);
typedef void (*ZikzakPublishDmaBufResultFn)(uint64_t generation,
                                            int32_t status);
typedef int32_t (*ZikzakDmaBufCopyAttachFn)(
    zikzak_dma_buf_copy_callback callback, void *user_data);
typedef void (*ZikzakDmaBufCopyDetachFn)(void *user_data);

typedef struct _ZikzakNativeTexture {
  FlTextureGL parent_instance;
  GMutex gl_mutex;
  GLuint gl_name;
  uint8_t *pixels;
  size_t pixel_capacity;
  uint64_t uploaded_generation;
  uint64_t imported_dma_buf_generation;
  uint32_t allocated_width;
  uint32_t allocated_height;
  ZikzakDimensionFn get_width;
  ZikzakDimensionFn get_height;
  ZikzakGenerationFn get_generation;
  ZikzakRenderFrameFn render_frame;
  ZikzakPublishGlStateFn publish_gl_state;
  ZikzakPublishDmaBufResultFn publish_dma_buf_result;
  EGLDisplay copy_display;
  EGLContext copy_context;
  EGLSurface copy_surface;
  EGLenum copy_api;
} ZikzakNativeTexture;

typedef struct _ZikzakNativeTextureClass {
  FlTextureGLClass parent_class;
} ZikzakNativeTextureClass;

G_DEFINE_TYPE(ZikzakNativeTexture, zikzak_native_texture,
              fl_texture_gl_get_type())

struct _ZikzakNativeTextureBridge {
  GModule *native_module;
  FlTextureRegistrar *registrar;
  ZikzakNativeTexture *texture;
  int64_t texture_id;
  ZikzakDetachFn detach;
  ZikzakDmaBufCopyDetachFn detach_dma_buf_copy;
};

static void mark_texture_frame_available(void *user_data);

static GQuark zikzak_native_texture_error_quark(void) {
  return g_quark_from_static_string("zikzak-native-texture-error");
}

#define ZIKZAK_FOURCC(a, b, c, d)                                              \
  ((uint32_t)(a) | ((uint32_t)(b) << 8) | ((uint32_t)(c) << 16) |              \
   ((uint32_t)(d) << 24))
#define ZIKZAK_DRM_FORMAT_ARGB8888 ZIKZAK_FOURCC('A', 'R', '2', '4')
#define ZIKZAK_DRM_FORMAT_ABGR8888 ZIKZAK_FOURCC('A', 'B', '2', '4')

static uint32_t drm_format_for_cef(uint32_t format) {
  switch (format) {
  case 0: // CEF_COLOR_TYPE_RGBA_8888
    return ZIKZAK_DRM_FORMAT_ABGR8888;
  case 1: // CEF_COLOR_TYPE_BGRA_8888
    return ZIKZAK_DRM_FORMAT_ARGB8888;
  default:
    return 0;
  }
}

static gboolean ensure_dma_buf_copy_context(ZikzakNativeTexture *self) {
  if (self->copy_context != EGL_NO_CONTEXT) {
    return TRUE;
  }
  EGLDisplay display = eglGetCurrentDisplay();
  EGLContext flutter_context = eglGetCurrentContext();
  if (display == EGL_NO_DISPLAY || flutter_context == EGL_NO_CONTEXT ||
      !epoxy_has_egl_extension(display, "EGL_KHR_surfaceless_context")) {
    return FALSE;
  }

  EGLint config_id = 0;
  EGLint client_version = 0;
  if (!eglQueryContext(display, flutter_context, EGL_CONFIG_ID, &config_id) ||
      !eglQueryContext(display, flutter_context, EGL_CONTEXT_CLIENT_VERSION,
                       &client_version)) {
    return FALSE;
  }
  EGLConfig config = NULL;
  EGLint config_count = 0;
  const EGLint config_attributes[] = {EGL_CONFIG_ID, config_id, EGL_NONE};
  if (!eglChooseConfig(display, config_attributes, &config, 1, &config_count) ||
      config_count != 1) {
    return FALSE;
  }

  const EGLenum api = eglQueryAPI();
  const EGLint context_attributes[] = {
      EGL_CONTEXT_CLIENT_VERSION,
      client_version,
      EGL_NONE,
  };
  EGLContext copy_context =
      eglCreateContext(display, config, flutter_context, context_attributes);
  if (copy_context == EGL_NO_CONTEXT) {
    return FALSE;
  }
  self->copy_display = display;
  self->copy_context = copy_context;
  self->copy_surface = EGL_NO_SURFACE;
  self->copy_api = api;
  return TRUE;
}

static int32_t copy_dma_buf_to_flutter_texture(
    ZikzakNativeTexture *self, const zikzak_dma_buf_frame *frame,
    uint32_t destination_width, uint32_t destination_height) {
  const EGLDisplay display = eglGetCurrentDisplay();
  if (display == EGL_NO_DISPLAY || eglGetCurrentContext() == EGL_NO_CONTEXT ||
      !epoxy_has_egl_extension(display, "EGL_EXT_image_dma_buf_import")) {
    return -10;
  }
  const uint32_t drm_format = drm_format_for_cef(frame->format);
  if (frame->plane_count != 1 || frame->fds[0] < 0 || drm_format == 0 ||
      frame->coded_width <= 0 || frame->coded_height <= 0 ||
      frame->visible_width <= 0 || frame->visible_height <= 0 ||
      frame->offsets[0] > INT_MAX || frame->strides[0] > INT_MAX) {
    return -11;
  }

  EGLint attributes[32];
  size_t attribute_count = 0;
#define APPEND_EGL_ATTRIBUTE(key, value)                                       \
  do {                                                                         \
    attributes[attribute_count++] = (key);                                     \
    attributes[attribute_count++] = (value);                                   \
  } while (0)
  APPEND_EGL_ATTRIBUTE(EGL_WIDTH, frame->coded_width);
  APPEND_EGL_ATTRIBUTE(EGL_HEIGHT, frame->coded_height);
  APPEND_EGL_ATTRIBUTE(EGL_LINUX_DRM_FOURCC_EXT, (EGLint)drm_format);
  APPEND_EGL_ATTRIBUTE(EGL_DMA_BUF_PLANE0_FD_EXT, frame->fds[0]);
  APPEND_EGL_ATTRIBUTE(EGL_DMA_BUF_PLANE0_OFFSET_EXT,
                       (EGLint)frame->offsets[0]);
  APPEND_EGL_ATTRIBUTE(EGL_DMA_BUF_PLANE0_PITCH_EXT, (EGLint)frame->strides[0]);
  if (epoxy_has_egl_extension(display,
                              "EGL_EXT_image_dma_buf_import_modifiers")) {
    APPEND_EGL_ATTRIBUTE(EGL_DMA_BUF_PLANE0_MODIFIER_LO_EXT,
                         (EGLint)(frame->modifier & 0xffffffffu));
    APPEND_EGL_ATTRIBUTE(EGL_DMA_BUF_PLANE0_MODIFIER_HI_EXT,
                         (EGLint)(frame->modifier >> 32));
  }
  attributes[attribute_count] = EGL_NONE;
#undef APPEND_EGL_ATTRIBUTE

  EGLImageKHR image = eglCreateImageKHR(
      display, EGL_NO_CONTEXT, EGL_LINUX_DMA_BUF_EXT, NULL, attributes);
  if (image == EGL_NO_IMAGE_KHR) {
    return -12;
  }

  GLint previous_texture = 0;
  GLint previous_read_framebuffer = 0;
  GLint previous_draw_framebuffer = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &previous_texture);
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &previous_read_framebuffer);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &previous_draw_framebuffer);

  GLuint source_texture = 0;
  GLuint read_framebuffer = 0;
  GLuint draw_framebuffer = 0;
  glGenTextures(1, &source_texture);
  glBindTexture(GL_TEXTURE_2D, source_texture);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, image);

  glGenFramebuffers(1, &read_framebuffer);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, read_framebuffer);
  glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                         GL_TEXTURE_2D, source_texture, 0);
  glGenFramebuffers(1, &draw_framebuffer);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw_framebuffer);
  glFramebufferTexture2D(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                         GL_TEXTURE_2D, self->gl_name, 0);

  int32_t status = 0;
  if (glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) !=
          GL_FRAMEBUFFER_COMPLETE ||
      glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER) !=
          GL_FRAMEBUFFER_COMPLETE) {
    status = -13;
  } else {
    const GLint source_x0 = frame->visible_x;
    const GLint source_x1 = frame->visible_x + frame->visible_width;
    const GLint source_y0 = frame->visible_y;
    const GLint source_y1 = frame->visible_y + frame->visible_height;
    glBlitFramebuffer(source_x0, source_y0, source_x1, source_y1, 0, 0,
                      (GLint)destination_width, (GLint)destination_height,
                      GL_COLOR_BUFFER_BIT, GL_NEAREST);
    glFinish();
    if (glGetError() != GL_NO_ERROR) {
      status = -14;
    }
  }

  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)previous_read_framebuffer);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)previous_draw_framebuffer);
  glBindTexture(GL_TEXTURE_2D, (GLuint)previous_texture);
  glDeleteFramebuffers(1, &read_framebuffer);
  glDeleteFramebuffers(1, &draw_framebuffer);
  glDeleteTextures(1, &source_texture);
  eglDestroyImageKHR(display, image);
  return status;
}

static int32_t
copy_dma_buf_during_cef_callback(const zikzak_dma_buf_frame *frame,
                                 void *user_data) {
  ZikzakNativeTextureBridge *bridge = user_data;
  if (bridge == NULL || bridge->texture == NULL || frame == NULL) {
    return -30;
  }
  ZikzakNativeTexture *texture = bridge->texture;
  g_mutex_lock(&texture->gl_mutex);
  if (texture->copy_context == EGL_NO_CONTEXT || texture->gl_name == 0 ||
      texture->allocated_width == 0 || texture->allocated_height == 0) {
    g_mutex_unlock(&texture->gl_mutex);
    texture->publish_dma_buf_result(frame->generation, -31);
    mark_texture_frame_available(bridge);
    return -31;
  }

  const EGLDisplay previous_display = eglGetCurrentDisplay();
  const EGLContext previous_context = eglGetCurrentContext();
  const EGLSurface previous_draw = eglGetCurrentSurface(EGL_DRAW);
  const EGLSurface previous_read = eglGetCurrentSurface(EGL_READ);
  const EGLenum previous_api = eglQueryAPI();
  if (!eglBindAPI(texture->copy_api) ||
      !eglMakeCurrent(texture->copy_display, texture->copy_surface,
                      texture->copy_surface, texture->copy_context)) {
    eglBindAPI(previous_api);
    g_mutex_unlock(&texture->gl_mutex);
    texture->publish_dma_buf_result(frame->generation, -32);
    mark_texture_frame_available(bridge);
    return -32;
  }

  const int32_t status = copy_dma_buf_to_flutter_texture(
      texture, frame, texture->allocated_width, texture->allocated_height);
  if (status == 0) {
    texture->imported_dma_buf_generation = frame->generation;
  }
  texture->publish_dma_buf_result(frame->generation, status);

  if (previous_display != EGL_NO_DISPLAY) {
    eglMakeCurrent(previous_display, previous_draw, previous_read,
                   previous_context);
  } else {
    eglMakeCurrent(texture->copy_display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                   EGL_NO_CONTEXT);
  }
  eglBindAPI(previous_api);
  g_mutex_unlock(&texture->gl_mutex);
  mark_texture_frame_available(bridge);
  return status;
}

static gboolean zikzak_native_texture_populate(FlTextureGL *texture,
                                               uint32_t *target, uint32_t *name,
                                               uint32_t *width,
                                               uint32_t *height,
                                               GError **error) {
  ZikzakNativeTexture *self = (ZikzakNativeTexture *)texture;
  const uint32_t next_width = self->get_width();
  const uint32_t next_height = self->get_height();
  const uint64_t generation = self->get_generation();
  if (next_width == 0 || next_height == 0 ||
      next_width > G_MAXSIZE / 4 / next_height) {
    g_set_error(error, zikzak_native_texture_error_quark(), 1,
                "Rust supplied invalid Flutter texture dimensions");
    return FALSE;
  }
  g_mutex_lock(&self->gl_mutex);

  if (self->gl_name == 0) {
    glGenTextures(1, &self->gl_name);
    glBindTexture(GL_TEXTURE_2D, self->gl_name);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  } else {
    glBindTexture(GL_TEXTURE_2D, self->gl_name);
  }

  const gboolean storage_changed = self->allocated_width != next_width ||
                                   self->allocated_height != next_height;
  if (storage_changed) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, (GLsizei)next_width,
                 (GLsizei)next_height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    self->allocated_width = next_width;
    self->allocated_height = next_height;
    self->uploaded_generation = 0;
    self->imported_dma_buf_generation = 0;
  }

  ensure_dma_buf_copy_context(self);
  const gboolean has_browser_pixels = self->imported_dma_buf_generation > 0;
  if (!has_browser_pixels && self->uploaded_generation != generation) {
    const size_t byte_length = (size_t)next_width * next_height * 4;
    if (byte_length > self->pixel_capacity) {
      uint8_t *replacement = g_try_realloc(self->pixels, byte_length);
      if (replacement == NULL) {
        g_set_error(error, zikzak_native_texture_error_quark(), 2,
                    "Unable to allocate Flutter texture test pixels");
        g_mutex_unlock(&self->gl_mutex);
        return FALSE;
      }
      self->pixels = replacement;
      self->pixel_capacity = byte_length;
    }
    const int32_t render_status = self->render_frame(
        self->pixels, byte_length, next_width, next_height, generation);
    if (render_status != 0) {
      g_set_error(error, zikzak_native_texture_error_quark(), 3,
                  "Rust texture rendering failed with status %d",
                  render_status);
      g_mutex_unlock(&self->gl_mutex);
      return FALSE;
    }
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, (GLsizei)next_width,
                 (GLsizei)next_height, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                 self->pixels);
    self->uploaded_generation = generation;
  }

  const GLenum gl_error = glGetError();
  if (gl_error != GL_NO_ERROR) {
    g_set_error(error, zikzak_native_texture_error_quark(), 4,
                "OpenGL texture upload failed with error 0x%x", gl_error);
    g_mutex_unlock(&self->gl_mutex);
    return FALSE;
  }

  // Flutter calls populate with its GL context current. Publish the texture
  // name and share-context handles to Rust for the upcoming DMA-BUF copy path.
  self->publish_gl_state(self->gl_name, next_width, next_height,
                         (uintptr_t)eglGetCurrentDisplay(),
                         (uintptr_t)eglGetCurrentContext());

  *target = GL_TEXTURE_2D;
  *name = self->gl_name;
  *width = next_width;
  *height = next_height;
  g_mutex_unlock(&self->gl_mutex);
  return TRUE;
}

static void zikzak_native_texture_dispose(GObject *object) {
  ZikzakNativeTexture *self = (ZikzakNativeTexture *)object;
  g_mutex_lock(&self->gl_mutex);
  if (self->copy_display != EGL_NO_DISPLAY &&
      self->copy_context != EGL_NO_CONTEXT) {
    eglDestroyContext(self->copy_display, self->copy_context);
  }
  self->copy_display = EGL_NO_DISPLAY;
  self->copy_context = EGL_NO_CONTEXT;
  self->copy_surface = EGL_NO_SURFACE;
  g_clear_pointer(&self->pixels, g_free);
  self->pixel_capacity = 0;
  // The Flutter GL context is not guaranteed to be current during disposal.
  // Its share group reclaims the texture name when the engine is destroyed.
  self->gl_name = 0;
  g_mutex_unlock(&self->gl_mutex);
  G_OBJECT_CLASS(zikzak_native_texture_parent_class)->dispose(object);
}

static void zikzak_native_texture_finalize(GObject *object) {
  ZikzakNativeTexture *self = (ZikzakNativeTexture *)object;
  g_mutex_clear(&self->gl_mutex);
  G_OBJECT_CLASS(zikzak_native_texture_parent_class)->finalize(object);
}

static void zikzak_native_texture_class_init(ZikzakNativeTextureClass *klass) {
  G_OBJECT_CLASS(klass)->dispose = zikzak_native_texture_dispose;
  G_OBJECT_CLASS(klass)->finalize = zikzak_native_texture_finalize;
  FL_TEXTURE_GL_CLASS(klass)->populate = zikzak_native_texture_populate;
}

static void zikzak_native_texture_init(ZikzakNativeTexture *self) {
  g_mutex_init(&self->gl_mutex);
  self->copy_display = EGL_NO_DISPLAY;
  self->copy_context = EGL_NO_CONTEXT;
  self->copy_surface = EGL_NO_SURFACE;
}

static gboolean load_symbol(GModule *module, const gchar *name,
                            gpointer *destination) {
  if (g_module_symbol(module, name, destination)) {
    return TRUE;
  }
  g_warning("Unable to load %s from Rust native asset: %s", name,
            g_module_error());
  return FALSE;
}

static gchar *native_asset_path(void) {
  g_autoptr(GError) error = NULL;
  g_autofree gchar *executable = g_file_read_link("/proc/self/exe", &error);
  if (executable == NULL) {
    g_warning("Unable to resolve the runner executable: %s", error->message);
    return NULL;
  }
  g_autofree gchar *directory = g_path_get_dirname(executable);
  return g_build_filename(directory, "lib", "libzikzak_browser_native.so",
                          NULL);
}

static void mark_texture_frame_available(void *user_data) {
  ZikzakNativeTextureBridge *bridge = user_data;
  if (bridge == NULL || bridge->registrar == NULL || bridge->texture == NULL) {
    return;
  }
  fl_texture_registrar_mark_texture_frame_available(
      bridge->registrar, FL_TEXTURE(bridge->texture));
}

ZikzakNativeTextureBridge *zikzak_native_texture_bridge_new(FlView *view) {
  g_return_val_if_fail(FL_IS_VIEW(view), NULL);

  g_autofree gchar *asset_path = native_asset_path();
  if (asset_path == NULL) {
    return NULL;
  }
  GModule *module =
      g_module_open(asset_path, G_MODULE_BIND_LAZY | G_MODULE_BIND_LOCAL);
  if (module == NULL) {
    g_warning("Unable to open Rust native asset at %s: %s", asset_path,
              g_module_error());
    return NULL;
  }

  ZikzakAttachFn attach = NULL;
  ZikzakDetachFn detach = NULL;
  ZikzakDimensionFn get_width = NULL;
  ZikzakDimensionFn get_height = NULL;
  ZikzakGenerationFn get_generation = NULL;
  ZikzakRenderFrameFn render_frame = NULL;
  ZikzakPublishGlStateFn publish_gl_state = NULL;
  ZikzakPublishDmaBufResultFn publish_dma_buf_result = NULL;
  ZikzakDmaBufCopyAttachFn attach_dma_buf_copy = NULL;
  ZikzakDmaBufCopyDetachFn detach_dma_buf_copy = NULL;
  if (!load_symbol(module, "zikzak_flutter_texture_attach",
                   (gpointer *)&attach) ||
      !load_symbol(module, "zikzak_flutter_texture_detach",
                   (gpointer *)&detach) ||
      !load_symbol(module, "zikzak_flutter_texture_width",
                   (gpointer *)&get_width) ||
      !load_symbol(module, "zikzak_flutter_texture_height",
                   (gpointer *)&get_height) ||
      !load_symbol(module, "zikzak_flutter_texture_generation",
                   (gpointer *)&get_generation) ||
      !load_symbol(module, "zikzak_flutter_texture_render_test_frame",
                   (gpointer *)&render_frame) ||
      !load_symbol(module, "zikzak_flutter_texture_publish_gl_state",
                   (gpointer *)&publish_gl_state) ||
      !load_symbol(module, "zikzak_flutter_texture_publish_dma_buf_result",
                   (gpointer *)&publish_dma_buf_result) ||
      !load_symbol(module, "zikzak_cef_dma_buf_copy_attach",
                   (gpointer *)&attach_dma_buf_copy) ||
      !load_symbol(module, "zikzak_cef_dma_buf_copy_detach",
                   (gpointer *)&detach_dma_buf_copy)) {
    g_module_close(module);
    return NULL;
  }

  ZikzakNativeTextureBridge *bridge = g_new0(ZikzakNativeTextureBridge, 1);
  bridge->native_module = module;
  bridge->detach = detach;
  bridge->detach_dma_buf_copy = detach_dma_buf_copy;
  bridge->texture = g_object_new(zikzak_native_texture_get_type(), NULL);
  bridge->texture->get_width = get_width;
  bridge->texture->get_height = get_height;
  bridge->texture->get_generation = get_generation;
  bridge->texture->render_frame = render_frame;
  bridge->texture->publish_gl_state = publish_gl_state;
  bridge->texture->publish_dma_buf_result = publish_dma_buf_result;

  FlEngine *engine = fl_view_get_engine(view);
  bridge->registrar = g_object_ref(fl_engine_get_texture_registrar(engine));
  if (!fl_texture_registrar_register_texture(bridge->registrar,
                                             FL_TEXTURE(bridge->texture))) {
    g_warning("Unable to register the Rust-backed Flutter GL texture");
    zikzak_native_texture_bridge_free(bridge);
    return NULL;
  }

  bridge->texture_id = fl_texture_get_id(FL_TEXTURE(bridge->texture));
  if (attach(bridge->texture_id, mark_texture_frame_available, bridge) != 0) {
    g_warning("Rust rejected the Flutter GL texture registration");
    zikzak_native_texture_bridge_free(bridge);
    return NULL;
  }
  if (attach_dma_buf_copy(copy_dma_buf_during_cef_callback, bridge) != 0) {
    g_warning("Rust rejected the CEF DMA-BUF copy callback registration");
    zikzak_native_texture_bridge_free(bridge);
    return NULL;
  }
  mark_texture_frame_available(bridge);
  return bridge;
}

void zikzak_native_texture_bridge_free(ZikzakNativeTextureBridge *bridge) {
  if (bridge == NULL) {
    return;
  }
  if (bridge->detach_dma_buf_copy != NULL) {
    bridge->detach_dma_buf_copy(bridge);
  }
  if (bridge->detach != NULL && bridge->texture_id > 0) {
    bridge->detach(bridge->texture_id);
  }
  if (bridge->registrar != NULL && bridge->texture != NULL) {
    fl_texture_registrar_unregister_texture(bridge->registrar,
                                            FL_TEXTURE(bridge->texture));
  }
  g_clear_object(&bridge->texture);
  g_clear_object(&bridge->registrar);
  if (bridge->native_module != NULL) {
    g_module_close(bridge->native_module);
  }
  g_free(bridge);
}
