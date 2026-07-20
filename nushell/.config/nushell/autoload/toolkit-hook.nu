# toolkit-hook.nu — auto-load toolkit.nu overlay on cd
# Source: nushell/nu_scripts (nu-hooks/toolkit)
#
# When you cd into a directory containing toolkit.nu, it loads as an overlay
# with the prefix "tk". Define project-local commands in toolkit.nu files.

export def toolkit-hook [
  --name: string = "tk",
  --color: string = "yellow_bold",
]: [ nothing -> record<condition: closure, code: string> ] {
  {
    condition: {|_, after| $after | path join 'toolkit.nu' | path exists }
    code: $"
      print $'[\(ansi ($color)\)toolkit\(ansi reset\)] loading \(ansi purple\)toolkit.nu\(ansi reset\) as overlay'
      overlay use --prefix toolkit.nu as ($name)
    "
  }
}
