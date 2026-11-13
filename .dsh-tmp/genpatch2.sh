cd /c/Users/fk/PiliNara/.dsh-tmp/t/mpv
git diff > /c/Users/fk/PiliNara/.dsh-tmp/android-gl-hdr.new.patch
wc -c /c/Users/fk/PiliNara/.dsh-tmp/android-gl-hdr.new.patch
grep -rn "include <string.h>" video/out/opengl/../../common/common.h 2>/dev/null | head -3