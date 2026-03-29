#!/usr/bin/env python3
"""PostToolUseFailure hook: instructs Claude to diagnose, fix, and save to memory."""
import sys, json

data = json.load(sys.stdin)
command = data.get("tool_input", {}).get("command", "")
error = data.get("error", "")

context = f"""COMMAND FAILURE DETECTED.

Failed command: {command}
Error: {error}

MANDATORY WORKFLOW — Do NOT blindly retry. Follow these steps:
1. DIAGNOSE: Identify the root cause of the failure
2. CHECK MEMORY: Read MEMORY.md for known fixes for this type of error
3. FIX: Find a working solution
4. SAVE: If the fix is reusable across sessions, update MEMORY.md with the diagnosis and solution
5. RETRY: Execute the corrected command"""

result = {
    "hookSpecificOutput": {
        "hookEventName": "PostToolUseFailure",
        "additionalContext": context
    }
}

print(json.dumps(result))
