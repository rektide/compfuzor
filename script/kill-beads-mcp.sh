#!/bin/bash
dry_run=false
while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run) dry_run=true; shift ;;
        *) echo "Usage: $0 [-n|--dry-run]"; exit 1 ;;
    esac
done

procs=$(
    { pgrep -af "uv run --frozen --project /usr/local/src/beads-git/integrations/beads-mcp beads-mcp" 2>/dev/null
      pgrep -af "/usr/local/src/beads-git/integrations/beads-mcp/\.venv/bin/python3 /usr/local/src/beads-git/integrations/beads-mcp/\.venv/bin/beads-mcp" 2>/dev/null
    } | sort -n | uniq
)

if [ -z "$procs" ]; then
    echo "No matching processes found."
    exit 0
fi

pids=$(echo "$procs" | awk '{print $1}')
echo "Found processes to kill:"
echo "$procs"
echo ""
echo "PIDs: $(echo $pids | tr '\n' ' ')"
echo ""

if [ "$dry_run" = true ]; then
    echo "[DRY RUN] Would kill the above processes."
    exit 0
fi

read -p "Kill these processes? [y/N] " confirm

if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    echo "$pids" | xargs kill
    echo "Done."
else
    echo "Aborted."
fi
