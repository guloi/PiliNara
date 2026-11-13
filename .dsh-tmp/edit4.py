
import io
p = r"C:\Users\fk\PiliNara\.dsh-tmp\t\mpv\video\out\opengl\context_android.c"
s = io.open(p, encoding="utf-8").read()
old = """    if (p->egl_surface == EGL_NO_SURFACE && hdr_cs) {"""
new = """    if (p->egl_surface != EGL_NO_SURFACE && hdr_cs) {
        MP_VERBOSE(ctx, "Android/EGL: 面色彩空间 = BT.2020/PQ"
                   "（EGL_EXT_gl_colorspace_bt2020_pq）\\n");
    }
    if (p->egl_surface == EGL_NO_SURFACE && hdr_cs) {"""
assert old in s
s = s.replace(old, new, 1)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("ok")
