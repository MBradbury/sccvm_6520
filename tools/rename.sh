#!/bin/bash
# Rename the template placeholder (sccm_0000) to your module code, in file
# contents and filenames, and set MODULE_CODE in module.env.
# Usage: tools/rename.sh scc_253

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLD="sccm_0000"
NEW="${1:-}"

if [[ ! "$NEW" =~ ^scc(m)?_[0-9]+$ ]]; then
	echo "Usage: $0 <module_code>   e.g. $0 scc_253 or $0 sccm_5550 (lower case)" >&2
	exit 2
fi

cd "$ROOT"
NEW_UPPER="$(echo "$NEW" | tr '[:lower:]' '[:upper:]')"

# Contents (docs and tools keep the placeholder - they describe it)
grep -rlI --exclude-dir=.git --exclude-dir=tools --exclude=README.md --exclude=MAINTAINERS.md \
	--exclude=CLAUDE.md --exclude=AGENTS.md \
	-e "$OLD" -e "SCCM_0000" . | while read -r f; do
	perl -pi -e "s/$OLD/$NEW/g; s/SCCM_0000/$NEW_UPPER/g" "$f"
	echo "updated  $f"
done

# Filenames
find . -path ./.git -prune -o -name "*$OLD*" -print | while read -r f; do
	new_f="${f//$OLD/$NEW}"
	if [ -d .git ] && git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
		git mv "$f" "$new_f"
	else
		mv "$f" "$new_f"
	fi
	echo "renamed  $f -> $new_f"
done

echo
echo "Done. Now run: tools/check.sh"
