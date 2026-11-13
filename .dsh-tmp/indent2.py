import io
p = r"C:\Users\fk\PiliNara\lib\\pages\\video\\introduction\\ugc\\view.dart"
lines = io.open(p, encoding="utf-8").read().split("\n")
start = next(i for i, l in enumerate(lines) if l.startswith("    if (videoDetail.descV2"))
end = next(i for i in range(start, len(lines)) if lines[i] == "    ];")
for i in range(start, end):
    if lines[i].strip():
        lines[i] = "  " + lines[i]
io.open(p, "w", encoding="utf-8", newline="").write("\n".join(lines))
print("reindented", start + 1, end)
