#!/usr/bin/env bash
# Tests of setup-runner.sh.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"
RUNNER="$SCRIPTS/setup-runner.sh"

# gh and curl that fail the test if called.
mkdir -p "$TMP/nobin"
for c in gh curl; do
  printf '#!/bin/sh\necho "%s called" >>"%s/called"\nexit 99\n' "$c" "$TMP" >"$TMP/nobin/$c"
  chmod +x "$TMP/nobin/$c"
done
export PATH="$TMP/nobin:$PATH"

assert_status 0 "--help exits 0" "$RUNNER" --help
assert_contains "$(last_output)" "--dry-run" "help mentions --dry-run"
assert_contains "$(last_output)" "sudo" "help documents sudo for svc.sh"
assert_status 0 "--dry-run exits 0" "$RUNNER" --dry-run
out="$(last_output)"
assert_contains "$out" "config.sh" "dry-run shows config.sh"
assert_contains "$out" "CI_RUNS_ON" "dry-run shows CI_RUNS_ON"
assert_contains "$out" "service" "dry-run shows the service step"
case "$(printf '%s\n' "$out" | tail -1)" in
  *"to register, run only: scripts/setup-runner.sh --register"*) ok ;;
  *) bad "dry-run last line must say to register with only --register" ;;
esac
[ ! -e "$TMP/called" ] && ok || bad "dry-run called gh or curl"
assert_status 1 "no flag fails" "$RUNNER"
assert_status 2 "unknown flag fails" "$RUNNER" --nope
[ ! -e "$TMP/called" ] && ok || bad "gh or curl called"

# --register with fake gh and curl: no network, no real service.
mkdir -p "$TMP/regbin" "$TMP/pkg"
export PATH="$TMP/regbin:$PATH"
printf '#!/bin/sh\necho "config $*" >>"%s/calls"\n' "$TMP" >"$TMP/pkg/config.sh"
printf '#!/bin/sh\necho "svc $*" >>"%s/calls"\n' "$TMP" >"$TMP/pkg/svc.sh"
chmod +x "$TMP/pkg/config.sh" "$TMP/pkg/svc.sh"
tar czf "$TMP/pkg.tgz" -C "$TMP/pkg" config.sh svc.sh
printf '#!/bin/sh\nexec "$@"\n' >"$TMP/regbin/sudo"
chmod +x "$TMP/regbin/sudo"
case "$(uname -s)" in Darwin) os=osx ;; *) os=linux ;; esac
case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; *) arch=x64 ;; esac
sha_of() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
write_gh() {
cat >"$TMP/regbin/gh" <<G
#!/bin/sh
echo "gh \$*" >>"$TMP/calls"
case "\$*" in
  *releases/latest*) printf 'v9.9.9\nnotes <!-- BEGIN SHA $os-$arch -->$1<!-- END SHA $os-$arch -->\n' ;;
  "api repos/o/r --jq .visibility") [ -z "\$FAKE_VISIBILITY_FAILS" ] || exit 1; echo "\${FAKE_VISIBILITY:-private}" ;;
  *registration-token*) echo SECRET-TOKEN ;;
esac
G
chmod +x "$TMP/regbin/gh"
}
write_gh "$(sha_of "$TMP/pkg.tgz")"
cat >"$TMP/regbin/curl" <<C
#!/bin/sh
while [ \$# -gt 0 ]; do case "\$1" in -o) out="\$2"; shift 2 ;; *) shift ;; esac; done
cp "$TMP/pkg.tgz" "\$out"
C
chmod +x "$TMP/regbin/gh" "$TMP/regbin/curl"
rm -f "$TMP/calls"
GH_REPO=o/r assert_status 0 "--register exits 0" "$RUNNER" --register --dir "$TMP/run" --name my-runner
out="$(last_output)"
calls="$(cat "$TMP/calls")"
assert_contains "$calls" "config --unattended --replace --url https://github.com/o/r" "config.sh called"
assert_contains "$calls" "--labels my-runner" "label set"
assert_contains "$calls" "svc install" "service installed"
assert_contains "$calls" "svc start" "service started"
assert_contains "$calls" 'variable set CI_RUNS_ON --repo o/r --body ["self-hosted","my-runner"]' "CI_RUNS_ON set"
assert_not_contains "$out" "SECRET-TOKEN" "token not printed"
# The variable only changes after the service is up.
first_var="$(grep -n 'variable set' "$TMP/calls" | head -1 | cut -d: -f1)"
last_svc="$(grep -n 'svc start' "$TMP/calls" | tail -1 | cut -d: -f1)"
[ "$last_svc" -lt "$first_var" ] && ok || bad "CI_RUNS_ON set before the service started"
# Public repo: refuses before downloading, asking for a token or configuring.
for v in public unknown; do
  rm -f "$TMP/calls"; rm -rf "$TMP/runpub"
  case "$v" in public) envv="FAKE_VISIBILITY=public" ;; *) envv="FAKE_VISIBILITY_FAILS=1" ;; esac
  GH_REPO=o/r assert_status 1 "--register refuses a $v repository" env "$envv" "$RUNNER" --register --dir "$TMP/runpub"
  calls="$(cat "$TMP/calls")"
  assert_not_contains "$calls" "registration-token" "no token for a $v repository"
  assert_not_contains "$calls" "config" "no config for a $v repository"
  assert_not_contains "$calls" "variable set" "no CI_RUNS_ON for a $v repository"
  [ ! -d "$TMP/runpub" ] && ok || bad "runner folder created for a $v repository"
done
GH_REPO=o/r assert_status 1 "--register refuses a public repository" env FAKE_VISIBILITY=public "$RUNNER" --register --dir "$TMP/runpub"
assert_contains "$(last_output)" "o/r is public" "says the repository is public"
# Wrong hash: fails before extracting and configuring.
write_gh "$(printf 0%.0s $(seq 64))"
rm -f "$TMP/calls"
GH_REPO=o/r assert_status 1 "--register fails on a wrong SHA-256" "$RUNNER" --register --dir "$TMP/run3"
assert_contains "$(last_output)" "SHA-256 mismatch" "mismatch message"
assert_not_contains "$(cat "$TMP/calls")" "config" "no config after a bad hash"
# Service that fails: the variable is not written.
printf '#!/bin/sh\nexit 1\n' >"$TMP/pkg/svc.sh"
tar czf "$TMP/pkg.tgz" -C "$TMP/pkg" config.sh svc.sh
write_gh "$(sha_of "$TMP/pkg.tgz")"
rm -f "$TMP/calls"
GH_REPO=o/r assert_status 1 "--register fails when the service fails" "$RUNNER" --register --dir "$TMP/run2"
assert_not_contains "$(cat "$TMP/calls")" "variable set" "no CI_RUNS_ON after a failed service"
# macOS without gtar on PATH: warning (uname and PATH simulated).
printf '#!/bin/sh\ncase "$1" in -s) echo Darwin ;; *) /usr/bin/uname "$@" ;; esac\n' >"$TMP/regbin/uname"
chmod +x "$TMP/regbin/uname"
write_gh "$(sha_of "$TMP/pkg.tgz")"
PATH="$TMP/regbin:/usr/bin:/bin" GH_REPO=o/r assert_status 1 "--register on macOS without gtar still runs" "$RUNNER" --register --dir "$TMP/run4"
assert_contains "$(last_output)" "gtar not found" "warns about missing gtar on macOS"
assert_contains "$(last_output)" "brew install gnu-tar" "says how to install gtar"
printf '#!/bin/sh\nexit 0\n' >"$TMP/regbin/gtar"; chmod +x "$TMP/regbin/gtar"
PATH="$TMP/regbin:/usr/bin:/bin" GH_REPO=o/r assert_status 1 "--register with gtar" "$RUNNER" --register --dir "$TMP/run5"
assert_not_contains "$(last_output)" "gtar not found" "no warning when gtar exists"
rm -f "$TMP/regbin/uname" "$TMP/regbin/gtar"
assert_status 2 "--name without value fails with a message" "$RUNNER" --register --name
assert_contains "$(last_output)" "missing value" "missing value message"
finish
