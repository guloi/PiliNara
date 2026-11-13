#!/bin/bash
set -u
cd /c/Users/fk/PiliNara
GH_TOKEN=$(git config --local remote.origin.url | sed -E "s#.*guloi:([^@]+)@.*#\1#")
URL="http://guloi:$GH_TOKEN@127.0.0.1:8765/guloi/PiliNara.git"
# 路线 A 的提交留在本地分支备查，分支本身回退到 75c0150c1
git branch -f routeA-mediacodec-landscape 41bfb443d 2>/dev/null || true
git reset --hard 75c0150c1
git log -1 --format="HEAD=%h %s"
git status --porcelain | head
git fetch "$URL" ds-ai-hdr >/dev/null 2>&1
git push --force-with-lease=ds-ai-hdr:41bfb443d "$URL" HEAD:ds-ai-hdr 2>&1 | tail -3
