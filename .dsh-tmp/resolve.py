import sys, io

# usage: python resolve.py <file> <spec>
# spec: comma separated per-hunk actions: o (ours), t (theirs), b (ours+theirs), or index-based via file
path = sys.argv[1]
spec = sys.argv[2] if len(sys.argv) > 2 else ''
acts = [a.strip() for a in spec.split(',') if a.strip()]

text = io.open(path, encoding='utf-8', newline='').read()
lines = text.split('\n')

out = []
i = 0
hi = 0
while i < len(lines):
    line = lines[i]
    if line.startswith('<<<<<<<'):
        ours = []
        theirs = []
        j = i + 1
        while not lines[j].startswith('======='):
            ours.append(lines[j]); j += 1
        j += 1
        while not lines[j].startswith('>>>>>>>'):
            theirs.append(lines[j]); j += 1
        act = acts[hi] if hi < len(acts) else 'x'
        hi += 1
        if act == 'o':
            out.extend(ours)
        elif act == 't':
            out.extend(theirs)
        elif act == 'b':
            out.extend(ours); out.extend(theirs)
        elif act == 'x':
            raise SystemExit('unresolved hunk %d in %s' % (hi, path))
        i = j + 1
        continue
    out.append(line)
    i += 1

io.open(path, 'w', encoding='utf-8', newline='').write('\n'.join(out))
print('resolved %d hunks in %s' % (hi, path))
