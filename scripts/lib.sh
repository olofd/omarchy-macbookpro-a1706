# Shared by the installers (sourced, not run): write a file or a marked block of a config file only when it
# would change. Run again on an up-to-date machine, an installer then changes nothing, and says so.
# CHANGED is set to 1 by any write.
# shellcheck disable=SC2034  # read by the installers that source this file
CHANGED=0

# put_file SRC DEST MODE: install SRC (carriage returns removed) as DEST with MODE (e.g. 755), if different.
put_file() {
  _pf=$(mktemp)
  tr -d '\r' < "$1" > "$_pf"
  if [ -f "$2" ] && cmp -s "$_pf" "$2" && [ "$(stat -c %a "$2")" = "$3" ]; then rm -f "$_pf"; return 0; fi
  mkdir -p "$(dirname "$2")"
  install -m "$3" "$_pf" "$2"
  rm -f "$_pf"
  CHANGED=1
}

# put_text DEST MODE: like put_file, with the content on standard input.
put_text() {
  _pt=$(mktemp)
  cat > "$_pt"
  put_file "$_pt" "$1" "$2"
  rm -f "$_pt"
}

# put_block FILE BEGIN END <<EOF: put standard input between the marker lines BEGIN and END in FILE: in place if
# the markers are there (so blocks of different installers keep their order), else at the end after a blank line.
# Feed it with a heredoc or a < redirect, never a pipe: a pipe runs it in a subshell and CHANGED is lost.
put_block() {
  _pb=$(mktemp); _pn=$(mktemp)
  { printf '%s\n' "$2"; cat; printf '%s\n' "$3"; } > "$_pn"
  if grep -qxF -- "$2" "$1" && ! grep -qxF -- "$3" "$1"; then
    rm -f "$_pb" "$_pn"; echo "$1: '$2' has no end marker; fix the file by hand" >&2; return 1
  fi
  awk -v b="$2" -v e="$3" -v blk="$_pn" '
    function emit(  l) { while ((getline l < blk) > 0) print l; close(blk) }
    $0 == b { skip = 1; emit(); done = 1; next }
    skip { if ($0 == e) skip = 0; next }
    { print }
    END { if (!done) { print ""; emit() } }' "$1" > "$_pb"
  if cmp -s "$_pb" "$1"; then rm -f "$_pb" "$_pn"; return 0; fi
  cat "$_pb" > "$1"     # rewrite in place: the file keeps its owner and mode
  rm -f "$_pb" "$_pn"
  CHANGED=1
}

# drop_block FILE BEGIN END: remove the marked block (and the blank line put_block added before it).
drop_block() {
  [ -f "$1" ] || return 0
  _db=$(mktemp)
  awk -v b="$2" -v e="$3" '
    $0 == b { skip = 1; pend = 0; next }
    skip { if ($0 == e) skip = 0; next }
    $0 == "" { if (pend) print ""; pend = 1; next }
    { if (pend) print ""; pend = 0; print }
    END { if (pend) print "" }' "$1" > "$_db"
  if cmp -s "$_db" "$1"; then rm -f "$_db"; return 0; fi
  cat "$_db" > "$1"; rm -f "$_db"
  CHANGED=1
}

# needs_reboot WHAT: say that WHAT takes effect after a reboot, and tell setup.sh (A1706_REBOOT_FILE) too.
needs_reboot() {
  echo "Reboot for $1 to take effect."
  if [ -n "${A1706_REBOOT_FILE:-}" ]; then echo "$1" >> "$A1706_REBOOT_FILE"; fi
}
