set -e
cd /c/Users/fk/PiliNara/.dsh-tmp/t/mpv
git apply --check -v "C:/Users/fk/PiliNara/third_party/libmpv-android-video-build/buildscripts/patches/mpv/android-gl-hdr.patch" && echo "MPV CHECK OK"
