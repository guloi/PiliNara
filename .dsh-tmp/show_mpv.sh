set -e
cd /c/Users/fk/PiliNara/.dsh-tmp/t/mpv
git apply "C:/Users/fk/PiliNara/third_party/libmpv-android-video-build/buildscripts/patches/mpv/android-gl-hdr.patch"
sed -n '1,40p' video/out/opengl/context_android.c
echo ======
sed -n '/static bool android_is_hdr/,/^}/p;/android_gl_refine_config/,/^}/p' video/out/opengl/context_android.c | head -80
