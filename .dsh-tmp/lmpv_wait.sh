export GH_TOKEN=$(git -C /c/Users/fk/PiliNara config --local remote.origin.url | sed -E 's#.*guloi:([^@]+)@.*#\1#')
prev=""
for i in $(seq 1 300); do
  st=$(python.exe /c/Users/fk/PiliNara/.dsh-tmp/lmpv_status.py 2>&1 | head -1 | awk '{print $1" "$2}')
  if [ "$st" != "$prev" ]; then echo "[$(date +%H:%M:%S)] $st"; prev="$st"; fi
  case "$st" in completed*) echo "FINAL: $st"; break;; esac
  sleep 30
done