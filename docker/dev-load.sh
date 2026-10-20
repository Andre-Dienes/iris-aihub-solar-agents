#!/usr/bin/env bash
# Development loop: copy ../src into the running container and recompile the SolarAgents package.
# Usage: ./docker/dev-load.sh [container]
set -euo pipefail
export MSYS_NO_PATHCONV=1
CONTAINER="${1:-solar-agents-iris}"
HERE="$(cd "$(dirname "$0")" && pwd -W 2>/dev/null || pwd)"
docker exec -u root "$CONTAINER" rm -rf /tmp/src
docker cp "$HERE/../src" "$CONTAINER:/tmp/src"
docker exec -u root "$CONTAINER" chown -R irisowner /tmp/src
docker exec -i "$CONTAINER" iris session IRIS -U SOLAR <<'EOF' | grep -vE '^(SOLAR>|\s*$)'
do $system.OBJ.LoadDir("/tmp/src","k",.err,1)
do $system.OBJ.CompilePackage("SolarAgents","ck-d",.err)
do $system.OBJ.Compile("SolarAgents.Tools.SolarToolSet","ck-d",.err)
write "ERRORS: ",+$get(err),!
set i="" for { set i=$order(err(i)) quit:i=""  write $get(err(i)),! }
halt
EOF
