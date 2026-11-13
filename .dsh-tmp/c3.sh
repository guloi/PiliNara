export GH_TOKEN=$(git -C /c/Users/fk/PiliNara config --local remote.origin.url | sed -E 's#.*guloi:([^@]+)@.*#\1#')
cd /c/Users/fk/PiliNara/third_party/libmpv-android-video-build
cp /c/Users/fk/PiliNara/.dsh-tmp/android-gl-hdr.new.patch buildscripts/patches/mpv/android-gl-hdr.patch
git add -A
git -c user.name=guloi -c user.email=soiaii@163.com commit --amend --no-edit
git push "http://guloi:$GH_TOKEN@127.0.0.1:8765/Guloi/libmpv-android-video-build.git" HEAD:gl-hdr --force 2>&1 | tail -2
git log --oneline -2