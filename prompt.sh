# shellcheck shell=bash
# Source from ~/.bashrc or ~/.zshrc. Display and settings are documented in README.md.

# Sets __prompt_dur instead of printing, so callers avoid a $(...) fork.
__prompt_fmt_duration() {
  local s=$1
  if [ "$s" -ge 3600 ]; then
    __prompt_dur="$((s / 3600))h$((s % 3600 / 60))m"
  elif [ "$s" -ge 60 ]; then
    __prompt_dur="$((s / 60))m$((s % 60))s"
  else
    __prompt_dur="${s}s"
  fi
}

# $1 exit code, $2 elapsed seconds, $3/$4/$5 = red/yellow/reset in the shell's
# prompt syntax. Sets __prompt_seg.
__prompt_status_segment() {
  __prompt_seg=''
  [ "$1" -ne 0 ] && __prompt_seg="$3✘$1$5 "
  if [ "$2" -ge "${PROMPT_DURATION_MIN:-3}" ]; then
    __prompt_fmt_duration "$2"
    __prompt_seg="$__prompt_seg$4$__prompt_dur$5 "
  fi
}

# True if element $1 is listed in PROMPT_GIT_SHOW (space or comma separated).
__prompt_git_on() {
  case " ${PROMPT_GIT_SHOW//,/ } " in
    *" $1 "*|*" all "*) return 0 ;;
  esac
  return 1
}

# True if $1 (a repository's top directory) matches a glob in PROMPT_GIT_IGNORE.
__prompt_git_ignored() {
  local rest=${PROMPT_GIT_IGNORE-} pat
  while [ -n "$rest" ]; do
    pat=${rest%%:*}
    [ -n "$pat" ] && __prompt_match "$1" "$pat" && return 0
    case $rest in
      *:*) rest=${rest#*:} ;;
      *) rest='' ;;
    esac
  done
  return 1
}

__prompt_host_needed=0
if [ -n "${SSH_CONNECTION-}${SSH_TTY-}${container-}" ] || [ "${EUID-}" = 0 ] ||
   [ -e /.dockerenv ] || [ -e /run/.containerenv ]; then
  __prompt_host_needed=1
fi

# $1..$5 = red/green/yellow/cyan/reset in the shell's prompt syntax.
# Sets __prompt_git_branch and __prompt_git_seg. The segment refers to the
# branch as a literal ${__prompt_git_branch}: PS1 is expanded again at display
# time, and a branch may be named $(cmd).
__prompt_git() {
  __prompt_git_seg=''
  __prompt_git_branch=''
  local out line gd xy top br='' oid='' op='' step='' total='' s=''
  local -i ahead=0 behind=0 staged=0 unstaged=0 untracked=0 conflicts=0 stashes=0
  local -a args=(--porcelain=v2 --branch)
  __prompt_git_on untracked || args+=(-uno)
  __prompt_git_on stash && args+=(--show-stash)
  if [ -n "${PROMPT_GIT_IGNORE-}" ]; then
    top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
    __prompt_git_ignored "$top" && return 0
  fi
  out=$(git rev-parse --git-dir 2>/dev/null &&
    git --no-optional-locks status "${args[@]}" 2>/dev/null) || return 0
  gd=${out%%$'\n'*}
  out=${out#*$'\n'}

  while IFS= read -r line; do
    case $line in
      '# branch.oid '*)  oid=${line#'# branch.oid '} ;;
      '# branch.head '*) br=${line#'# branch.head '} ;;
      '# branch.ab '*)
        line=${line#'# branch.ab +'}
        ahead=${line%% *}
        behind=${line##*-} ;;
      '# stash '*)       stashes=${line#'# stash '} ;;
      '1 '*|'2 '*)
        xy=${line:2:2}
        [ "${xy%?}" = . ] || staged=$((staged + 1))
        [ "${xy#?}" = . ] || unstaged=$((unstaged + 1)) ;;
      'u '*)             conflicts=$((conflicts + 1)) ;;
      '? '*)             untracked=$((untracked + 1)) ;;
    esac
  done <<<"$out"

  if [ -d "$gd/rebase-merge" ]; then
    op=REBASE
    read -r step 2>/dev/null <"$gd/rebase-merge/msgnum"
    read -r total 2>/dev/null <"$gd/rebase-merge/end"
    read -r br 2>/dev/null <"$gd/rebase-merge/head-name"
  elif [ -d "$gd/rebase-apply" ]; then
    read -r step 2>/dev/null <"$gd/rebase-apply/next"
    read -r total 2>/dev/null <"$gd/rebase-apply/last"
    if [ -f "$gd/rebase-apply/rebasing" ]; then
      op=REBASE
      read -r br 2>/dev/null <"$gd/rebase-apply/head-name"
    elif [ -f "$gd/rebase-apply/applying" ]; then
      op=AM
    else
      op=AM/REBASE
    fi
  elif [ -f "$gd/MERGE_HEAD" ]; then op=MERGING
  elif [ -f "$gd/CHERRY_PICK_HEAD" ]; then op=CHERRY-PICKING
  elif [ -f "$gd/REVERT_HEAD" ]; then op=REVERTING
  elif [ -f "$gd/BISECT_LOG" ]; then op=BISECTING
  fi

  br=${br#refs/heads/}
  [ "$br" = '(detached)' ] && br="detached@${oid:0:7}"
  __prompt_git_branch=$br

  [ "$oid" = '(initial)' ] && __prompt_git_on new && s="$s ${3}new$5"
  [ -n "$op" ] && s="$s $3$op${step:+ $step/$total}$5"
  [ "$conflicts" -gt 0 ] && s="$s $1⚠$conflicts$5"
  [ "$staged" -gt 0 ]    && __prompt_git_on staged    && s="$s $2●$staged$5"
  [ "$unstaged" -gt 0 ]  && __prompt_git_on unstaged  && s="$s $1✎$unstaged$5"
  [ "$untracked" -gt 0 ] && __prompt_git_on untracked && s="$s $1?$untracked$5"
  [ "$stashes" -gt 0 ]   && s="$s $4⚑$stashes$5"
  [ "$ahead" -gt 0 ]     && s="$s $4↑$ahead$5"
  [ "$behind" -gt 0 ]    && s="$s $4↓$behind$5"
  [ -z "$s" ] && __prompt_git_on clean && s=" $2✔$5"
  __prompt_git_seg=" ($2\${__prompt_git_branch}$5$s)"
}

if [ -n "$BASH_VERSION" ]; then
  # Captured once: after the first prompt, PS1 already contains our segments.
  if [ -z "${__prompt_pre+x}" ]; then
    __prompt_pre=${PS1%'\$ '}
  fi
  __prompt_title=''
  case $__prompt_pre in
    '\[\e]0;'*) __prompt_title=${__prompt_pre%%'\a\]'*}'\a\]' ;;
  esac

  # shellcheck disable=SC2053 # $2 is a glob
  __prompt_match() { [[ $1 == $2 ]]; }

  # PS0 expands in this shell just before a command runs; only an arithmetic
  # subscript can assign from it. EPOCHREALTIME uses ',' in some locales.
  case $PS0 in
    *__prompt_t0*) ;;
    *) PS0="${PS0}"'${__prompt_nil[(__prompt_t0=${EPOCHREALTIME/[.,]/}),0]:0:0}' ;;
  esac

  __prompt_cmd() {
    local ec=$? mr='' secs fail=0 ch='\$' base=$__prompt_pre j n
    __prompt_seg=''
    # Unset __prompt_t0 means no command ran (empty Enter, Ctrl-C at the prompt).
    if [ -n "${__prompt_t0-}" ]; then
      secs=$(( (${EPOCHREALTIME/[.,]/} - __prompt_t0) / 1000000 ))
      unset __prompt_t0
      [ "$ec" -ne 0 ] && fail=1
      [ "${PROMPT_EXIT_STYLE:-code}" = char ] && ec=0
      __prompt_status_segment "$ec" "$secs" '\[\e[31m\]' '\[\e[33m\]' '\[\e[0m\]'
    fi
    [ "$fail" = 1 ] && [ "${PROMPT_EXIT_STYLE:-code}" = char ] && ch='\[\e[31m\]\$\[\e[0m\]'
    if [ "${PROMPT_JOBS:-0}" = 1 ]; then
      j=$(jobs -p)
      if [ -n "$j" ]; then
        n=${j//[!$'\n']/}
        __prompt_seg="$__prompt_seg\[\e[36m\]✦$(( ${#n} + 1 ))\[\e[0m\] "
      fi
    fi
    if [ "${PROMPT_HOST:-always}" = auto ]; then
      base=$__prompt_title
      [ "$__prompt_host_needed" = 1 ] && base="$base"'\[\e[01;32m\]\u@\h\[\e[00m\]:'
      base="$base"'\[\e[01;34m\]\w\[\e[00m\]'
    fi
    [ "${PROMPT_TWO_LINE:-0}" = 1 ] && ch="\\n$ch"
    __prompt_git '\[\e[31m\]' '\[\e[32m\]' '\[\e[33m\]' '\[\e[36m\]' '\[\e[0m\]'
    [ "${GIT_PROMPT_MR:-1}" = 0 ] || mr=$(git-mr --segment=bash 2>/dev/null)
    PS1="$__prompt_seg$base$__prompt_git_seg${mr:+ $mr}$ch "
  }
  case ";$PROMPT_COMMAND;" in
    *";__prompt_cmd;"*) ;;
    *) PROMPT_COMMAND="__prompt_cmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
  esac

elif [ -n "$ZSH_VERSION" ]; then
  setopt PROMPT_SUBST
  zmodload zsh/datetime zsh/parameter
  autoload -Uz add-zsh-hook
  # Not ${__prompt_pre:=...}: the '}' of %F{green} would close the expansion.
  if [[ -z ${__prompt_pre-} ]]; then
    __prompt_pre='%B%F{green}%n@%m%f%b:%B%F{blue}%~%f%b'
  fi

  __prompt_match() { [[ $1 == ${~2} ]]; }

  __prompt_preexec() { __prompt_t0=$EPOCHREALTIME; }
  __prompt_precmd() {
    local ec=$? mr='' fail=0 ch='%#' base=$__prompt_pre
    local -i secs
    __prompt_seg=''
    if [[ -n ${__prompt_t0-} ]]; then
      (( secs = EPOCHREALTIME - __prompt_t0 ))
      unset __prompt_t0
      (( ec )) && fail=1
      [[ ${PROMPT_EXIT_STYLE:-code} = char ]] && ec=0
      __prompt_status_segment "$ec" "$secs" '%F{red}' '%F{yellow}' '%f'
    fi
    [[ $fail = 1 && ${PROMPT_EXIT_STYLE:-code} = char ]] && ch='%F{red}%#%f'
    if [[ ${PROMPT_JOBS:-0} = 1 ]] && (( ${#jobstates} )); then
      __prompt_seg="$__prompt_seg%F{cyan}✦${#jobstates}%f "
    fi
    if [[ ${PROMPT_HOST:-always} = auto ]]; then
      base=''
      [[ $__prompt_host_needed = 1 ]] && base='%B%F{green}%n@%m%f%b:'
      base="$base%B%F{blue}%~%f%b"
    fi
    [[ ${PROMPT_TWO_LINE:-0} = 1 ]] && ch=$'\n'"$ch"
    __prompt_git '%F{red}' '%F{green}' '%F{yellow}' '%F{cyan}' '%f'
    # Prompt escapes are applied after PROMPT_SUBST expansion, so % must be doubled.
    __prompt_git_branch=${__prompt_git_branch//\%/%%}
    [[ ${GIT_PROMPT_MR:-1} = 0 ]] || mr=$(git-mr --segment=zsh 2>/dev/null)
    PS1="$__prompt_seg$base$__prompt_git_seg${mr:+ $mr}$ch "
  }
  add-zsh-hook preexec __prompt_preexec
  # First in line, so $? is still the user's command status, not another hook's.
  precmd_functions=(__prompt_precmd ${precmd_functions:#__prompt_precmd})
fi
