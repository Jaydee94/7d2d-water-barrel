#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ps_script="$script_dir/Deploy-Mod.ps1"

if command -v pwsh >/dev/null 2>&1; then
    exec pwsh -NoProfile -File "$ps_script" "$@"
fi

if ! command -v powershell.exe >/dev/null 2>&1; then
    echo "pwsh or powershell.exe is required to run Deploy-Mod.ps1 from WSL." >&2
    exit 1
fi

if ! command -v wslpath >/dev/null 2>&1; then
    echo "wslpath is required to convert the script path for powershell.exe." >&2
    exit 1
fi

exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w "$ps_script")" "$@"