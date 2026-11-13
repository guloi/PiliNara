
import difflib, os

ROOT = r"C:\Users\fk\PiliNara"
LPSRC = os.path.join(ROOT, r".dsh-tmp\lp\opengl_swapchain.c")
MPVSRC = os.path.join(ROOT, r".dsh-tmp\mpvsrc\video_out_opengl_context_android.c")

def patch_for(a_path, b_path, old, new):
    diff = difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                fromfile="a/" + a_path, tofile="b/" + b_path, n=3)
    return "".join(diff)

def replace_once(text, anchor, repl, name):
    assert text.count(anchor) == 1, (name, text.count(anchor))
    return text.replace(anchor, repl)

# ---------------- libplacebo ----------------
src = open(LPSRC, "r", encoding="utf-8").read()
new = src
new = replace_once(new, "    pl_tex fb;\n    bool frame_started;\n",
"""    pl_tex fb;
    bool frame_started;

    // PiliNara: Android/EGL 没法通过平台 API 声明 HDR，改为由调用方
    // （mpv 的 vo_gpu_next）用 pl_swapchain_colorspace_hint 告知要以什么
    // 色彩空间编码输出；这里只保存，真正生效在 gl_sw_start_frame。
    struct pl_color_space hint;
    bool has_hint;
""", "lp-priv")

new = replace_once(new, "static bool gl_sw_resize(pl_swapchain sw, int *width, int *height)\n",
"""static void gl_sw_colorspace_hint(pl_swapchain sw,
                                  const struct pl_color_space *csp)
{
    struct priv *p = PL_PRIV(sw);

    pl_mutex_lock(&p->lock);
    if (csp) {
        p->hint = *csp;
        p->has_hint = true;
    } else {
        p->has_hint = false;
    }
    pl_mutex_unlock(&p->lock);
}

static bool gl_sw_resize(pl_swapchain sw, int *width, int *height)
""", "lp-hintfn")

new = replace_once(new, "        .color_space = pl_color_space_monitor,\n",
"        .color_space = p->has_hint ? p->hint : pl_color_space_monitor,\n", "lp-cs")

new = replace_once(new,
"""    .latency      = gl_sw_latency,
    .resize       = gl_sw_resize,
""",
"""    .latency         = gl_sw_latency,
    .colorspace_hint = gl_sw_colorspace_hint,
    .resize          = gl_sw_resize,
""", "lp-fns")
# 对齐其余成员，避免风格突兀
new = new.replace("""    .destroy      = gl_sw_destroy,
    .latency         = gl_sw_latency,""", """    .destroy         = gl_sw_destroy,
    .latency         = gl_sw_latency,""")
new = new.replace("""    .start_frame  = gl_sw_start_frame,
    .submit_frame = gl_sw_submit_frame,
    .swap_buffers = gl_sw_swap_buffers,""", """    .start_frame     = gl_sw_start_frame,
    .submit_frame    = gl_sw_submit_frame,
    .swap_buffers    = gl_sw_swap_buffers,""")

lp_patch = patch_for("src/opengl/swapchain.c", "src/opengl/swapchain.c", src, new)

# ---------------- mpv gl android context ----------------
m = open(MPVSRC, "r", encoding="utf-8").read()
n = m
n = replace_once(n, "#include <EGL/egl.h>\n#include <EGL/eglext.h>\n",
"""#include <dlfcn.h>

#include <android/data_space.h>
#include <android/native_window.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
""", "mpv-inc")

n = replace_once(n, """#include "video/out/android_common.h"
#include "egl_helpers.h"
#include "common/common.h"
#include "context.h"
""",
"""#include "video/out/android_common.h"
#include "egl_helpers.h"
#include "common/common.h"
#include "context.h"

// PiliNara: Android/EGL（gpu-next + gpu-api=opengl）下的 HDR 输出。
//
// Vulkan WSI 在 Android 上只给线性（没压缩）缓冲，全屏/横屏需要旋转图层时
// SurfaceFlinger 只能退回 CLIENT（GPU）合成，PQ 画面被画进 SDR 的 client
// target，表现为「暗了非常多」。EGL/gralloc 的窗口缓冲是 UBWC 压缩的，
// HWC 可以直接合成（含旋转），所以这里把 EGL 窗口切成 10bit RGBA +
// BT.2020/PQ dataspace，再让 libplacebo 按 PQ 编码输出。
#ifndef AHARDWAREBUFFER_FORMAT_R10G10B10A2_UNORM
#define AHARDWAREBUFFER_FORMAT_R10G10B10A2_UNORM 0x2b
#endif

#ifndef ADATASPACE_BT2020_PQ
#define ADATASPACE_BT2020_PQ 163971072
#endif

// ANativeWindow_setBuffersDataSpace 是 API 28 才导出的符号，而 libmpv 以
// API 24 为最低版本编译，直接调用会让库在旧系统上加载失败，故用 dlsym 取。
typedef int32_t (*set_buffers_dataspace_fn)(ANativeWindow *window, int32_t dataSpace);

static void android_gl_set_dataspace(ANativeWindow *window, int32_t dataspace)
{
    static set_buffers_dataspace_fn fn;
    static bool resolved;
    if (!resolved) {
        resolved = true;
        fn = (set_buffers_dataspace_fn)dlsym(RTLD_DEFAULT,
                                             "ANativeWindow_setBuffersDataSpace");
    }
    if (fn)
        fn(window, dataspace);
}

// 是否按 HDR 输出，由 --android-vulkan-hdr 决定（播放器在打开 HDR /
// 杜比视界片源前设置，SDR 片源保持关闭）。
static bool android_gl_is_hdr(struct ra_ctx *ctx)
{
    return ctx->vo && ctx->vo->opts && ctx->vo->opts->android_vulkan_hdr;
}

// 告诉 vo_gpu_next 交换链的目标是 HDR10（BT.2020/PQ）。它据此把 hint 设成
// HDR10，libplacebo 才会按 PQ 编码而不是先 tone map 回 SDR。
static pl_color_space_t android_gl_preferred_csp(struct ra_ctx *ctx)
{
    if (!android_gl_is_hdr(ctx))
        return (pl_color_space_t){0};
    return pl_color_space_hdr10;
}

struct android_gl_cb {
    struct ra_ctx *ctx;
    EGLDisplay display;
};

// 在 eglChooseConfig 给的候选里优先挑 10bit 的配置。EGL_RED_SIZE 只是
// 下限，10bit 配置也会出现在列表里；一个都没有时回退 0（8bit），
// 保证画面能出，只是 PQ 会有色带。
static int android_gl_refine_config(void *user_data, EGLConfig *configs,
                                    int num_configs)
{
    struct android_gl_cb *cb = user_data;

    if (!android_gl_is_hdr(cb->ctx))
        return 0;

    for (int i = 0; i < num_configs; i++) {
        EGLint r = 0, g = 0, b = 0;
        eglGetConfigAttrib(cb->display, configs[i], EGL_RED_SIZE, &r);
        eglGetConfigAttrib(cb->display, configs[i], EGL_GREEN_SIZE, &g);
        eglGetConfigAttrib(cb->display, configs[i], EGL_BLUE_SIZE, &b);
        if (r >= 10 && g >= 10 && b >= 10) {
            MP_VERBOSE(cb->ctx, "Android/EGL: 选中 10bit EGLConfig (%d/%d/%d)\\n",
                       (int)r, (int)g, (int)b);
            return i;
        }
    }

    MP_WARN(cb->ctx, "Android/EGL: 没有 10bit 的 EGLConfig，HDR 退化成 8bit\\n");
    return 0;
}
""", "mpv-helpers")

n = replace_once(n, """    EGLConfig config;
    if (!mpegl_create_context(ctx, p->egl_display, &p->egl_context, &config))
        goto fail;
""",
"""    EGLConfig config;
    struct android_gl_cb cb = {
        .ctx = ctx,
        .display = p->egl_display,
    };
    if (!mpegl_create_context_cb(ctx, p->egl_display,
                                 (struct mpegl_cb){ .refine_config = android_gl_refine_config,
                                                    .user_data = &cb },
                                 &p->egl_context, &config))
        goto fail;
""", "mpv-create")

n = replace_once(n, "    ANativeWindow_setBuffersGeometry(native_window, 0, 0, format);\n",
"""    ANativeWindow_setBuffersGeometry(native_window, 0, 0, format);

    // setBuffersGeometry 会把 dataspace 复位成 UNKNOWN，HDR 时必须重新声明
    // BT.2020/PQ，否则系统会把 PQ 数据当 SDR 解释（画面发灰/偏暗）。
    if (android_gl_is_hdr(ctx)) {
        android_gl_set_dataspace(native_window, ADATASPACE_BT2020_PQ);
        MP_VERBOSE(ctx, "Android/EGL: 以 10bit BT.2020/PQ 输出（HDR）\\n");
    }
""", "mpv-geom")

n = replace_once(n, """    struct ra_ctx_params params = {
        .swap_buffers = android_swap_buffers,
    };
""",
"""    struct ra_ctx_params params = {
        .swap_buffers = android_swap_buffers,
        .preferred_csp = android_gl_preferred_csp,
    };
""", "mpv-params")

n = replace_once(n, """        int32_t current_format = ANativeWindow_getFormat(native_window);
        ANativeWindow_setBuffersGeometry(native_window, w, h, current_format);
""",
"""        int32_t current_format = ANativeWindow_getFormat(native_window);
        ANativeWindow_setBuffersGeometry(native_window, w, h, current_format);
        // 尺寸变化同样会复位 dataspace，HDR 时补回 BT.2020/PQ
        if (android_gl_is_hdr(ctx))
            android_gl_set_dataspace(native_window, ADATASPACE_BT2020_PQ);
""", "mpv-reconfig")

mpv_patch = patch_for("video/out/opengl/context_android.c", "video/out/opengl/context_android.c", m, n)

base = os.path.join(ROOT, r"third_party\libmpv-android-video-build\buildscripts\patches")
os.makedirs(os.path.join(base, "libplacebo"), exist_ok=True)
open(os.path.join(base, "libplacebo", "android-gl-hdr.patch"), "w", encoding="utf-8", newline="\n").write(lp_patch)
open(os.path.join(base, "mpv", "android-gl-hdr.patch"), "w", encoding="utf-8", newline="\n").write(mpv_patch)
print("libplacebo patch", len(lp_patch))
print("mpv patch", len(mpv_patch))
