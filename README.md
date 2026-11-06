# shell-prompt

bash와 zsh에서 같은 모양으로 동작하는 프롬프트 설정이다. git 상태, MR/PR 표시, 직전 명령의 종료 코드와 실행 시간을 보여 준다.

```
✘1 12s dev1@dev-1:~/repo (main ↑2 ↓1) !289 ✔$
```

| 구간 | 언제 나오나 |
|---|---|
| `✘1` (빨강) | 직전 명령이 0이 아닌 코드로 끝났을 때 |
| `12s` (노랑) | 직전 명령이 `PROMPT_DURATION_MIN`초 이상 걸렸을 때 |
| `✦2` (청록) | `PROMPT_JOBS=1`이고 백그라운드 작업이 있을 때 |
| `(main ↑2 ↓1)` | git 저장소 안. [git 구간](#git-구간) 참고 |
| `!289 ✔` | `git-mr`이 `PATH`에 있고 현재 브랜치에 MR/PR이 있을 때 |

빈 줄에서 Enter를 누르거나 프롬프트에서 Ctrl-C를 누르면 종료 코드와 실행 시간 구간은 사라진다.

## git 구간

기본으로는 브랜치 이름, upstream 차이, 진행 중인 작업, 충돌 파일 수만 나온다. 나머지 요소는 `PROMPT_GIT_SHOW`에 이름을 적어 켠다.

```bash
PROMPT_GIT_SHOW='staged unstaged untracked'   # 쉼표로 구분해도 됨. all은 전부
```
```
dev1@dev-1:~/repo (main ●1 ✎2 ?3 ↑2 ↓1)$
```

| 이름 | 기호 | 의미 |
|---|---|---|
| (항상) | `↑2` / `↓1` | upstream보다 2커밋 앞섬 / 1커밋 뒤처짐 |
| (항상) | `REBASE 2/5`, `MERGING` 등 | 진행 중인 작업. `AM`, `CHERRY-PICKING`, `REVERTING`, `BISECTING`도 있음 |
| (항상) | `⚠1` | 충돌 난 파일 1개 |
| (항상) | `detached@a1b2c3d` | 브랜치 대신 커밋을 체크아웃한 상태. 브랜치 이름 자리에 나옴 |
| `staged` | `●2` | 스테이징한 파일 2개 |
| `unstaged` | `✎2` | 스테이징하지 않은 변경이 있는 파일 2개 |
| `untracked` | `?3` | 추적하지 않는 항목 3개. 추적 안 하는 디렉터리는 1개로 셈 |
| `stash` | `⚑1` | stash 1개 |
| `new` | `new` | 아직 커밋이 없는 저장소 |
| `clean` | `✔` | 괄호 안에 다른 기호가 하나도 없음 |

기호는 해당 상태일 때만 나온다. 한 파일을 스테이징한 뒤 다시 고치면 `●`와 `✎`에 모두 센다. `untracked`를 켜지 않으면 추적하지 않는 파일을 찾지 않는다(`git status -uno`). 켰을 때 세는 방식은 git의 `status.showUntrackedFiles` 설정을 따른다.

## 빠른 시작

1. 저장소 파일을 `~/.config/shell`에 연결한다.
   ```bash
   mkdir -p ~/.config/shell
   ln -sfn ~/ahngbeom/shell-prompt/prompt.sh ~/.config/shell/prompt.sh
   ```
2. `~/.bashrc`와 `~/.zshrc` 끝에 다음 줄을 넣는다. bash에서는 `PS1`을 정하는 줄보다 뒤에 있어야 한다.
   ```bash
   [ -f ~/.config/shell/prompt.sh ] && . ~/.config/shell/prompt.sh
   ```
3. 새 터미널을 연다. 이미 열린 셸에서 다시 source하면 bash는 첫 프롬프트에서 기록한 `PS1`을 기반 프롬프트로 쓴다.

`claude-statusline`의 `shell/git-prompt.sh`와 함께 source하지 않는다. 둘 다 `PS1`을 다시 쓰는 훅을 등록한다.

## 설정

셸 rc 파일에서 `prompt.sh`를 source하기 전이나 후에 환경 변수로 정한다.

| 키 | 기본값 | 설명 |
|---|---|---|
| `PROMPT_DURATION_MIN` | `3` | 실행 시간을 보여 줄 최소 초 |
| `PROMPT_EXIT_STYLE` | `code` | `char`이면 `✘1` 대신 프롬프트 기호(`$`, `%`)를 빨갛게 표시 |
| `PROMPT_HOST` | `always` | `auto`이면 SSH, 컨테이너, root일 때만 `사용자@호스트:` 표시 |
| `PROMPT_JOBS` | `0` | `1`이면 백그라운드 작업 수 `✦N` 표시 |
| `PROMPT_TWO_LINE` | `0` | `1`이면 프롬프트 기호를 다음 줄로 내림 |
| `PROMPT_GIT_SHOW` | 빈 값 | git 구간에 켤 요소. [git 구간](#git-구간) 참고 |
| `PROMPT_GIT_IGNORE` | 빈 값 | git 구간을 끌 저장소. `:`로 구분한 glob을 저장소 최상위 경로와 비교 |
| `GIT_PROMPT_MR` | `1` | `0`이면 `git-mr` MR/PR 구간을 숨김 |

```bash
PROMPT_EXIT_STYLE=char PROMPT_HOST=auto PROMPT_JOBS=1 PROMPT_TWO_LINE=1
PROMPT_GIT_IGNORE="$HOME:$HOME/vendor/*"
```
```
✦1 ~/repo (main ↑2)
$
```

기반 프롬프트(`사용자@호스트:경로`)는 bash에서 source 시점의 `PS1`, zsh에서 `__prompt_pre` 변수를 쓴다. zsh에서 바꾸려면 source하기 전에 `__prompt_pre`를 정한다.

`PROMPT_HOST=auto`는 기반 프롬프트를 내장 모양으로 다시 만든다. bash에서는 `PS1` 앞의 창 제목 설정(`\[\e]0;...\a\]`)만 이어받고, 그 밖에 직접 꾸민 `PS1`이나 `__prompt_pre`는 쓰지 않는다. SSH 여부는 `SSH_CONNECTION`, `SSH_TTY`, 컨테이너 여부는 `container` 변수와 `/.dockerenv`, `/run/.containerenv`로 판단하며, source할 때 한 번만 확인한다.

`PROMPT_GIT_IGNORE`의 glob에는 `~`가 아니라 `$HOME`을 쓴다. 맞는 저장소에서는 `git status`를 실행하지 않는다.

## 요구 사항

- bash 5.0 이상(`EPOCHREALTIME`, `PS0`) 또는 zsh 5.x
- git. stash 개수는 git 2.35 이상에서 나온다
- `git-mr`(선택). [claude-statusline](https://github.com/Ahngbeom/claude-statusline)의 `bin/git-mr`

## 테스트

```bash
tests/run.sh
```

상태별 git 저장소를 임시로 만들어 git 구간을 검사하고, 대화형 bash와 zsh를 띄워 `PS1`을 검사한다. zsh가 `PATH`에 없으면 zsh 검사는 건너뛴다. 설치되지 않은 zsh 바이너리는 `ZSH=/path/to/zsh`로 지정하고, 모듈과 함수 경로가 기본값과 다르면 `MODULE_PATH`와 `FPATH`도 함께 넘긴다.
