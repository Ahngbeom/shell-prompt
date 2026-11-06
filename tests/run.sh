#!/usr/bin/env bash
# Drives prompt.sh in bash and zsh (if found) and checks the prompt.
# ZSH=/path/to/zsh overrides the zsh lookup; MODULE_PATH/FPATH are passed through.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
fails=0
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

export HOME=$work GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -C "$1" "${@:2}" >/dev/null 2>&1; }
commit() { echo "$3" >"$1/$2"; g "$1" add "$2"; g "$1" commit -m "$2"; }

mkdir -p "$work/bin" "$work/plain"
printf '#!/bin/sh\necho "!42"\n' >"$work/bin/git-mr"
chmod +x "$work/bin/git-mr"

git init -q -b main "$work/new"

git init -q --bare -b main "$work/remote.git"
git clone -q "$work/remote.git" "$work/clean" 2>/dev/null
commit "$work/clean" a 1
commit "$work/clean" b 1
g "$work/clean" push -u origin main
mkdir "$work/clean/sub"

git clone -q "$work/remote.git" "$work/dirty"
git clone -q "$work/remote.git" "$work/other"
commit "$work/other" o 1
g "$work/other" push
g "$work/dirty" fetch
commit "$work/dirty" d 1
echo stash >>"$work/dirty/a"; g "$work/dirty" stash
echo x >>"$work/dirty/a"
echo x >"$work/dirty/c"; g "$work/dirty" add c
echo x >>"$work/dirty/b"; g "$work/dirty" add b; echo y >>"$work/dirty/b"
touch "$work/dirty/u1" "$work/dirty/u2"

git clone -q "$work/remote.git" "$work/detached"
g "$work/detached" checkout --detach
sha=$(git -C "$work/detached" rev-parse HEAD)

git clone -q "$work/remote.git" "$work/merge"
g "$work/merge" checkout -b side; commit "$work/merge" a side
g "$work/merge" checkout main; commit "$work/merge" a main
g "$work/merge" merge side

git clone -q "$work/remote.git" "$work/rebase"
g "$work/rebase" checkout -b side; commit "$work/rebase" a side
g "$work/rebase" checkout main; commit "$work/rebase" a main
g "$work/rebase" rebase side

printf '%s\n' "__pt_s_char='>>'" >"$work/my-theme.sh"
esc=$(printf '\033')

git init -q -b main "$work/evil"
commit "$work/evil" a 1
# shellcheck disable=SC2016 # the literal $(...) is the point
g "$work/evil" checkout -b '$(true>pwned)'

# $1 shell, $2 directory, $3 PROMPT_GIT_SHOW, $IGN PROMPT_GIT_IGNORE; prints
# "branch|segment" with colors left empty.
git_seg() {
  local code="NO_COLOR=1 PROMPT_THEME='${THEME-}' PROMPT_GIT_SHOW='${3-}' PROMPT_GIT_IGNORE='${IGN-}'; . '$here/prompt.sh'; __prompt_git; printf '%s|%s\n' \"\$__prompt_git_branch\" \"\$__prompt_git_seg\""
  case $1 in
    bash) (cd "$2" && bash --norc -c "$code") ;;
    zsh)  (cd "$2" && "$ZSH" -f -c "${MODULE_PATH:+module_path=($MODULE_PATH);} $code") ;;
  esac
}

# $1 shell, $2 command list; prints one "TAG[PS1]" line per probe. Runs in $DIR,
# with $PRE run before prompt.sh is sourced.
run_shell() {
  local sh=$1 script=$2 prelude
  local -a cmd
  case $sh in
    bash) cmd=(bash --norc -i); prelude="PS1='u@h:\\w\\\$ '" ;;
    # zsh imports FPATH from the environment but not MODULE_PATH.
    zsh)  cmd=("$ZSH" -f -i); prelude="${MODULE_PATH:+module_path=($MODULE_PATH)}" ;;
  esac
  (cd "${DIR:-$work/clean}" && printf '%s\n' "$prelude" "${PRE-}" ". '$here/prompt.sh'" "$script" |
    env -i HOME="$work" PATH="$work/bin:/usr/bin:/bin" TERM=dumb \
      PROMPT_DURATION_MIN=1 GIT_PROMPT_MR="${MR:-0}" ${FPATH:+FPATH="$FPATH"} \
      "${cmd[@]}" 2>/dev/null) | grep -ao '[A-Z]\[.*\]$' | sed 's/^[^A-Z]*//'
}

# $1 label, $2 actual, $3 grep -E pattern, $4 "!" to require no match.
check() {
  if { [ "${4-}" = '!' ] && ! printf '%s' "$2" | grep -qE -- "$3"; } ||
     { [ "${4-}" != '!' ] && printf '%s' "$2" | grep -qE -- "$3"; }; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n     got: %s\n' "$1" "$2"
    fails=$((fails + 1))
  fi
}

# $1 label, $2 actual, $3 expected (exact).
same() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n     got:  %s\n     want: %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

# shellcheck disable=SC2016 # run by the shell under test
probe='printf "P[%s]\n" "$PS1"'
# zsh puts a real newline in PS1; bash keeps the two characters \n.
# shellcheck disable=SC2016
probe_nl='printf "P[%s]\n" "${PS1//$'"'"'\n'"'"'/<NL>}"'
suite() {
  # shellcheck disable=SC2016 # the literal reference that PS1 holds
  local sh=$1 out b='${__prompt_git_branch}'
  same "$sh: git outside a repo"     "$(git_seg "$sh" "$work/plain" all)"    '|'
  same "$sh: git new repo"           "$(git_seg "$sh" "$work/new" all)"      "main| ($b new)"
  same "$sh: git clean"              "$(git_seg "$sh" "$work/clean" all)"    "main| ($b ✔)"
  same "$sh: git counts"             "$(git_seg "$sh" "$work/dirty" all)"    "main| ($b ●2 ✎2 ?2 ⚑1 ↑1 ↓1)"
  same "$sh: git detached"           "$(git_seg "$sh" "$work/detached" all)" "detached@${sha:0:7}| ($b ✔)"
  same "$sh: git merge conflict"     "$(git_seg "$sh" "$work/merge" all)"    "main| ($b MERGING ⚠1 ↑1)"
  same "$sh: git rebase in progress" "$(git_seg "$sh" "$work/rebase" all)"   "main| ($b REBASE 1/1 ⚠1)"

  same "$sh: default shows only upstream" "$(git_seg "$sh" "$work/dirty")"  "main| ($b ↑1 ↓1)"
  same "$sh: default clean"          "$(git_seg "$sh" "$work/clean")"        "main| ($b)"
  same "$sh: default new repo"       "$(git_seg "$sh" "$work/new")"          "main| ($b)"
  same "$sh: default merge shows op"  "$(git_seg "$sh" "$work/merge")"        "main| ($b MERGING ⚠1 ↑1)"
  same "$sh: default rebase shows op" "$(git_seg "$sh" "$work/rebase")"     "main| ($b REBASE 1/1 ⚠1)"
  same "$sh: selected elements"      "$(git_seg "$sh" "$work/dirty" 'staged,stash')" "main| ($b ●2 ⚑1 ↑1 ↓1)"
  same "$sh: each element alone"     "$(for e in staged unstaged untracked stash; do git_seg "$sh" "$work/dirty" "$e"; done | tr '\n' ' ')" \
    "main| ($b ●2 ↑1 ↓1) main| ($b ✎2 ↑1 ↓1) main| ($b ?2 ↑1 ↓1) main| ($b ⚑1 ↑1 ↓1) "
  same "$sh: clean alone"            "$(git_seg "$sh" "$work/clean" clean)"  "main| ($b ✔)"
  out=$(run_shell "$sh" "false
${probe/P/A}
sleep 1.2
${probe/P/B}

${probe/P/C}
(exit 3)
${probe/P/D}")
  check "$sh: failure shows exit code"        "$(sed -n 1p <<<"$out")" '✘1'
  check "$sh: success hides exit code"        "$(sed -n 2p <<<"$out")" '✘' '!'
  check "$sh: slow command shows duration"    "$(sed -n 2p <<<"$out")" '1s'
  check "$sh: fast command hides duration"    "$(sed -n 1p <<<"$out")" '[0-9]s' '!'
  check "$sh: empty Enter clears segments"    "$(sed -n 3p <<<"$out")" '✘|[0-9]s' '!'
  check "$sh: other exit codes"               "$(sed -n 4p <<<"$out")" '✘3'
  check "$sh: git segment in prompt"          "$(sed -n 1p <<<"$out")" '\(.*__prompt_git_branch[^ ]*\)'
  check "$sh: base prompt kept"               "$(sed -n 1p <<<"$out")" 'u@h|%n@%m%f%b:%B%F\{blue\}%~'

  out=$(MR=1 run_shell "$sh" "true
${probe/P/M}")
  check "$sh: MR segment before prompt char"  "$out" '!42(\\\$|%#) \]$'

  same "$sh: ignored repo has no git segment" "$(IGN=$work/clean git_seg "$sh" "$work/clean")" '|'
  same "$sh: ignore matches globs in a list"  "$(IGN="/nope:$work/cl*" git_seg "$sh" "$work/clean/sub")" '|'
  same "$sh: unmatched ignore keeps segment"  "$(IGN=/nope git_seg "$sh" "$work/clean")" "main| ($b)"

  out=$(run_shell "$sh" "PROMPT_EXIT_STYLE=char
false
${probe/P/E}
true
${probe/P/F}")
  check "$sh: char style hides exit code"     "$(sed -n 1p <<<"$out")" '✘' '!'
  check "$sh: char style colors prompt char"  "$(sed -n 1p <<<"$out")" '(\\\[\\e\[31m\\\]\\\$|31m%\}%#)'
  check "$sh: char style clears on success"   "$(sed -n 2p <<<"$out")" '(31m\\\]\\\$|31m%\}%#)' '!'

  out=$(run_shell "$sh" "PROMPT_HOST=auto
true
${probe/P/H}")
  if [ -e /.dockerenv ] || [ -e /run/.containerenv ]; then
    echo "skip $sh: local host check (running in a container)"
  else
    check "$sh: auto host hidden locally"     "$out" '\\u@\\h|%n@%m' '!'
  fi
  out=$(PRE="export SSH_CONNECTION='1 2 3 4'" run_shell "$sh" "PROMPT_HOST=auto
true
${probe/P/H}")
  check "$sh: auto host shown over SSH"       "$out" '\\u@\\h|%n@%m'

  out=$(run_shell "$sh" "true
${probe/P/N}
PROMPT_JOBS=1
${probe/P/O}
sleep 5 &
sleep 5 &
${probe/P/J}
PROMPT_JOBS=0
${probe/P/Q}
kill %1 %2")
  check "$sh: no jobs, no job count"          "$(sed -n 2p <<<"$out")" '✦' '!'
  check "$sh: job count"                      "$(sed -n 3p <<<"$out")" '✦2'
  check "$sh: job count off by default"       "$(sed -n 4p <<<"$out")" '✦' '!'

  out=$(run_shell "$sh" "PROMPT_TWO_LINE=1
${probe_nl/P/T}
PROMPT_TWO_LINE=0
${probe_nl/P/U}")
  check "$sh: two-line puts prompt char below" "$(sed -n 1p <<<"$out")" '(\\n|<NL>)(\\\$|%#) \]$'
  check "$sh: one line by default"            "$(sed -n 2p <<<"$out")" '\\n|<NL>' '!'

  same "$sh: space theme git segment" "$(THEME=space git_seg "$sh" "$work/dirty" all)" "main| ⋆ $b ◉2 ✎2 ?2 ⚑1 ▴1 ▾1"
  same "$sh: space theme new repo"   "$(THEME=space git_seg "$sh" "$work/new" all)"   "main| ⋆ $b nebula"

  out=$(PRE="PROMPT_THEME=space" run_shell "$sh" "false
${probe/P/S}
PROMPT_EXIT_STYLE=char
false
${probe/P/T}")
  check "$sh: space theme base"               "$(sed -n 1p <<<"$out")" '^S\[.*✧ '
  check "$sh: space status after git"         "$(sed -n 1p <<<"$out")" '__prompt_git_branch.*☄ 1.*☾ ❯.* \]$'
  check "$sh: space char style shows sun"     "$(sed -n 2p <<<"$out")" '☀ ❯'
  check "$sh: space char style hides comet"   "$(sed -n 2p <<<"$out")" '☄' '!'

  out=$(run_shell "$sh" "prompt_theme space
true
${probe/P/A}
prompt_theme default
true
${probe/P/B}
prompt_theme nope 2>/dev/null
printf 'R[%s]\n' \"\$?\"
true
${probe/P/C}
prompt_theme '$work/my-theme.sh'
true
${probe/P/D}
prompt_theme space
printf 'L[%s]\n' \"\$(prompt_theme | tr '\n' ,)\"")
  check "$sh: switch to space live"           "$(sed -n 1p <<<"$out")" '☾ ❯'
  check "$sh: switch back to default"         "$(sed -n 2p <<<"$out")" '☾' '!'
  check "$sh: unknown theme fails"            "$(sed -n 3p <<<"$out")" '^R\[1\]$'
  check "$sh: unknown theme keeps current"    "$(sed -n 4p <<<"$out")" '__prompt_git_branch.*\)(\\\$|%#) \]$'
  check "$sh: theme file overrides one value" "$(sed -n 5p <<<"$out")" '\(.*__prompt_git_branch.*\)>> \]$'
  check "$sh: theme list marks current"       "$(sed -n 6p <<<"$out")" '^L\[  default,\* space,\]$'

  out=$(PRE="NO_COLOR=1 PROMPT_THEME=space" run_shell "$sh" "false
${probe/P/N}")
  check "$sh: NO_COLOR drops colors"          "$out" "\\\\\\[\\\\e\\[|$esc\\[" '!'

  rm -f "$work/evil/pwned"
  DIR=$work/evil run_shell "$sh" "true
true" >/dev/null
  check "$sh: branch name is not executed"    "$(ls "$work/evil")" 'pwned' '!'
}

suite bash
ZSH=${ZSH:-$(command -v zsh || true)}
if [ -n "$ZSH" ]; then
  suite zsh
else
  echo "skip zsh: not installed (set ZSH=/path/to/zsh)"
fi

if [ "$fails" -eq 0 ]; then
  echo "all passed"
else
  echo "$fails failed"
  exit 1
fi
