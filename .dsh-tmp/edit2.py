
import io, sys
p = r"C:\Users\fk\PiliNara\.dsh-tmp\t\mpv\video\out\opengl\context_android.c"
s = io.open(p, encoding="utf-8").read()

old1 = """#ifndef ADATASPACE_BT2020_PQ
#define ADATASPACE_BT2020_PQ 163971072
#endif
"""
new1 = old1 + """
// eglCreateWindowSurface 的 EGL_GL_COLORSPACE_KHR 属性（EGL_EXT_gl_colorspace_bt2020_pq）。
// 这一步很关键：EGL 驱动会给每次 eglSwapBuffers 入队的缓冲打上自己的 dataspace，
// 只调 ANativeWindow_setBuffersDataSpace 的话会被 EGL 打回 sRGB，表现为
// 「亮度对了但画面发灰」（PQ 数据被当 SDR 解释）。
#ifndef EGL_GL_COLORSPACE_KHR
#define EGL_GL_COLORSPACE_KHR 0x309D
#endif

#ifndef EGL_GL_COLORSPACE_BT2020_PQ_EXT
#define EGL_GL_COLORSPACE_BT2020_PQ_EXT 0x3340
#endif
"""
assert old1 in s
s = s.replace(old1, new1, 1)

old2 = """struct android_gl_cb {"""
new2 = """// EGL_EXT_gl_colorspace_bt2020_pq 是否可用（Adreno 一般有，部分 Mali 没有）。
static bool android_gl_supports_bt2020pq(EGLDisplay display)
{
    const char *exts = eglQueryString(display, EGL_EXTENSIONS);
    return exts && strstr(exts, "EGL_EXT_gl_colorspace_bt2020_pq");
}

struct android_gl_cb {"""
assert old2 in s
s = s.replace(old2, new2, 1)

old3 = """    p->egl_surface = eglCreateWindowSurface(p->egl_display, config,
                                    (EGLNativeWindowType)native_window, NULL);

    if (p->egl_surface == EGL_NO_SURFACE) {
        MP_FATAL(ctx, "Could not create EGL surface!\\n");
        goto fail;
    }
"""
new3 = """    const EGLint hdr_cs_attribs[] = {
        EGL_GL_COLORSPACE_KHR, EGL_GL_COLORSPACE_BT2020_PQ_EXT,
        EGL_NONE,
    };
    bool hdr_cs = android_gl_is_hdr(ctx) &&
                  android_gl_supports_bt2020pq(p->egl_display);
    p->egl_surface = eglCreateWindowSurface(p->egl_display, config,
                                    (EGLNativeWindowType)native_window,
                                    hdr_cs ? hdr_cs_attribs : NULL);
    if (p->egl_surface == EGL_NO_SURFACE && hdr_cs) {
        // 驱动声称支持但建面失败时退回默认色彩空间，至少能出画。
        MP_WARN(ctx, "Android/EGL: 指定 BT.2020/PQ 色彩空间失败，退回默认\\n");
        p->egl_surface = eglCreateWindowSurface(p->egl_display, config,
                                    (EGLNativeWindowType)native_window, NULL);
    }

    if (p->egl_surface == EGL_NO_SURFACE) {
        MP_FATAL(ctx, "Could not create EGL surface!\\n");
        goto fail;
    }
"""
assert old3 in s
s = s.replace(old3, new3, 1)

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("patched")
