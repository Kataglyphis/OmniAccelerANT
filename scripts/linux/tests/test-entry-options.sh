#!/usr/bin/env bash
# The shared flag loop's contract; each entry script's own values are graded by that script's suite.
set -uo pipefail
# shellcheck source=scripts/linux/tests/harness-bootstrap.sh
source "$(dirname "${BASH_SOURCE[0]}")/harness-bootstrap.sh"
library="${ENTRY_OPTIONS_LIB:-${KATAGLYPHIS_REPO_ROOT}/scripts/linux/lib/entry-options.sh}"

probe() {
  bash -c '
    set -euo pipefail
    source "$1"
    shift
    take_positional() { case "$1" in -*) return 1 ;; *) rest+=("$1") ;; esac; }
    value=default0 phrased=default1 switch=off rest=()
    parse_entry_options "--value V" take_positional --value=value "--phrased=phrased:a phrase" +--switch=switch=on -a=value -- "$@"
    printf "%s|%s|%s|%s\n" "$value" "$phrased" "$switch" "${rest[*]:-}"
  ' _ "$library" "$@"
}

t_case 'values, aliases, switches and other arguments land in caller order'
t_assert_eq 'two|p|on|x y' "$(probe x --value one --switch --phrased p -a two y)"
t_assert_eq 'default0|default1|off|' "$(probe)"
t_assert_eq 'default0|default1|off|' "$(probe '')"
t_assert_eq '-h|default1|off|' "$(probe --value -h)"

t_case 'an unphrased flag accepts an empty value and refuses a missing one'
t_assert_eq '|default1|off|' "$(probe --value '')"
t_assert_rc 1 probe --value
t_assert_contains "$(probe --value 2>&1)" '--value needs a value'

t_case 'a phrased flag refuses both, in its own words'
t_assert_rc 1 probe --phrased
t_assert_rc 1 probe --phrased ''
t_assert_contains "$(probe --phrased '' 2>&1)" '--phrased needs a phrase'

t_case 'help exits 0 with the usage text, unknown exits 2'
t_assert_rc 0 probe --help
t_assert_contains "$(probe -h)" 'usage: _ --value V'
t_assert_rc 2 probe --unknown
t_assert_contains "$(probe --unknown 2>&1)" 'unknown argument: --unknown'

if [[ "${1:-}" == --values-only ]]; then t_summary; exit; fi

mutant_dir="$(t_mutant_dir entry-options)" || exit 1
trap 'rm -rf -- "${mutant_dir}"' EXIT
sed 's/_entry_phrases\[$flag\]="${target#\*:}"/_entry_phrases[$flag]=""/' "$library" > "${mutant_dir}/entry-options.sh"
if cmp -s "$library" "${mutant_dir}/entry-options.sh"; then exit 1; fi
t_mutant_breaks_suite 'a lost phrase fails the real parser assertions (mutation)' \
  ENTRY_OPTIONS_LIB "${mutant_dir}/entry-options.sh" --values-only

t_summary
