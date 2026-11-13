set -e
cd /c/Users/fk/PiliNara
rm -rf .dsh-tmp/t
mkdir -p .dsh-tmp/t/lp/src/opengl .dsh-tmp/t/mpv/video/out/opengl
cp .dsh-tmp/lp/opengl_swapchain.c .dsh-tmp/t/lp/src/opengl/swapchain.c
cp .dsh-tmp/mpvsrc/video_out_opengl_context_android.c .dsh-tmp/t/mpv/video/out/opengl/context_android.c
cd .dsh-tmp/t/lp && git init -q . && git add -A && git -c user.email=a@b -c user.name=a commit -qm x
git apply --check -v "$OLDPWD/third_party/libmpv-android-video-build/buildscripts/patches/libplacebo/android-gl-hdr.patch" && echo "LP CHECK OK"
cd ../mpv && git init -q . && git add -A && git -c user.email=a@b -c user.name=a commit -qm x
git apply --check -v "$OLDPWD/third_party/libmpv-android-video-build/buildscripts/patches/mpv/android-gl-hdr.patch" && echo "MPV CHECK OK"
