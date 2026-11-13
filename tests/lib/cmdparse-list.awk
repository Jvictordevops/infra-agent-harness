# Test sink for hooks/lib/cmdparse.awk: prints every simple command as 'depth kind class words'.
function cmd_seen(d, k, cls, m, V) { print d " " k " " cls " " join(V, 1, m, " ") }
