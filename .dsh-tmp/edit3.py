
import io
p = r"C:\Users\fk\PiliNara\.dsh-tmp\t\mpv\video\out\opengl\context_android.c"
s = io.open(p, encoding="utf-8").read()
old = "#include <dlfcn.h>\n"
new = "#include <dlfcn.h>\n#include <string.h>\n"
assert old in s
s = s.replace(old, new, 1)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("ok")
