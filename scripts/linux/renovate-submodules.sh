#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SELF_DIR}/../.." && pwd)"
LOCAL="${SELF_DIR}/renovate-local.sh"
MAX_DEPTH=8

[ -f "${LOCAL}" ] || { echo "renovate-submodules.sh: ${LOCAL} is missing" >&2; exit 1; }

normalize_url() {
  printf '%s' "$1" \
    | sed -e 's#^[a-zA-Z+]*://##' -e 's#^[^@/]*@##' -e 's#:#/#' \
          -e 's#\.git$##' -e 's#/*$##' \
    | tr '[:upper:]' '[:lower:]'
}

repo_identity() {
  local url
  url="$(git -C "$1" config --get remote.origin.url 2>/dev/null)" || return 1
  [ -n "${url}" ] || return 1
  normalize_url "${url}"
}

identity_owner() { printf '%s' "$1" | cut -d/ -f1,2; }

ROOT_ID="$(repo_identity "${REPO_ROOT}")" \
  || { echo "renovate-submodules.sh: ${REPO_ROOT} has no origin remote" >&2; exit 1; }
OWNER="$(identity_owner "${ROOT_ID}")"

declare -A CAND=()
declare -A CAND_DEPTH=()
declare -a IDS=()
declare -A DEPS=()

add_dep() {
  local from="$1" to="$2"
  case " ${DEPS[${from}]:-} " in
    *" ${to} "*) ;;
    *) DEPS["${from}"]="${DEPS[${from}]:- }${to} " ;;
  esac
}

walk() {
  local dir="$1" depth="$2" owner_id="$3" name path abs id
  [ "${depth}" -le "${MAX_DEPTH}" ] || return 0
  [ -f "${dir}/.gitmodules" ] || return 0
  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    path="$(git -C "${dir}" config -f .gitmodules --get "submodule.${name}.path" 2>/dev/null)" || continue
    [ -n "${path}" ] || continue
    abs="${dir}/${path}"
    [ -e "${abs}/.git" ] || continue
    id="$(repo_identity "${abs}" 2>/dev/null)" || id=""
    if [ -n "${id}" ] && [ "$(identity_owner "${id}")" = "${OWNER}" ]; then
      if [ -z "${CAND[${id}]+x}" ]; then
        CAND["${id}"]="${abs}"
        CAND_DEPTH["${id}"]="${depth}"
        IDS+=("${id}")
      elif [ "${depth}" -lt "${CAND_DEPTH[${id}]}" ]; then
        CAND["${id}"]="${abs}"
        CAND_DEPTH["${id}"]="${depth}"
      fi
      if [ -n "${owner_id}" ] && [ "${owner_id}" != "${id}" ]; then
        add_dep "${owner_id}" "${id}"
      fi
      walk "${abs}" $((depth + 1)) "${id}"
    else
      walk "${abs}" $((depth + 1)) "${owner_id}"
    fi
  done < <(git -C "${dir}" config -f .gitmodules --name-only --get-regexp '\.path$' 2>/dev/null \
           | sed -e 's/^submodule\.//' -e 's/\.path$//')
}

walk "${REPO_ROOT}" 1 "${ROOT_ID}"

if [ "${#IDS[@]}" -eq 0 ]; then
  echo "renovate-submodules.sh: no owned submodule with a checkout under ${REPO_ROOT}" >&2
  exit 0
fi

changed=1
while [ "${changed}" -eq 1 ]; do
  changed=0
  for id in "${IDS[@]}"; do
    for dep in ${DEPS[${id}]:-}; do
      for d2 in ${DEPS[${dep}]:-}; do
        if [ "${d2}" = "${id}" ]; then
          continue
        fi
        case " ${DEPS[${id}]:-} " in
          *" ${d2} "*) continue ;;
        esac
        add_dep "${id}" "${d2}"
        changed=1
      done
    done
  done
done

ORDER_ROWS="$(mktemp)" || exit 1
for id in "${IDS[@]}"; do
  rank=0
  for _d in ${DEPS[${id}]:-}; do rank=$((rank + 1)); done
  printf '%s\t%s\t%s\t%s\n' "${rank}" "$(basename "${CAND[${id}]}")" "${CAND[${id}]}" "${id}" >> "${ORDER_ROWS}"
done

ORDERED=()
while IFS=$'\t' read -r _rank _name _path _id; do
  ORDERED+=("${_path}")
done < <(sort -t$'\t' -k1,1n -k2,2 "${ORDER_ROWS}")
rm -f "${ORDER_ROWS}"

WORST=0
rc=0
LOG="$(mktemp)" || exit 1
for repo in "${ORDERED[@]}"; do
  echo ""
  echo "=== $(basename "${repo}")  ${repo}"
  : > "${LOG}"
  rc=0
  bash "${LOCAL}" "$@" "${repo}" 2>&1 | tee "${LOG}" || rc=${PIPESTATUS[0]}
  if [ "${rc}" -ne 0 ] && grep -q "no Renovate manager's file patterns match" "${LOG}" 2>/dev/null; then
    echo "--- nothing Renovate can manage here; skipped."
    rc=0
  fi
  case "${rc}" in
    0) ;;
    2) [ "${WORST}" -eq 1 ] || WORST=2 ;;
    *) WORST=1 ;;
  esac
done
rm -f "${LOG}"

exit "${WORST}"
