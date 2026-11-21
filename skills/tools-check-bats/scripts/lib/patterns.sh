# shellcheck shell=bash
# Pattern rules of check-bats (R4-R11): heuristics, one awk pass per file list.
#
# pattern_findings <kind> <allowed> <file>...
#   kind     test (bats files and their .bash helpers) or script (.sh files)
#   allowed  space-separated commands allowed in scripts (R9); empty skips R9
# Prints "<rule> <file>:<line> <text>" for each finding, in file and line order.
#
# Every rule skips comment lines and heredoc bodies (test fixtures live there). A line that carries
# "check-bats: ignore" is skipped for every rule, or only for the rules listed after it
# ("# check-bats: ignore R6 R8"). The regexes below are written so they do not match their own text
# (sed[ ]-i, h[e]ad...): this file passes its own check.
pattern_findings() {
  local kind="$1" allowed="$2"
  shift 2
  [ "$#" -gt 0 ] || return 0
  KIND="$kind" ALLOWED="$allowed" awk '
    BEGIN {
      kind = ENVIRON["KIND"]
      n = split(ENVIRON["ALLOWED"], a, /[ ,]+/)
      for (i = 1; i <= n; i++) if (a[i] != "") allowed[a[i]] = 1
      r9 = (n > 0 && ENVIRON["ALLOWED"] ~ /[^ ,]/)
      # External commands R9 watches; shell builtins are never reported.
      nw = split("awk basename cat chmod cksum comm cp cut date dirname env expr file find grep gzip " \
        "head jq ln mkdir mktemp mv od paste perl python3 readlink realpath rev rg rm sed seq sort " \
        "stat tac tail tar tee touch tr uniq wc xargs", watch, " ")
    }
    function report(rule, ln, text) {
      if (ignored(text, rule)) return
      sub(/^[ \t]+/, "", text)
      out[++no] = rule " " file ":" ln " " text; at[no] = ln
    }
    function ignored(text, rule,   m) {
      if (index(text, "check-bats: ignore") == 0) return 0
      m = substr(text, index(text, "check-bats: ignore") + 18)
      if (m !~ /^[ \t]*R[0-9]/) return 1
      return (" " m " ") ~ ("[ ,]" rule "[ ,]")
    }
    # The line without quoted strings, for command-position checks.
    function unquote(s) {
      gsub(/"([^"\\]|\\.)*"/, "\"\"", s); gsub(/\047[^\047]*\047/, "\047\047", s)
      return s
    }
    # c at command position: first on the line, after an operator or "$(", or after a keyword that runs
    # the next command (if, while, then, bats run...).
    function cmd_at(s, c) {
      return s ~ ("(^|[;&|(`{!]|\\$\\()[ \t]*" c "([ \t;)]|$)") \
        || s ~ ("(^|[^A-Za-z0-9_])(if|elif|while|until|then|do|else|run)[ \t]+" c "([ \t;)]|$)")
    }
    # Rules on one code line (not a comment, not in a heredoc).
    # Commands are matched on s1, the line without literal text: single-quoted text (a grep pattern, an awk
    # program) and double-quoted text with no "$(" in it are emptied, while "$(...)" stays, since it is code.
    # Bash 4 expansions are matched anywhere, quotes included ("${x,,}", "${a[-1]}").
    function line_rules(ln, raw,   s, s1, i) {
      s = unquote(raw)
      s1 = raw; gsub(/\047[^\047]*\047/, "\047\047", s1); gsub(/"([^"\\$]|\\.|\$[^(])*"/, "\"\"", s1)
      if (s1 ~ /readlink[ ]-f|sed[ ]-i|date[ ]-d|grep[ ]-P|ma[p]file|read[a]rray|declare[ ]-[An]|stat[ ]-c|[&][>]>|(^|[^|])[|][&]([^&]|$)/ \
          || raw ~ /\$\{[A-Za-z_]+(,,|\^\^)\}|\[[-]1\]\}/)
        report("R4", ln, raw)
      if (raw ~ /gen[s]ub|asort[i]?\(|strf[t]ime|sys[t]ime|PROC[I]NFO/)
        report("R5", ln, raw)
      if (s1 ~ /(^|[^|])[|][ \t]*(grep[ \t][^|]*-[A-Za-z]*q|h[e]ad([ \t]|$))/)
        report("R6", ln, raw)
      if (kind == "script") {
        if (!r9) return
        for (i = 1; i <= nw; i++)
          if (!(watch[i] in allowed) && cmd_at(s1, watch[i])) report("R9", ln, raw " (uses " watch[i] ")")
        return
      }
      if (!homeset && raw ~ /\$\{?HOME([^A-Za-z0-9_]|$)/ && raw !~ /HOME=/) report("R7", ln, raw)
      if (raw ~ /(^|[^A-Za-z0-9_.$}-])\/tmp\//) report("R7", ln, raw)
      if ((cmd_at(s1, "gh") && !stub["gh"]) || (cmd_at(s1, "curl") && !stub["curl"]) || (cmd_at(s1, "wget") && !stub["wget"]))
        report("R8", ln, raw)
      if (raw ~ /git[ \t].*(clone|fetch|pull|push|ls-remote)[ \t].*(https?:\/\/|git@)/) report("R8", ln, raw)
      if (s1 ~ /(^|[;&|({ \t])slee[p][ \t]+[0-9]/ || cmd_at(s1, "time[o]ut") || raw ~ /\$\{?SEC[O]NDS|date[ \t]+\+%s/)
        report("R10", ln, raw)
      if (s ~ /(^|[;&|{ \t])sk[i]p[ \t]*($|;|&&|\|\||\})/) report("R11", ln, raw)
      if (raw ~ /^[ \t]*@test[ \t]+["\047][A-Z][a-z]/) report("R11", ln, raw)
    }
    # A file is checked once it is read whole: R7 and R8 need to know what the file defines. First pass:
    # which lines are code (not a comment, not a heredoc body), and what the code does (mktemp, cleanup,
    # HOME). Stubs count anywhere, heredocs included: that is where tests write them.
    function flush(   i, j, raw, c, tag, mk, td, t, a) {
      if (file == "") return
      stub["gh"] = stub["curl"] = stub["wget"] = 0
      mk = 0; td = 0; homeset = 0; tag = ""
      for (i = 1; i <= nl; i++) {
        raw = L[i]; code[i] = 0
        if (raw ~ /bin\/gh([^A-Za-z0-9_]|$)/) stub["gh"] = 1
        if (raw ~ /bin\/curl([^A-Za-z0-9_]|$)/) stub["curl"] = 1
        if (raw ~ /bin\/wget([^A-Za-z0-9_]|$)/) stub["wget"] = 1
        if (tag != "") { if (raw ~ ("^[ \t]*" tag "[ \t]*$")) tag = ""; continue }
        if (raw ~ /^[ \t]*#/) continue
        code[i] = 1
        c = unquote(raw)
        if (c ~ /<<-?[ \t]*[A-Za-z_"\047]/ && c !~ /<<</) {
          tag = raw; sub(/.*<<-?[ \t]*/, "", tag); gsub(/["\047]/, "", tag); sub(/[^A-Za-z0-9_].*$/, "", tag)
        }
        if (!mk && raw ~ /mktemp/) mk = i
        if (raw ~ /^[ \t]*teardown[ \t]*\(\)|rm[ \t]+(-[A-Za-z]*[rR][A-Za-z]*f|-[A-Za-z]*f[A-Za-z]*[rR]|-[rR][ \t]+-f|-f[ \t]+-[rR])/) td = 1
        # HOME set for the test (a command of its own, or exported), not for one command (env HOME=x cmd).
        if (raw ~ /^[ \t]*(export[ \t]+)?HOME=|[;{][ \t]*(export[ \t]+)?HOME=/) homeset = 1
      }
      for (i = 1; i <= nl; i++) if (code[i]) line_rules(i, L[i])
      if (kind == "test" && file ~ /\.bats$/ && mk && !td)
        report("R7", mk, L[mk] " (mktemp with no teardown or rm -rf)")
      # In line order (the file-level R7 comes last); insertion sort keeps equal lines in rule order.
      for (i = 2; i <= no; i++) {
        t = out[i]; a = at[i]
        for (j = i - 1; j >= 1 && at[j] > a; j--) { out[j + 1] = out[j]; at[j + 1] = at[j] }
        out[j + 1] = t; at[j + 1] = a
      }
      for (i = 1; i <= no; i++) print out[i]
      no = 0; nl = 0
    }
    FNR == 1 { flush(); file = FILENAME }
    { L[++nl] = $0 }
    END { flush() }
  ' "$@"
}
