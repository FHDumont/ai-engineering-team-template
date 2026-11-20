#!/usr/bin/env bash
#: setup-runner.sh: register a self-hosted runner on the repo owner's machine.
#:
#: Usage: setup-runner.sh --dry-run
#:        setup-runner.sh --register [--dir folder] [--name name] [--label label]
#:
#: --dry-run   prints the steps a registration would take; runs nothing, no
#:             network, no gh.
#: --register  downloads the runner package for this OS/architecture, asks
#:             GitHub for a registration token (never printed or stored),
#:             verifies the package SHA-256 against the release notes,
#:             configures, installs and starts the service (on Linux svc.sh
#:             needs root, so it is called through sudo: the user must be a sudoer), and only then sets
#:             the repository variable CI_RUNS_ON. With no running service the
#:             variable stays unset and CI keeps using ubuntu-latest. Run it
#:             only after the repo owner's ok on a choice board. Refuses a
#:             public repository (or one whose visibility cannot be read):
#:             the runner would run the code of any pull request.
#: --dir       install folder (default ~/actions-runner-<repo>)
#: --name      runner name (default: this machine's hostname)
#: --label     runner label (default: the runner name)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$HERE/lib/common.sh"

dry=0 reg=0 dir="" name="" label=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) print_help "$0"; exit 0 ;;
    --dry-run) dry=1; shift ;;
    --register) reg=1; shift ;;
    --dir) [ $# -ge 2 ] || die "missing value for --dir" 2; dir="$2"; shift 2 ;;
    --name) [ $# -ge 2 ] || die "missing value for --name" 2; name="$2"; shift 2 ;;
    --label) [ $# -ge 2 ] || die "missing value for --label" 2; label="$2"; shift 2 ;;
    *) die "unknown option: $1 (see --help)" 2 ;;
  esac
done

[ "$dry" = 1 ] || [ "$reg" = 1 ] || die "pass --dry-run to see the steps or --register to register the runner" 1

if [ "$dry" = 1 ]; then
cat <<'S'
dry-run: a self-hosted runner registration would:
1. Download the GitHub Actions runner package for this machine's OS and architecture.
2. Request a registration token for the repository.
3. Run ./config.sh --url <repo-url> --token <token> to configure the runner.
4. Install and start the runner as a service (./svc.sh install && ./svc.sh start).
5. Set the repository variable CI_RUNS_ON to the runner label.
Nothing was executed.
to register, run only: scripts/setup-runner.sh --register
S
exit 0
fi

require_cmd gh curl tar
slug="$(repo_slug)"
# A self-hosted runner on a public repository runs the code of any pull request,
# forks included, on this machine: only a repository read back as private gets one.
visibility="$(gh api "repos/$slug" --jq .visibility 2>/dev/null)" || visibility=""
case "$visibility" in
  private|internal) ;;
  public) die "refused: $slug is public: a self-hosted runner would run the code of any pull request, forks included, on this machine; keep CI on GitHub-hosted runners (CI_RUNS_ON unset)" ;;
  *) die "refused: could not read the visibility of $slug: the runner is only registered on a repository read back as private" ;;
esac
repo="${slug#*/}"
[ -n "$name" ] || name="$(hostname -s)"
[ -n "$label" ] || label="$name"
[ -n "$dir" ] || dir="$HOME/actions-runner-$repo"

case "$(uname -s)" in
  Darwin) os=osx ;;
  Linux) os=linux ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac
# actions/upload-pages-artifact uses gtar on macOS; without it the deploy fails (exit 127).
if [ "$os" = osx ] && ! command -v gtar >/dev/null 2>&1; then
  echo "warning: gtar not found in PATH (macOS): upload-pages-artifact will fail; install it with: brew install gnu-tar" >&2
fi
case "$(uname -m)" in
  arm64|aarch64) arch=arm64 ;;
  x86_64|amd64) arch=x64 ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

info "runner: $name (label $label) for $slug in $dir"
release="$(gh api repos/actions/runner/releases/latest --jq '.tag_name + "\n" + .body')"
version="$(printf '%s\n' "$release" | head -1)"
version="${version#v}"
[ -n "$version" ] || die "could not read the latest runner version"
mkdir -p "$dir"
tarball="actions-runner-$os-$arch-$version.tar.gz"
curl -sSfL -o "$dir/$tarball" "https://github.com/actions/runner/releases/download/v$version/$tarball"
# SHA-256 published in the release notes (<!-- BEGIN SHA os-arch -->hash<!-- END SHA os-arch -->).
want="$(printf '%s\n' "$release" | sed -n "s/.*<!-- BEGIN SHA $os-$arch -->\\([0-9a-f]\\{64\\}\\)<!-- END SHA $os-$arch -->.*/\\1/p" | head -1)"
if [ -z "$want" ]; then rm -f "$dir/$tarball"; die "no SHA-256 for $os-$arch in the release notes"; fi
if command -v sha256sum >/dev/null; then got="$(sha256sum "$dir/$tarball" | cut -d' ' -f1)"; else got="$(shasum -a 256 "$dir/$tarball" | cut -d' ' -f1)"; fi
if [ "$got" != "$want" ]; then rm -f "$dir/$tarball"; die "SHA-256 mismatch for $tarball (expected $want, got $got)"; fi
tar xzf "$dir/$tarball" -C "$dir"
rm -f "$dir/$tarball"

token="$(gh api -X POST "repos/$slug/actions/runners/registration-token" --jq .token)"
[ -n "$token" ] || die "could not get a registration token"
(
  cd "$dir"
  ./config.sh --unattended --replace --url "https://github.com/$slug" \
    --token "$token" --name "$name" --labels "$label"
  if [ "$os" = linux ]; then sudo ./svc.sh install; sudo ./svc.sh start; else ./svc.sh install; ./svc.sh start; fi
)
# CI uses the runner only once the service is up.
gh variable set CI_RUNS_ON --repo "$slug" --body "[\"self-hosted\",\"$label\"]"
info "ok: runner $name registered; CI_RUNS_ON set to [\"self-hosted\",\"$label\"]"
