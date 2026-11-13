export GH_TOKEN=$(git -C /c/Users/fk/PiliNara config --local remote.origin.url | sed -E 's#.*guloi:([^@]+)@.*#\1#')
cd /c/Users/fk/PiliNara/third_party/libmpv-android-video-build
git push "http://guloi:$GH_TOKEN@127.0.0.1:8765/Guloi/libmpv-android-video-build.git" HEAD:gl-hdr 2>&1 | tail -3