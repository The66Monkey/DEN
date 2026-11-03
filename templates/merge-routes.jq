.[0] as $base | .[1] as $custom |
if ($custom | type) != "object" or ($custom | keys) != ["http"] or
   ($custom.http | type) != "object"
then error("Custom routes must contain an http object only") else . end |
reduce ($custom.http | to_entries[]) as $section ($base;
    if (["routers", "services", "middlewares", "serversTransports"] | index($section.key)) == null or
       ($section.value | type) != "object"
    then error("Invalid custom HTTP section: " + $section.key) else . end |
    reduce ($section.value | to_entries[]) as $entry (.;
        if .http[$section.key] | has($entry.key)
        then error("Custom route conflicts with managed entry: " + $entry.key)
        elif ($entry.value | type) != "object"
        then error("Custom route entry must be an object: " + $entry.key)
        else .http[$section.key][$entry.key] = $entry.value end))
