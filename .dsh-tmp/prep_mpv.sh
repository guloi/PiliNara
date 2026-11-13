cd /c/Users/fk/PiliNara/.dsh-tmp/t/mpv
git checkout -- . 2>/dev/null
git apply "C:/Users/fk/PiliNara/third_party/libmpv-android-video-build/buildscripts/patches/mpv/android-gl-hdr.patch"
grep -n "eglCreateWindowSurface\|EGL_GL_COLORSPACE\|strstr\|include <string.h>" video/out/opengl/context_android.c
echo ==== 
sed -n "/p->egl_surface = eglCreateWindowSurface/,+8p" video/out/opengl/context_android.c
echo ====
grep -n "define EGL_\|android_gl_is_hdr\|android_gl_supports" video/out/opengl/context_android.c