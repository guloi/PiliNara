import io
p = r"C:\Users\fk\PiliNara\lib\\pages\\video\\introduction\\ugc\\view.dart"
lines = io.open(p, encoding="utf-8").read().split("\n")
# 1-based 303..318 -> 0-based 302..317 : add two spaces
for i in range(302, 318):
    lines[i] = "  " + lines[i]
io.open(p, "w", encoding="utf-8", newline="").write("\n".join(lines))
print("done")
