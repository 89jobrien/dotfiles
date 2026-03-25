function n --description 'Quick note capture via doob'
    if test (count $argv) -eq 0
        doob note list --limit 10
    else
        doob note add $argv
    end
end
