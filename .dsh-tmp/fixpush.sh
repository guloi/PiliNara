#!/bin/bash
set -eu
cd /c/Users/fk/PiliNara
GH_TOKEN=$(git config --local remote.origin.url | sed -E "s#.*guloi:([^@]+)@.*#\1#")
git add lib/utils/storage_pref.dart lib/utils/storage_key.dart
git commit -q --amend --no-edit
git log -1 --format="%h %an <%ae> | %cn <%ce> | %s"
git push --force-with-lease=ds-ai-hdr:79db9e4ec "http://guloi:$GH_TOKEN@127.0.0.1:8765/guloi/PiliNara.git" HEAD:ds-ai-hdr 2>&1 | tail -3
