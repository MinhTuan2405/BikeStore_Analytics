#!/usr/bin/env bash
# After a Dagster project is scaffolded via the dagster-expert plugin
# (`create-dagster` or `dg scaffold project`), nudge the agent to apply the
# project's layout convention by loading the `dagster-orchestration-layout` skill.

set -euo pipefail

PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null) || {
  echo '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":""}}' ; exit 0
}

payload="$(cat)"

tool_name="$(printf '%s' "$payload" | "$PYTHON" -c 'import json,sys;d=json.load(sys.stdin);print(d.get("tool_name",""))')"
[ "$tool_name" = "Bash" ] || exit 0

cmd="$(printf '%s' "$payload" | "$PYTHON" -c 'import json,sys;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("command",""))')"

case "$cmd" in
  *create-dagster*|*"dg scaffold project"*|*"dagster project scaffold"*)
    "$PYTHON" -c '
import json
msg = (
  "A new Dagster project was just scaffolded. Before doing anything else, "
  "load the `dagster-orchestration-layout` skill via the Skill tool and "
  "reshape the scaffolded project to match the project layout convention "
  "(assets/<source>/, resources/<system>_resource.py, RESOURCES dict per "
  "deployment, asset-group-driven jobs, utils/ split by concern)."
)
print(json.dumps({
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": msg
  }
}))
'
    ;;
esac
