set -e
cd /c/Users/fk/PiliNara/third_party/libmpv-android-video-build
git checkout -B gl-hdr
git add -A buildscripts/patches
git commit -q -F - <<'MSG'
feat(gl): gpu-next + OpenGL 输出 10bit BT.2020/PQ

Vulkan WSI 在 Android 上只给线性缓冲，全屏/横屏旋转图层时 SF 只能退回
CLIENT 合成，PQ 画面被画进 SDR client target，表现为「暗了非常多」。
EGL/gralloc 的窗口缓冲是 UBWC 压缩的，HWC 可以直接合成（含旋转）。

- libplacebo: OpenGL 交换链补 colorspace_hint，start_frame 用调用方给的
  色彩空间而不是写死 pl_color_space_monitor。
- mpv: Android/EGL context 在 HDR 时挑 10bit EGLConfig，并把窗口 dataspace
  声明成 BT.2020/PQ（init 与每次 resize 后都要重发，setBuffersGeometry 会
  把 dataspace 复位），同时提供 preferred_csp = pl_color_space_hdr10。
MSG
git --no-pager log --oneline -2
TOKEN=$(cd /c/Users/fk/PiliNara && git config --local remote.origin.url | sed -E 's#.*guloi:([^@]+)@.*#\1#')
git push "http://guloi:$TOKEN@127.0.0.1:8765/Guloi/libmpv-android-video-build.git" gl-hdr:gl-hdr 2>&1 | tail -5
