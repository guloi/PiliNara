import sys, re
for path in sys.argv[1:]:
    lines = open(path, encoding='utf-8').read().split('\n')
    i = 0
    n = 0
    while i < len(lines):
        if lines[i].startswith('<<<<<<<'):
            n += 1
            start = i
            j = i
            while j < len(lines) and not lines[j].startswith('>>>>>>>'):
                j += 1
            print('=' * 70)
            print(f'--- {path}:{start+1} (hunk {n}) ---')
            lo = max(0, start - 6)
            for k in range(lo, min(len(lines), j + 7)):
                print(lines[k])
            i = j
        i += 1
