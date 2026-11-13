#!/bin/bash
cd /c/Users/fk/PiliNara
mkdir -p .dsh-tmp/tmp
export TMP="C:/Users/fk/PiliNara/.dsh-tmp/tmp"
export TEMP="$TMP"
export TMPDIR="$TMP"
timeout 500 /c/Users/fk/flutter/bin/cache/dart-sdk/bin/dart.exe analyze lib/plugin/pl_player/controller.dart lib/pages/setting/models/hdr_settings.dart 2>&1 | tail -30
