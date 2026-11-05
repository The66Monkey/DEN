.[0] as $base | .[1] as $custom |
if ($custom | type) != "object" or ($custom | keys | all(. == "http" or . == "tcp") | not) or
   ([$custom[] | select(type != "object")] | length) != 0
then error("Custom routes must contain http and/or tcp objects only") else . end |
reduce ($custom | keys[]) as $protocol ($base;
    .[$protocol] = (.[$protocol] // {}) |
    reduce (($custom[$protocol] // {}) | to_entries[]) as $section (.;
        if (["routers", "services", "middlewares", "serversTransports"] | index($section.key)) == null or
           ($section.value | type) != "object"
        then error("Invalid custom " + $protocol + " section: " + $section.key) else . end |
        reduce ($section.value | to_entries[]) as $entry (.;
            if .[$protocol][$section.key] | has($entry.key)
            then error("Custom route conflicts with managed entry: " + $entry.key)
            elif ($entry.value | type) != "object"
            then error("Custom route entry must be an object: " + $entry.key)
            else .[$protocol][$section.key][$entry.key] = $entry.value end)))
