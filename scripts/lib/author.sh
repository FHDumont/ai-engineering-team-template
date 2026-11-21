#!/usr/bin/env bash
# Authorship header for every comment an agent or a bot posts (the owner, the
# manager, the child sessions and the bots share one GitHub account). One line:
#   **De:** <role> · **Para:** <role> · **Pedido:** <ask_id or what> · **Responde a:** <link or —>
# Roles: dono, gerenciadora, fase #n, revisor, bot <name>.
# A comment without the header is the owner's. Source it; it needs common.sh.

# Who the running session is: AUTHOR_FROM wins; else "fase #n" on a phase branch,
# "gerenciadora" elsewhere.
author_from() {
  [ -z "${AUTHOR_FROM:-}" ] || { printf '%s' "$AUTHOR_FROM"; return; }
  local n
  n="$(issue_from_branch "$(current_branch)" 2>/dev/null || true)"
  if [ -n "$n" ]; then printf 'fase #%s' "$n"; else printf 'gerenciadora'; fi
}

# author_header <to> <request> [replies-to]: prints the header line (no newline).
author_header() {
  local to="$1" what="$2" reply="${3:-}"
  printf '**De:** %s · **Para:** %s · **Pedido:** %s · **Responde a:** %s' \
    "$(author_from)" "$to" "$what" "${reply:-—}"
}

# has_author_header: reads a text on stdin; 0 when a line opens with the header.
has_author_header() {
  grep -qE '^\*\*De:\*\* .+ · \*\*Para:\*\* .+ · \*\*Pedido:\*\* .+ · \*\*Responde a:\*\* .+'
}
