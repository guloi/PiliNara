#!/bin/bash
cd /c/Users/fk/PiliNara
export GH_TOKEN=$(git config --local remote.origin.url | sed -E "s#.*guloi:([^@]+)@.*#\1#")
python.exe .dsh-tmp/ci.py
