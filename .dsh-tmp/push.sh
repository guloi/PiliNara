#!/bin/bash
set -u
cd /c/Users/fk/PiliNara
GH_TOKEN=$(git config --local remote.origin.url | sed -E "s#.*guloi:([^@]+)@.*#\1#")
if [ -z "$GH_TOKEN" ]; then echo "no token"; exit 1; fi
echo "token len: $(printf %s "$GH_TOKEN" | wc -c)"
git push "http://guloi:$GH_TOKEN@127.0.0.1:8765/guloi/PiliNara.git" HEAD:ds-ai-hdr 2>&1 | tail -5
git log -1 --format="local: %h %s"
