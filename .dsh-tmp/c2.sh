cd /c/Users/fk/PiliNara/third_party/libmpv-android-video-build
git status --short
cp /c/Users/fk/PiliNara/.dsh-tmp/android-gl-hdr.new.patch buildscripts/patches/mpv/android-gl-hdr.patch
git add -A
git -c user.name=guloi -c user.email=soiaii@163.com commit -m 'fix(gl): EGL 面按 BT.2020/PQ 色彩空间创建，避免 PQ 被当 SDR 发灰'
git log --oneline -3