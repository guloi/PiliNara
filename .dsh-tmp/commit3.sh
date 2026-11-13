cd /c/Users/fk/PiliNara
git add docs/hdr.md lib/pages/setting/models/gpu_next_settings.dart lib/pages/setting/models/hdr_settings.dart lib/plugin/pl_player/controller.dart lib/utils/storage_key.dart lib/utils/storage_pref.dart
cat > .dsh-tmp/msg2.txt <<'EOF'
feat(hdr): 新增「SDR 走 Vulkan / HDR 走 OpenGL」分流开关

Vulkan 交换链在 Android 上只能拿到线性缓冲，全屏 / 横屏旋转 10bit HDR 图层时
SurfaceFlinger 会退回 CLIENT（GPU）合成，PQ 被画进 SDR 的 client target；EGL 的
窗口缓冲来自 gralloc（UBWC），HWC 能直接合成。与其让用户二选一，不如按片源分流。

- 新增 gpuNextSplitHdr 设置项（默认 gpu-next 页里，默认关）
- _splitHdrAcrossBackends：HDR / 杜比视界固定 gpuNextGl（profile 5 关了软解仍交给
  MediaCodec），SDR 纹理固定 gpuNext（Vulkan），失败各自回退
- 开启时优先于「HDR / 杜比视界时切回 MediaCodec」，设置页文案与 HDR 设置页摘要同步
- docs/hdr.md 7.8 补充分流开关的说明
EOF
git commit -F .dsh-tmp/msg2.txt && git log --oneline -2