cd /c/Users/fk/PiliNara
git add docs/hdr.md lib/plugin/pl_player/controller.dart lib/plugin/pl_player/models/hdr_config.dart
cat > .dsh-tmp/msg.txt <<'EOF'
feat(hdr): gpu-next 改走 OpenGL/EGL 输出 10bit BT.2020/PQ

全屏 / 横屏时 HDR 画面「暗了非常多」的根因不是 10bit 或 PQ：SurfaceFlinger
dump 里 mediacodec 直通的 Y_CBCR_420_TP10_UBWC + BT2020_PQ 图层带着 90° 旋转
仍然是 DEVICE/DEVICE，而 gpu-next Vulkan 出的是线性 RGBA_1010102（modifier 0、
compressed: false），需要旋转时被降级成 CLIENT 合成，PQ 被画进 SDR 的 client
target（DCI-P3 sRGB），RenderEngine 又不做色调映射。半屏不旋转，所以正常。

Android 的 EGL 窗口缓冲来自 gralloc、是 UBWC 压缩的，HWC 可以直接合成（含旋转）。
配合 libmpv 新加的 GL HDR 补丁（libplacebo OpenGL 交换链支持 colorspace_hint，
mpv 的 android GL context 选 10bit EGLConfig 并声明 BT.2020/PQ dataspace），
gpu-next + OpenGL 也能输出 10bit HDR。

- HdrBackend.gpuNextGl 也算 supportsHdrOutput，窗口 HDR 与 target-colorspace-hint
  按 HDR 处理；android-vulkan-hdr 选项对 gpu-api=opengl 同样置 yes
- _isVulkanHdrOutput 改名 _isGpuNextHdrOutput，覆盖 Vulkan 与 OpenGL 两条 HDR 路径
- 新增 vo-configured 自检：GL 路径建不起 VO（libmpv 没有补丁 / 设备不支持）时
  回退到 gpu（SDR），避免停在有声音的黑屏
- docs/hdr.md 新增 7.8，记录 SF dump 证据链与试用方法
EOF
git commit -F .dsh-tmp/msg.txt
git log --oneline -2