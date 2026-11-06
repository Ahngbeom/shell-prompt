# shellcheck shell=bash disable=SC2154 # __pt_* come from themes/*.sh
# Source from ~/.bashrc or ~/.zshrc. Display, settings and themes are documented in README.md.

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

# Sets __pc_<name> from the theme's SGR code __pt_c_<name>, in the shell's
# prompt syntax; empty under NO_COLOR or when the theme leaves the code empty.
__prompt_apply_colors() {
  local n c
  for n in reset exit dur jobs icon host dir char char_fail branch \
           new op conflict staged unstaged untracked stash ahead behind clean; do
    eval "c=\${__pt_c_$n-}"
    [ "$n" = reset ] && c=0
    if [ -n "${NO_COLOR-}" ] || [ -z "$c" ]; then
      eval "__pc_$n=''"
    else
      eval "__pc_$n=\"\$__prompt_esc_open\$c\$__prompt_esc_close\""
    fi
  done
}

# prompt_theme NAME|FILE loads a theme on top of themes/default.sh;
# with no argument, lists the bundled themes.
prompt_theme() {
  local f
  if [ $# -eq 0 ]; then
    for f in "$__prompt_root"/themes/*.sh; do
      f=${f##*/}
      f=${f%.sh}
      if [ "$f" = "${PROMPT_THEME:-default}" ]; then echo "* $f"; else echo "  $f"; fi
    done
    return 0
  fi
  case $1 in
    */*) f=$1 ;;
    *) f=$__prompt_root/themes/$1.sh ;;
  esac
  if [ ! -r "$f" ]; then
    echo "prompt_theme: no theme '$1' (looked for $f)" >&2
    return 1
  fi
  # shellcheck source=themes/default.sh
  . "$__prompt_root/themes/default.sh"
  # shellcheck source=/dev/null
  [ "$f" = "$__prompt_root/themes/default.sh" ] || . "$f"
  PROMPT_THEME=$1
  __prompt_apply_colors
}

# $1 exit code (0 = none), $2 elapsed seconds (-1 = none), $3 job count.
# Sets __prompt_seg_front and __prompt_seg_end; the theme picks which one is used.
__prompt_status() {
  local s='' g=$__pt_status_gap
  [ "$1" -ne 0 ] && s="$s $__pc_exit$__pt_s_exit$g$1$__pc_reset"
  if [ "$2" -ge "${PROMPT_DURATION_MIN:-3}" ]; then
    __prompt_fmt_duration "$2"
    s="$s $__pc_dur$__pt_s_dur$__prompt_dur$__pc_reset"
  fi
  [ "$3" -gt 0 ] && s="$s $__pc_jobs$__pt_s_jobs$g$3$__pc_reset"
  __prompt_seg_front=''
  __prompt_seg_end=''
  [ -n "$s" ] || return 0
  if [ "$__pt_status_end" = 1 ]; then
    __prompt_seg_end=$s
  else
    __prompt_seg_front="${s# } "
  fi
}

# Sets __prompt_base_str: the captured shell prompt, or one built from the theme.
__prompt_base() {
  __prompt_base_str=$__prompt_pre
  [ "$__pt_base" = theme ] || [ "${PROMPT_HOST:-always}" = auto ] || return 0
  local b=$__prompt_title
  [ -n "$__pt_s_icon" ] && b="$b$__pc_icon$__pt_s_icon$__pc_reset"
  if [ "${PROMPT_HOST:-always}" != auto ] || [ "$__prompt_host_needed" = 1 ]; then
    b="$b$__pc_host$__prompt_uh$__pc_reset:"
  fi
  __prompt_base_str="$b$__pc_dir$__prompt_wd$__pc_reset"
}

# $1 = 1 if the last command failed. Sets __prompt_char_str.
__prompt_char() {
  local s=$__pt_s_char c=$__pc_char
  if [ "$1" = 1 ] && [ "${PROMPT_EXIT_STYLE:-code}" = char ]; then
    s=${__pt_s_char_fail:-$s}
    c=$__pc_char_fail
  fi
  [ -n "$s" ] || s=$__prompt_char_default
  [ -n "$c" ] && s="$c$s$__pc_reset"
  if [ "${PROMPT_TWO_LINE:-0}" = 1 ]; then
    s="$__prompt_nl$s"
  else
    s="$__pt_char_gap$s"
  fi
  __prompt_char_str=$s
}

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

  [ "$oid" = '(initial)' ] && __prompt_git_on new && s="$s $__pc_new$__pt_s_new$__pc_reset"
  [ -n "$op" ] && s="$s $__pc_op$op${step:+ $step/$total}$__pc_reset"
  [ "$conflicts" -gt 0 ] && s="$s $__pc_conflict$__pt_s_conflict$conflicts$__pc_reset"
  [ "$staged" -gt 0 ]    && __prompt_git_on staged    && s="$s $__pc_staged$__pt_s_staged$staged$__pc_reset"
  [ "$unstaged" -gt 0 ]  && __prompt_git_on unstaged  && s="$s $__pc_unstaged$__pt_s_unstaged$unstaged$__pc_reset"
  [ "$untracked" -gt 0 ] && __prompt_git_on untracked && s="$s $__pc_untracked$__pt_s_untracked$untracked$__pc_reset"
  [ "$stashes" -gt 0 ]   && s="$s $__pc_stash$__pt_s_stash$stashes$__pc_reset"
  [ "$ahead" -gt 0 ]     && s="$s $__pc_ahead$__pt_s_ahead$ahead$__pc_reset"
  [ "$behind" -gt 0 ]    && s="$s $__pc_behind$__pt_s_behind$behind$__pc_reset"
  [ -z "$s" ] && __prompt_git_on clean && s=" $__pc_clean$__pt_s_clean$__pc_reset"
  __prompt_git_seg="$__pt_git_open$__pc_branch$__pt_s_branch\${__prompt_git_branch}$__pc_reset$s$__pt_git_close"
}

if [ -n "$BASH_VERSION" ]; then
  __prompt_root=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null) || __prompt_root=${BASH_SOURCE[0]}
  __prompt_root=${__prompt_root%/*}
  __prompt_esc_open='\[\e['
  __prompt_esc_close='m\]'
  __prompt_uh='\u@\h'
  __prompt_wd='\w'
  __prompt_nl='\n'
  __prompt_char_default='\$'

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
  # shellcheck disable=SC2016 # expanded later by PS0
  case $PS0 in
    *__prompt_t0*) ;;
    *) PS0="${PS0}"'${__prompt_nil[(__prompt_t0=${EPOCHREALTIME/[.,]/}),0]:0:0}' ;;
  esac

  __prompt_cmd() {
    local ec=$? mr='' secs=-1 fail=0 j n=0
    # Unset __prompt_t0 means no command ran (empty Enter, Ctrl-C at the prompt).
    if [ -n "${__prompt_t0-}" ]; then
      secs=$(( (${EPOCHREALTIME/[.,]/} - __prompt_t0) / 1000000 ))
      unset __prompt_t0
      [ "$ec" -ne 0 ] && fail=1
    else
      ec=0
    fi
    [ "${PROMPT_EXIT_STYLE:-code}" = char ] && ec=0
    if [ "${PROMPT_JOBS:-0}" = 1 ]; then
      j=$(jobs -p)
      if [ -n "$j" ]; then
        n=${j//[!$'\n']/}
        n=$(( ${#n} + 1 ))
      fi
    fi
    __prompt_status "$ec" "$secs" "$n"
    __prompt_base
    __prompt_char "$fail"
    __prompt_git
    [ "${GIT_PROMPT_MR:-1}" = 0 ] || mr=$(git-mr --segment=bash 2>/dev/null)
    PS1="$__prompt_seg_front$__prompt_base_str$__prompt_git_seg${mr:+ $mr}$__prompt_seg_end$__prompt_char_str "
  }
  case ";$PROMPT_COMMAND;" in
    *";__prompt_cmd;"*) ;;
    *) PROMPT_COMMAND="__prompt_cmd${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
  esac

elif [ -n "$ZSH_VERSION" ]; then
  setopt PROMPT_SUBST
  zmodload zsh/datetime zsh/parameter
  autoload -Uz add-zsh-hook
  # shellcheck disable=SC2296,SC2298 # zsh syntax
  __prompt_root=${${(%):-%x}:A:h}
  __prompt_esc_open=$'%{\e['
  __prompt_esc_close='m%}'
  __prompt_uh='%n@%m'
  __prompt_wd='%~'
  __prompt_nl=$'\n'
  __prompt_char_default='%#'
  __prompt_title=''
  # Not ${__prompt_pre:=...}: the '}' of %F{green} would close the expansion.
  if [[ -z ${__prompt_pre-} ]]; then
    __prompt_pre='%B%F{green}%n@%m%f%b:%B%F{blue}%~%f%b'
  fi

  # shellcheck disable=SC2053,SC2296 # zsh syntax: ${~2} is the glob
  __prompt_match() { [[ $1 == ${~2} ]]; }

  __prompt_preexec() { __prompt_t0=$EPOCHREALTIME; }
  __prompt_precmd() {
    local ec=$? mr='' fail=0 n=0
    local -i secs=-1
    if [[ -n ${__prompt_t0-} ]]; then
      (( secs = EPOCHREALTIME - __prompt_t0 ))
      unset __prompt_t0
      (( ec )) && fail=1
    else
      ec=0
    fi
    [[ ${PROMPT_EXIT_STYLE:-code} = char ]] && ec=0
    [[ ${PROMPT_JOBS:-0} = 1 ]] && n=${#jobstates}
    __prompt_status "$ec" "$secs" "$n"
    __prompt_base
    __prompt_char "$fail"
    __prompt_git
    # Prompt escapes are applied after PROMPT_SUBST expansion, so % must be doubled.
    __prompt_git_branch=${__prompt_git_branch//\%/%%}
    [[ ${GIT_PROMPT_MR:-1} = 0 ]] || mr=$(git-mr --segment=zsh 2>/dev/null)
    PS1="$__prompt_seg_front$__prompt_base_str$__prompt_git_seg${mr:+ $mr}$__prompt_seg_end$__prompt_char_str "
  }
  add-zsh-hook preexec __prompt_preexec
  # First in line, so $? is still the user's command status, not another hook's.
  # shellcheck disable=SC2206 # zsh does not word-split
  precmd_functions=(__prompt_precmd ${precmd_functions:#__prompt_precmd})
fi

prompt_theme "${PROMPT_THEME:-default}" || prompt_theme default
