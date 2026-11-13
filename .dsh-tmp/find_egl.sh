ls /c/Users/fk/AppData/Local/Android/Sdk/ndk 2>/dev/null | head
for d in /c/Users/fk/AppData/Local/Android/Sdk/ndk/*/; do echo "== $d"; done 2>/dev/null | head
grep -rn "EGL_GL_COLORSPACE_BT2020_PQ_EXT" /c/Users/fk/AppData/Local/Android/Sdk/ndk 2>/dev/null | head -5