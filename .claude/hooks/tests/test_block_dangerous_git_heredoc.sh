#!/usr/bin/env bash
# Tests for the block-dangerous-git.sh hook: blocks, heredocs, line continuation, many commits, spaced paths, commit on main.
# shellcheck source=.claude/hooks/tests/dangerous_git_common.sh
source "$(dirname "$0")/dangerous_git_common.sh"

# Blocks, prefixes, abbreviations and command substitution.
blocked "$repo" '{ git push -f; }'
blocked "$repo" 'if true; then git push -f; fi'
blocked "$repo" '! git push -f'
blocked "$repo" 'nice -n 5 git push -f'
blocked "$repo" 'timeout 30 git reset --hard'
blocked "$repo" 'env -u HOME git push -f'
blocked "$repo" 'bash -o pipefail -c "git push -f"'
blocked "$repo" "bash <<<'git push -f'"
blocked "$repo" 'git commit --no-verif -m x'
blocked "$repo" 'git push --forc origin x'
blocked "$repo" 'echo "$(git push -f)"'
blocked "$repo" 'echo `git reset --hard`'
blocked "$repo" 'gh pr -R o/r merge 6'
# `<<` inside quotes or a comment, heredoc to a shell by pipe/source.
blocked "$repo" "echo \"<<EOF\"
git push --force
EOF"
blocked "$repo" "echo x # <<EOF
git reset --hard
EOF"
blocked "$repo" "git commit -m \"x <<EOF\"
git push --force
EOF"
blocked "$repo" "cat <<'EOF' | bash
git push --force
EOF"
blocked "$repo" "cat <<'EOF' | sh
git commit --no-verify -m x
EOF"
blocked "$repo" "source /dev/stdin <<'EOF'
git reset --hard
EOF"
allowed "$repo" "cat > notes.md <<'EOF'
Nunca rode git push --force nem git reset --hard; it's \" odd
EOF"
allowed "$repo" "python3 - <<'EOF'
import subprocess  # git push --force shows up only as text
EOF"
# Line continuation and file checkout.
blocked "$repo" "git \\
push --force"
blocked "$repo" "git commit \\
  --no-verify -m x"
allowed "$repo" 'git checkout main README.md && git commit -m x'
# Half-quoted delimiter, `\ #`, pipe at the end of the line, prefixes, many commits.
blocked "$repo" "cat <<E\"OF\"
EOF
git push --force
E"
blocked "$repo" "cat <<'E'OF
EOF
git reset --hard
E"
blocked "$repo" "cat <<E\\OF
EOF
git add -A
E"
blocked "$repo" 'echo \ # ; git push --force'
blocked "$repo" 'echo a\ #; git reset --hard'
blocked "$repo" "cat <<'EOF' |
git push --force
EOF
bash"
blocked "$repo" 'caffeinate -i /usr/bin/git push --force'
blocked "$repo" 'arch -arm64 /usr/bin/git reset --hard'
blocked "$repo" 'watch /usr/bin/git add -A'
allowed "$repo" 'echo git push --force'
many="$(python3 -c 'print("git commit -m x; " * 3000 + "git push --force")')"
start="$(date +%s)"
blocked "$repo" "$many"
assert_eq yes "$([ $(( $(date +%s) - start )) -lt 10 ] && echo yes)" "many commits are checked fast"

# Quoted paths, with a space.
spaced="$TMP/dir com espaço"; mkdir -p "$spaced"; git clone --quiet "$main_repo" "$spaced/main"
blocked "$repo" "cd \"$spaced/main\" && git commit -m x"
blocked "$repo" "git -C \"$spaced/main\" commit -m x"
blocked "$repo" "git -C '$main_repo' commit -m x"

# A commit on main is blocked.
git -C "$repo" switch --quiet main
blocked "$repo" 'git commit -m "x"'
blocked "$repo" "git -C $repo commit -m x"
assert_contains "$(run "$repo" 'git commit -m x' 2>&1 || true)" "never commit on main" "explains the main block"
finish
