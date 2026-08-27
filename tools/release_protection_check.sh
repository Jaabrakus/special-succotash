#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

failed=0

report_failure() {
	printf 'BLOCK: %s\n' "$1"
	failed=1
}

report_warning() {
	printf 'WARN: %s\n' "$1"
}

for required_file in LICENSE.md AI_TRAINING_POLICY.md THIRD_PARTY_NOTICES.md web/robots.txt web/ai.txt; do
	if [ ! -f "$required_file" ]; then
		report_failure "missing $required_file"
	fi
done

if ! grep -q 'name="141 Restricted Web"' export_presets.cfg; then
	report_failure "missing the restricted Web export preset"
fi

for protected_pattern in 'art_source/*' 'reference/*' 'tools/*' 'scripts/labs/gunsmith/*' 'scripts/labs/animation_studio/*'; do
	if ! grep -Fq "$protected_pattern" export_presets.cfg; then
		report_failure "restricted Web export does not exclude $protected_pattern"
	fi
done

preset_count=$(grep -c '^\[preset\.[0-9][0-9]*\]$' export_presets.cfg)
for protected_pattern in \
	'addons/socom_authoring/*' \
	'reCOM-main/*' \
	'counter-strike-urban/*' \
	'motion/*' \
	'source/*' \
	'config/supabase.json' \
	'supabase/*' \
	'animation_library_lab.tscn' \
	'scripts/labs/acoustic_*' \
	'scripts/labs/animation_studio/*'
do
	protected_count=$(grep 'exclude_filter=' export_presets.cfg | grep -Fc "$protected_pattern" || true)
	if [ "$protected_count" -ne "$preset_count" ]; then
		report_failure "every export preset must exclude $protected_pattern"
	fi
done

if grep -R -Fq 'preload("res://counter-strike-urban/' scripts; then
	report_failure "runtime scripts hard-preload optional counter-strike-urban staging content"
fi

tracked_secrets=$(git ls-files | awk '
	/(^|\/)\.env($|\.)/ ||
	/\.(p12|pfx|pem|key|keystore)$/ ||
	/(^|\/)(private|private_assets|server_secrets)\// { print }
')
if [ -n "$tracked_secrets" ]; then
	report_failure "tracked file names match protected credential or private paths"
	printf '%s\n' "$tracked_secrets"
fi

tracked_source_art=$(git ls-files | awk '
	/\.(blend|blend[0-9]+|psd|kra|xcf|mb|ma|max|c4d|hip|spp)$/ { print }
')
if [ -n "$tracked_source_art" ]; then
	report_warning "editable source-art files are tracked; keep the repository private"
	printf '%s\n' "$tracked_source_art"
fi

if [ -f export_presets.cfg ] && grep -q 'export_filter="all_resources"' export_presets.cfg; then
	report_warning "an export preset uses all_resources; inspect the exported package before release"
fi

if git ls-files | grep -Eq '(^|/)(art_source|reference)/'; then
	report_warning "development reference or source-art paths are tracked; do not publish this repository without review"
fi

if [ "$failed" -ne 0 ]; then
	printf 'Release protection check failed.\n'
	exit 1
fi

printf 'Release protection check passed with any warnings shown above.\n'
