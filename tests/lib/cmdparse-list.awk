# Test sink for hooks/lib/cmdparse.awk: prints every simple command as 'depth kind class words'.
function cmd_seen(d, k, cls, m, V) { print d " " k " " cls " " join(V, 1, m, " ") }
function cmd_redir(d, kind, target, lit) { if (ENVIRON["CMDP_LIST_REDIR"] == 1) print d " redir " kind " " target }
