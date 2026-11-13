export GH_TOKEN=$(git -C /c/Users/fk/PiliNara config --local remote.origin.url | sed -E 's#.*guloi:([^@]+)@.*#\1#')
prev=""
for i in $(seq 1 120); do
  st=$(python.exe /c/Users/fk/PiliNara/.dsh-tmp/wait_run.py 2>&1 | tail -3)
  if [ "$st" != "$prev" ]; then echo "[$(date +%H:%M:%S)] $st"; prev="$st"; fi
  case "$st" in *"completed success"*|*"completed failure"*|*"completed cancelled"*) echo "FINAL"; break;; esac
  sleep 20
done