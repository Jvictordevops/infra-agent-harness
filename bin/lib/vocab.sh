# shellcheck shell=bash
# Record vocabulary per language, for the scripts and hooks that read or write records.
#
# The repository that uses the harness picks its language in <repo root>/.harness.conf:
#     language=es
# IAH_LANG overrides it; with neither, the language is "en". The words live in locale/<lang>.sh
# (KEY="value" lines). Both files are parsed as data: nothing in them is executed.
#
#   . bin/lib/vocab.sh
#   vocab_load "$repo_root"      # sets VOC_LANG and every VOC_* variable
#   vocab_banner_re              # ERE for the banners allowed under a record title

IAH_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=conf.sh
. "$(dirname "${BASH_SOURCE[0]}")/conf.sh"

# vocab_lang [repo root] -> language code
vocab_lang() {
  local lang="${IAH_LANG:-}"
  [ -n "$lang" ] || lang="$(conf_get "${1:-}" language)"
  printf '%s' "${lang:-en}"
}

# _vocab_read <file>: assign the VOC_* keys of a locale file (data only, no eval)
_vocab_read() {
  local line key val
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^(VOC_[A-Z0-9_]+)=\"(.*)\"[[:space:]]*$ ]] || continue
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    printf -v "$key" '%s' "$val"
  done < "$1"
}

# vocab_load [repo root]
vocab_load() {
  local lang
  lang="$(vocab_lang "${1:-}")"
  case "$lang" in "" | *[!A-Za-z_-]*) echo "vocab: invalid language '$lang', using en" >&2; lang=en ;; esac
  if [ ! -f "$IAH_HOME/locale/$lang.sh" ]; then
    echo "vocab: no locale/$lang.sh, using en" >&2
    lang=en
  fi
  _vocab_read "$IAH_HOME/locale/en.sh"
  [ "$lang" = en ] || _vocab_read "$IAH_HOME/locale/$lang.sh"
  # shellcheck disable=SC2034  # read by the scripts that source this file
  VOC_LANG="$lang"
}

# vocab_re <text>: the text escaped for an extended regex
vocab_re() { printf '%s' "$1" | sed -e 's/[][\.*^$+?(){}|/]/\\&/g'; }

# vocab_banner_re: ERE matching a banner line under a record title, in the loaded language
vocab_banner_re() {
  printf '^> \\*\\*(%s|%s|%s):\\*\\* .*\\]\\([^)]+\\.done\\.md\\)' \
    "$(vocab_re "$VOC_CORRECTED_BY")" "$(vocab_re "$VOC_SUPERSEDED_BY")" "$(vocab_re "$VOC_IDS_RENUMBERED_IN")"
}
