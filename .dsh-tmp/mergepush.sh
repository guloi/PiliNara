#!/bin/bash
set -eu
cd /c/Users/fk/PiliNara
GH_TOKEN=$(git config --local remote.origin.url | sed -E "s#.*guloi:([^@]+)@.*#\1#")
git -c core.editor=true commit --no-edit -q
git log -1 --format="%h %an <%ae> | %cn <%ce> | %s"
git push "http://guloi:$GH_TOKEN@127.0.0.1:8765/guloi/PiliNara.git" HEAD:ds-ai-hdr 2>&1 | tail -3
