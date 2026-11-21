# shellcheck shell=bash
# R1 of check-bats: silent_assertions <file>... prints file:line: text of each bats assertion that
# cannot fail the test in bash 3.2. Ported from the arness repo checks (tests/repo.bats).
#
# Prints file:line of each assertion that cannot fail the test. One rule: a line that
# starts with `[`, `[[`, `((` or `!` is an assertion and must end with `|| false` (or
# a `|| { ...; false; }` block, `return N`/`exit N` with N > 0 also count, on one line
# or several), with only checks joined by `||` before it (`|| echo` in between makes
# it never run); control flow is written as `if`. A `;` outside quotes, `[[ ]]`, `(( ))`,
# `$( )` and that block always flags the line. The only exception is a lone `[ ... ]`
# with no `&&` or `;`, a plain command that fails the test in every bash, alone or
# with each `||` followed by `[ ... ]`, `skip`, `return`, `continue` or `exit`.
# if/elif/while/until conditions do not start with those tokens, so they are never
# matched, and neither is a list that starts with another command
# (`grep -q a f && grep -q b f`), by design. The rule looks at the logical line: lines
# ending in `\`, `&&`, `||` or `|` joined with the next, quoted strings and the
# trailing comment removed line by line, a `|| {` block joined up to its `}`, the
# inside of `${ }`, `[[ ]]`, `(( ))` and `$( )` emptied, heredoc bodies skipped (a
# heredoc or a `|| {` block still open at the end of a file is reported).
# Known limits: an odd number of `"` inside '...' can confuse the quote stripping; a
# `]]`, `))` or `)` nested inside a check (`[[:digit:]]` inside `[[ ]]`) closes it too
# early; and `( ... )` and `{ ... }` other than the final block are not emptied.
silent_assertions() {
  awk '
    # The line without quoted strings and trailing comment; a quoted heredoc
    # delimiter (<<"EOF", or in single quotes) is unquoted first so it survives.
    function clean(s,   w) {
      while (match(s, /<<-?[ \t]*["\047][A-Za-z_][A-Za-z0-9_]*["\047]/)) {
        w = substr(s, RSTART, RLENGTH); gsub(/["\047 \t-]/, "", w)
        s = substr(s, 1, RSTART - 1) w substr(s, RSTART + RLENGTH)
      }
      gsub(/"([^"\\]|\\.)*"/, "\"\"", s); gsub(/\047[^\047]*\047/, "\047\047", s)
      sub(/^#.*$/, "", s); sub(/[ \t]#.*$/, "", s)
      return s
    }
    # s with what is between each open and its close emptied, so a || or && inside
    # [[ ]], (( )) or $( ) is not taken for the list operator.
    function blank(s, op, ed,   i, j, out) {
      out = ""
      while ((i = index(s, op)) > 0) {
        j = index(substr(s, i + length(op)), ed)
        if (j == 0) break
        out = out substr(s, 1, i - 1) op " " ed
        s = substr(s, i + length(op) + j - 1 + length(ed))
      }
      return out s
    }
    # A part of a || list after a lone [ ] that still fails the test: [ ] or a jump.
    function failing_tail(p) {
      return p ~ /^[ \t]*\[[ \t]/ || p ~ /^[ \t]*(skip|return|continue|exit)([ \t]|$)/
    }
    function silent(s,   n, i, p) {
      if (s !~ /^[ \t]*(\[|\(\(|![ \t])/) return 0
      s = blank(blank(blank(blank(s, "${", "}"), "$(", ")"), "[[", "]]"), "((", "))")
      gsub(/\$\{ \}/, "$v", s)
      # A final block counts as || false only when it ends in a command that fails.
      sub(/\|\|[ \t]*\{([^{}]*;)?[ \t]*(false|return[ \t]+[1-9][0-9]*|exit[ \t]+[1-9][0-9]*)[ \t]*;?[ \t]*\}[ \t]*$/, "|| false", s)
      if (s ~ /;/) return 1
      # Before the final || false, every || part must be a check: `|| echo` in between
      # always succeeds, so the || false after it never runs.
      if (s ~ /\|\|[ \t]*false[ \t]*$/) {
        n = split(s, p, /\|\|/)
        for (i = 2; i < n; i++) if (p[i] !~ /^[ \t]*(\[|\(\(|![ \t])/) return 1
        return 0
      }
      if (s !~ /^[ \t]*\[[ \t]/ || s ~ /&&/) return 1
      # A lone [ ], alone or with each || followed by another [ ] or skip/return/continue/exit.
      n = split(s, p, /\|\|/)
      for (i = 2; i <= n; i++) if (!failing_tail(p[i])) return 1
      return 0
    }
    function unterminated() {
      if (tag != "") print file ": unterminated heredoc " tag
      if (block) print file ": unterminated || { block"
    }
    FNR == 1 { unterminated(); tag = ""; line = ""; cl = ""; block = 0; file = FILENAME }
    tag != "" { if ($0 ~ "^[ \t]*" tag "[ \t]*$") tag = ""; next }
    # line is the raw logical line, for the report; cl the same line cleaned line by
    # line, so a comment on one line does not hide the lines joined after it.
    {
      c = clean($0)
      if (c ~ /<<-?[ \t]*[A-Za-z_]/ && c !~ /<<</) {
        tag = c; sub(/.*<<-?[ \t]*/, "", tag); sub(/[^A-Za-z0-9_].*$/, "", tag)
      }
      line = line $0; cl = cl c
    }
    c ~ /\\$/ { sub(/\\$/, "", line); sub(/\\$/, "", cl); next }
    cl ~ /(&&|\|)[ \t]*$/ { next }
    # A `|| {` block written over several lines is joined, with `;`, up to its `}`.
    {
      c = cl
      if ((block || c ~ /\|\|[ \t]*\{/) && gsub(/\{/, "{", c) > gsub(/\}/, "}", c)) {
        block = 1; line = line ";"; cl = cl ";"; next
      }
      block = 0
    }
    {
      if (silent(cl)) print FILENAME ":" FNR ": " line
      line = ""; cl = ""
    }
    END { unterminated() }
  ' "$@"
}
