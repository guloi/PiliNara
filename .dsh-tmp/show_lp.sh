set -e
cd /c/Users/fk/PiliNara/.dsh-tmp/t/lp
git apply "C:/Users/fk/PiliNara/third_party/libmpv-android-video-build/buildscripts/patches/libplacebo/android-gl-hdr.patch"
sed -n '20,40p;150,200p;265,290p' src/opengl/swapchain.c
