# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 weegs710

def cache-dir []: nothing -> string {
  [($env.XDG_CACHE_HOME? | default $"($env.HOME)/.cache") "shop"] | path join
}

def choices-path []: nothing -> string {
  [(cache-dir) "choices.json"] | path join
}

# nushell routes a script's stdout through its own pipeline, so is-terminal --stdout is false even on a real tty.
def palette []: nothing -> record {
  if (is-terminal --stderr) and ($env.NO_COLOR? | is-empty) {
    {
      b: (ansi attr_bold),
      d: (ansi attr_dimmed),
      r: (ansi red),
      g: (ansi green),
      c: (ansi cyan),
      z: (ansi reset),
    }
  } else {
    { b: "", d: "", r: "", g: "", c: "", z: "" }
  }
}

def die [msg: string, detail?: string] {
  let c = (palette)
  print -e $"($c.r)($c.b)shop:($c.z) ($msg)"
  if $detail != null {
    print -e $"($c.d)($detail)($c.z)"
  }
  exit 1
}

def hint [msg: string] {
  let c = (palette)
  print -e $"($c.d)($msg)($c.z)"
}

def interactive []: nothing -> bool {
  (is-terminal --stdin) and (is-terminal --stderr)
}

# nushell repeats the header row at the bottom of any table past 25 rows.
def render [v: any]: nothing -> string {
  $env.config.footer_mode = "never"
  $v | table --theme thin --index false
}

def locate [cmd: string]: nothing -> list<string> {
  let r = (^nix-locate --minimal --at-root --whole-name $"/bin/($cmd)" | complete)
  if $r.exit_code == 0 { $r.stdout | lines | where ($it | str trim | is-not-empty) } else { [] }
}

def knows-attr [attr: string]: nothing -> bool {
  let apply = $"f: f \"($attr)\""
  let r = (^nix eval --json -f $env.SHOP_ENGINE knows --apply $apply | complete)
  if $r.exit_code != 0 { false } else { $r.stdout | from json }
}

def raw-version-table [attr: string]: nothing -> table {
  let apply = $"f: f \"($attr)\""
  let r = (^nix eval --json -f $env.SHOP_ENGINE versionTable --apply $apply | complete)
  if $r.exit_code != 0 {
    die $"nix eval failed" ($r.stderr | str trim)
  }
  $r.stdout | from json | select version revision
}

def version-table [attr: string]: nothing -> table {
  let tbl = (raw-version-table $attr)
  if ($tbl | is-empty) {
    die $"'($attr)' has no version axis"
  }
  $tbl
}

def reject-nested [attr: string] {
  if ($attr | str contains ".") {
    die $"'($attr)' is a nested attribute -- the version index only covers top-level attributes"
  }
}

# nix reads a bare 1.5 in a selection path as a list index, so every component is quoted.
def sel-path [parts: list<string>]: nothing -> string {
  $parts | each {|p| $"\"($p)\"" } | str join "."
}

def load-cache []: nothing -> record {
  let p = (choices-path)
  if ($p | path exists) { open $p } else { {} }
}

def write-cache [cur: record] {
  mkdir (cache-dir)
  $cur | save --force (choices-path)
}

# `attr.output` is the form -p prints, so the output is everything after the last dot.
def split-choice [s: string]: nothing -> record {
  let parts = ($s | split row ".")
  { attr: ($parts | drop 1 | str join "."), output: ($parts | last) }
}

# Entries written by older versions are bare `attr.output` strings.
def as-choice [v: any]: nothing -> record {
  if (($v | describe) | str starts-with "record") { $v } else { split-choice $v }
}

def choice-label [c: record]: nothing -> string {
  if ($c.output | is-empty) { $c.attr } else { $"($c.attr).($c.output)" }
}

def save-choice [cmd: string, picked: record] {
  let entry = { attr: $picked.attr, output: $picked.output, picked: (date now | format date "%Y-%m-%d") }
  write-cache (load-cache | merge { ($cmd): $entry })
}

def announce [cmd: string, picked: record] {
  # The attribute fallback already said what it did.
  if $picked.how == "attribute" { return }
  hint $"($cmd) -> (choice-label $picked) \(($picked.how)\)"
}

# A first-candidate guess would be cached and reused silently, so a missing terminal is an error.
def refuse-to-guess [cmd: string, ordered: list<string>] {
  let first = ($ordered | first)
  let listed = ($ordered | each {|c| $"  ($c)" } | str join "\n")
  die $"($ordered | length) packages ship /bin/($cmd), nothing is remembered for it, and there is no terminal to ask on" $"candidates:\n($listed)\nname one and run it, remembering nothing:\n  shop -a ($first) ($cmd) [args...]\nor remember one, then run the command again:\n  shop --cache set ($cmd) ($first)\nor ask once from a real terminal:\n  shop --pick ($cmd)"
}

def resolve-choice [cmd: string, force: bool]: nothing -> record {
  let cached = if $force { null } else { load-cache | get -o $cmd }
  if $cached != null {
    return ((as-choice $cached) | merge { how: "remembered" })
  }

  let all = (locate $cmd)

  # The database only lists packages the binary cache has, so unfree attrs are reachable by name but never by command.
  if ($all | is-empty) {
    if not (knows-attr $cmd) {
      die $"no executable '($cmd)' in the nix-index database, and no attribute called '($cmd)'"
    }
    hint $"no /bin/($cmd) in the database -- resolving the attribute '($cmd)' directly"
    let picked = { attr: $cmd, output: "" }
    save-choice $cmd $picked
    return ($picked | merge { how: "attribute" })
  }

  # Only top-level attrs carry a version axis, so they are offered first.
  let ordered = ($all | sort-by {|a| $a | split row "." | length })

  if (($ordered | length) == 1) {
    let picked = (split-choice ($ordered | first))
    save-choice $cmd $picked
    return ($picked | merge { how: "only candidate" })
  }

  if not (interactive) {
    refuse-to-guess $cmd $ordered
  }

  let choice = ($ordered | input list --fuzzy $"($ordered | length) packages ship /bin/($cmd)")
  if ($choice | is-empty) {
    die "nothing picked"
  }

  let picked = (split-choice $choice)
  save-choice $cmd $picked
  $picked | merge { how: "picked" }
}

def cache-rows [cur: record]: nothing -> table {
  $cur
  | items {|k, v|
    let c = (as-choice $v)
    { command: $k, package: (choice-label $c), picked: ($c.picked? | default "-") }
  }
  | sort-by command
}

def cache-cmd [args: list<string>] {
  let cur = (load-cache)
  let known = ($cur | columns)
  let sub = ($args | get -o 0 | default "list")

  match $sub {
    "list" => {
      hint (choices-path | str replace $env.HOME "~")
      if ($cur | is-empty) {
        hint "nothing remembered -- shop asks the first time a command has several packages"
        return
      }
      return (render (cache-rows $cur))
    }
    "rm" => {
      let names = ($args | skip 1)
      if ($names | is-empty) {
        die "--cache rm needs at least one command" "shop --cache rm <command>..."
      }
      let missing = ($names | where ($it not-in $known))
      if ($missing | is-not-empty) {
        die $"nothing remembered for ($missing | str join ', ')" $"remembered: ($known | str join ' ')"
      }
      let rows = (cache-rows $cur | where ($it.command in $names))
      write-cache ($names | reduce --fold $cur {|n, acc| $acc | reject $n })
      hint $"forgot ($names | length), shop will ask again"
      return (render $rows)
    }
    "clear" => {
      if ($cur | is-empty) {
        hint "nothing to clear"
        return
      }
      let rows = (cache-rows $cur)
      write-cache {}
      hint $"cleared ($rows | length) remembered picks"
      return (render $rows)
    }
    "set" => {
      if ($args | length) != 3 {
        die "--cache set needs a command and a package" "shop --cache set <command> <attr.output>   the package as shop -p prints it"
      }
      let cmd = ($args | get 1)
      let pkg = ($args | get 2)
      let found = (locate $cmd)
      if ($found | is-empty) {
        die $"no /bin/($cmd) in the nix-index database, so there is nothing to choose between" "an unfree attribute resolves by name and needs no remembered pick"
      }
      if $pkg not-in $found {
        die $"'($pkg)' does not ship /bin/($cmd)" $"candidates: ($found | str join ' ')"
      }
      save-choice $cmd (split-choice $pkg)
      hint $"($cmd) -> ($pkg) \(remembered\)"
    }
    _ => {
      die $"unknown cache command '($sub)'" "shop --cache [list | rm <command>... | clear | set <command> <attr.output>]"
    }
  }
}

def resolve-version [attr: string, tbl: table, want: string]: nothing -> string {
  if ($want | is-empty) {
    if not (interactive) {
      die $"no version given for '($attr)' and nothing to prompt on"
    }
    let picked = ($tbl | reverse | input list --fuzzy $"every ($attr) that ever existed")
    if ($picked | is-empty) {
      die "nothing picked"
    }
    return $picked.version
  }

  let known = ($tbl | get version)
  if ($want in $known) {
    return $want
  }
  let listed = ($known | str join " ")
  die $"no revision ever shipped ($attr) ($want)" $"known versions: ($listed)"
}

def show-rev []: nothing -> string {
  let c = (palette)
  let label = (^nix eval --raw -f $env.SHOP_ENGINE pinnedLabel | str trim)
  let note = if (^nix eval --json -f $env.SHOP_ENGINE pinnedExact | from json) {
    "exact pairing with the nix-index database"
  } else {
    "nearest indexed revision -- the database is newer than the index"
  }
  $"($c.c)($label)($c.z) ($c.d)\(($note)\)($c.z)"
}

def usage []: nothing -> string {
  let c = (palette)
  [
    $"($c.b)shop($c.z) -- run any version of any package, without installing it"
    ""
    $"($c.b)USAGE($c.z)"
    $"  ($c.c)shop <command>[@<version>] [args...]($c.z)"
    ""
    $"  ($c.d)shop's own options go BEFORE <command>. everything after it goes($c.z)"
    $"  ($c.d)to the package untouched, so there is no -- separator to remember.($c.z)"
    ""
    $"  ($c.c)shop rg($c.z)             newest ripgrep, run right now, installed nowhere"
    $"  ($c.c)shop jq@1.5($c.z)         the exact jq that shipped as 1.5, years ago"
    $"  ($c.c)shop jq@($c.z)            pick a jq version from a menu"
    $"  ($c.c)shop -l rg($c.z)          every ripgrep that ever existed"
    ""
    $"($c.b)OPTIONS($c.z)"
    $"  ($c.c)-l, --list <cmd>($c.z)      every version of that command, with its revision"
    $"  ($c.c)-p, --print <cmd>($c.z)     which packages provide that command"
    $"  ($c.c)-s, --shell <cmd>...($c.z)  open a shell with all of those on PATH instead of running one"
    $"  ($c.c)-a, --attr <pkg>($c.z)      name the package yourself, remembering nothing"
    $"  ($c.c)--pick($c.z)                ask which package again, even if one is remembered"
    $"  ($c.c)--cache($c.z)               see, forget, clear or set what shop remembers"
    $"  ($c.c)--rev($c.z)                 which revision a bare command resolves against"
    $"  ($c.c)-h, --help($c.z)            show this"
    ""
    "  flags go first and combine: -l -a <pkg>, -s -a <pkg>, -l --pick <cmd>."
    "  the first token that is not a flag is the command, and for a plain run"
    "  everything after it goes to the package untouched."
    ""
    $"($c.b)HOW IT WORKS($c.z)"
    $"  1  you type a command name, like ($c.c)rg($c.z)"
    $"  2  shop asks the nix-index database which package ships /bin/rg,"
    $"     and gets back ($c.c)ripgrep($c.z)"
    "  3  if you gave a version, shop looks up the last nixpkgs revision"
    "     that shipped ripgrep at that version"
    "  4  it pulls that one package out of the binary cache and runs it"
    "  5  nothing is installed. it lands in /nix/store and is collected by"
    "     the garbage collector like anything else"
    ""
    $"  no version means the revision shop is paired with. ($c.c)shop --rev($c.z)"
    "  tells you which one that is."
    ""
    $"($c.b)EXAMPLES($c.z)"
    "  every version of jq nixpkgs ever shipped, newest last, each with the"
    "  revision it came from:"
    ""
    $"      ($c.c)shop -l jq($c.z)"
    ""
    "  run one of them:"
    ""
    $"      ($c.c)shop jq@1.5 --version($c.z)"
    "      jq-1.5"
    ""
    "  leave the version off after the @ and shop gives you a searchable"
    "  menu of every version, newest first:"
    ""
    $"      ($c.c)shop jq@($c.z)"
    ""
    $"  the command is ($c.c)rg($c.z), the package is ($c.c)ripgrep($c.z). shop knows that:"
    ""
    $"      ($c.c)shop rg --version($c.z)"
    "      ripgrep 15.2.0"
    ""
    "  a shell with a 2017-era ripgrep on PATH. exit and it is gone:"
    ""
    $"      ($c.c)shop -s rg@0.4.0($c.z)"
    ""
    "  one shell with several packages on PATH, each from its own revision. a"
    "  package named with -a takes no command:"
    ""
    $"      ($c.c)shop -s rg@15.1.0 jq@1.8.1($c.z)"
    $"      ($c.c)shop -s -a ripgrep.out@15.1.0 jq($c.z)"
    ""
    "  when several packages ship one command, shop asks you to pick and"
    "  then remembers the answer. with no terminal to ask on it refuses"
    "  rather than guess. -p lists the candidates and -a names one:"
    ""
    $"      ($c.c)shop -p convert($c.z)"
    $"      ($c.c)shop -a imagemagick.out convert in.png out.jpg($c.z)"
    ""
    $"($c.b)GOTCHAS($c.z)"
    "  the command you type is not always the package you think."
    "  /bin/python3 comes from python3Minimal, python311, python312 and"
    $"  python313 -- not from the attribute literally named ($c.c)python3($c.z). so"
    $"  ($c.c)shop python3@3.6.2($c.z) fails, because whatever shop picked never"
    $"  shipped a 3.6.2. use ($c.c)shop -p python3($c.z) to see the candidates, and"
    $"  ($c.c)shop -l python3($c.z) to see what your pick actually has."
    ""
    "  versions only work on top-level packages:"
    ""
    $"      shop yt-dlp@2026.07.04                    ($c.g)<- works($c.z)"
    $"      shop python314Packages.yt-dlp@2026.07.04  ($c.r)<- does not($c.z)"
    ""
    "  packages deleted from nixpkgs years ago cannot be found by command"
    "  name at all. the database only knows what exists today."
    ""
    "  the first package out of any given revision is slow -- shop has to"
    "  fetch that nixpkgs tree, roughly 300MB. every package from that same"
    "  revision afterwards is basically free."
    ""
    "  coming from comma, you may reach for a -- before the package's own"
    "  flags. do not. shop stops parsing at the first token, so nothing"
    "  consumes it and it reaches the program as a literal argument."
    ""
    $"      ($c.c)shop jq@1.5 --version($c.z)     ($c.g)<- works($c.z)"
    $"      ($c.c)shop jq@1.5 -- --version($c.z)  ($c.r)<- does not($c.z)"
    ""
    $"  shop reads its own flags first, up to the first token that is not one."
    $"  ($c.c)-a($c.z) takes the package after it, and ($c.c)--cache($c.z) takes the rest of the line."
    "  with -s every token after the flags is a package, not an argument, so"
    "  there is nothing to pass through."
    ""
    $"($c.b)CACHE($c.z)"
    "  ~/.cache/shop/choices.json   which package shop remembers for each command."
    "  every run prints on stderr which package it used, and whether that was"
    "  remembered, picked just now, or the only candidate."
    ""
    $"      ($c.c)shop --cache($c.z)                               list what is remembered"
    $"      ($c.c)shop --cache rm convert($c.z)                    forget one or more commands"
    $"      ($c.c)shop --cache clear($c.z)                         forget everything"
    $"      ($c.c)shop --cache set convert imagemagick.out($c.z)   remember one without a terminal"
    $"      ($c.c)shop --pick convert($c.z)                        ask again now, from a terminal"
  ] | str join "\n"
}

# A bare name with no dot is a top-level attribute and its default output; -p always prints a dotted form.
def parse-attr [s: string]: nothing -> record {
  if ($s | str contains ".") { split-choice $s } else { { attr: $s, output: "" } }
}

# The attribute path nix is handed, newest by default or pinned to a version's revision.
def selection-for [picked: record, version: any]: nothing -> string {
  let base = if $version == null {
    ["pkgs"] | append ($picked.attr | split row ".")
  } else {
    reject-nested $picked.attr
    let tbl = (version-table $picked.attr)
    let ver = (resolve-version $picked.attr $tbl $version)
    hint $"($picked.attr) ($ver) -- from ($tbl | where version == $ver | first | get revision)"
    ["versions" $picked.attr $ver]
  }
  sel-path (if ($picked.output | is-empty) { $base } else { $base | append $picked.output })
}

# A `command[@version]` token, resolved through the cache and the nix-index database.
def resolve-command [tok: string, force: bool]: nothing -> record {
  let bits = ($tok | split row "@")
  let cmd = ($bits | first)
  if ($cmd | is-empty) { die "no command given" }
  let picked = (resolve-choice $cmd $force)
  announce $cmd $picked
  { cmd: $cmd, picked: $picked, version: ($bits | get -o 1) }
}

# An `attr.output[@version]` token from -a.
def resolve-named [tok: string]: nothing -> record {
  let bits = ($tok | split row "@")
  let given = ($bits | first)
  if ($given | is-empty) { die "no package given" }
  { picked: (parse-attr $given), version: ($bits | get -o 1) }
}

def --wrapped main [...rest] {
  if ($rest | is-empty) {
    print -e (usage)
    exit 1
  }

  let head = ($rest | first)
  if $head in ["-h" "--help"] { return (usage) }
  if $head == "--rev" { return (show-rev) }
  if $head == "--cache" { return (cache-cmd ($rest | skip 1)) }

  # Leading flags run up to the first token that is not one of shop's own; from there it is the command and the package's arguments.
  mut mode = "run"
  mut flag = $head
  mut attrs = []
  mut force = false
  mut i = 0
  loop {
    let tok = ($rest | get -o $i)
    if $tok == null { break }
    if not ($tok | str starts-with "-") { break }
    $flag = $tok

    let picks_mode = (match $tok {
      "-l" | "--list" => "list",
      "-p" | "--print" => "print",
      "-s" | "--shell" => "shell",
      _ => null,
    })
    if $picks_mode != null {
      if $mode != "run" { die "choose one of -l, -p and -s" }
      $mode = $picks_mode
    } else if $tok in ["-a" "--attr"] {
      let given = ($rest | get -o ($i + 1))
      if $given == null {
        die $"($tok) needs a package" "shop -a <attr.output>[@<version>] ...   the package as shop -p prints it"
      }
      $attrs = ($attrs | append $given)
      $i = $i + 1
    } else if $tok == "--pick" {
      $force = true
    } else {
      die $"unknown option '($tok)'"
    }
    $i = $i + 1
  }

  let positional = ($rest | skip $i)
  let n_attr = ($attrs | length)

  if $mode == "print" {
    if $n_attr > 0 { die "-p lists the packages that ship a command, so -a does not apply" }
    if ($positional | is-empty) { die "-p needs a command" }
    let cmd = ($positional | first | split row "@" | first)
    if ($cmd | is-empty) { die "no command given" }
    let found = (locate $cmd)
    if ($found | is-empty) {
      if not (knows-attr $cmd) {
        die $"no executable '($cmd)' in the nix-index database, and no attribute called '($cmd)'"
      }
      hint $"no /bin/($cmd) in the database -- shop resolves the attribute '($cmd)' directly"
      return
    }
    return (render ($found | wrap attr))
  }

  if $mode == "list" {
    if $n_attr > 1 { die "-l lists one package at a time" }
    if $n_attr == 1 {
      if ($positional | is-not-empty) { die "-l -a takes only the package" "shop -l -a <attr.output>" }
      let n = (resolve-named ($attrs | first))
      if $n.version != null { die "-l lists every version, so leave the @version off" }
      reject-nested $n.picked.attr
      return (render (version-table $n.picked.attr))
    }
    if ($positional | is-empty) { die "-l needs a command" }
    let r = (resolve-command ($positional | first) $force)
    reject-nested $r.picked.attr
    return (render (version-table $r.picked.attr))
  }

  if $mode == "shell" {
    mut selections = []
    for a in $attrs {
      let n = (resolve-named $a)
      $selections = ($selections | append (selection-for $n.picked $n.version))
    }
    for t in $positional {
      let r = (resolve-command $t $force)
      $selections = ($selections | append (selection-for $r.picked $r.version))
    }
    if ($selections | is-empty) {
      die "-s needs a command or a package" "shop -s <command>[@<version>]... [-a <attr.output>[@<version>]]..."
    }
    exec nix shell -f $env.SHOP_ENGINE ...$selections
  }

  if $n_attr > 1 { die "a run takes one -a package; -s opens a shell with several" }
  if $n_attr == 1 {
    if ($positional | is-empty) {
      die "-a needs a package and a command" "shop -a <attr.output>[@<version>] <command> [args...]   the package as shop -p prints it"
    }
    if $force { die "--pick asks about a command, and -a already names the package" }
    let n = (resolve-named ($attrs | first))
    let selection = (selection-for $n.picked $n.version)
    exec nix shell -f $env.SHOP_ENGINE $selection --command ($positional | first) ...($positional | skip 1)
  }

  if ($positional | is-empty) { die $"($flag) needs a command" }
  let r = (resolve-command ($positional | first) $force)
  let selection = (selection-for $r.picked $r.version)
  exec nix shell -f $env.SHOP_ENGINE $selection --command $r.cmd ...($positional | skip 1)
}
