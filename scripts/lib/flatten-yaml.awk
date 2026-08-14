# Flattens the restricted YAML subset used by versions.yaml into
#   dotted.path=value      (mapping scalar)
#   dotted.path[]=item     (list item)
# Supported: two-space indentation, nested mappings with scalar leaves,
# lists of plain scalars, comments, optional double quotes around values.
# Anything outside that subset is a hard error so drift is caught early.
{
  line = $0
  sub(/[ \t]+#.*$/, "", line)
  if (line ~ /^[ \t]*(#|$)/) next
  match(line, /^ */)
  indent = RLENGTH
  if (indent % 2 != 0) {
    printf "flatten-yaml: odd indentation: %s\n", $0 > "/dev/stderr"
    exit 1
  }
  depth = indent / 2
  s = substr(line, indent + 1)
  sub(/[ \t]+$/, "", s)
  if (s ~ /^- /) {
    v = substr(s, 3)
    gsub(/^"|"$/, "", v)
    if (depth < 1 || path[depth - 1] == "") {
      printf "flatten-yaml: list item without parent key: %s\n", $0 > "/dev/stderr"
      exit 1
    }
    printf "%s[]=%s\n", path[depth - 1], v
    next
  }
  if (!match(s, /^[A-Za-z0-9_-]+:/)) {
    printf "flatten-yaml: unsupported line: %s\n", $0 > "/dev/stderr"
    exit 1
  }
  key = substr(s, 1, RLENGTH - 1)
  val = substr(s, RLENGTH + 1)
  sub(/^[ \t]*/, "", val)
  gsub(/^"|"$/, "", val)
  if (depth == 0) path[0] = key
  else path[depth] = path[depth - 1] "." key
  for (d = depth + 1; d <= maxdepth; d++) path[d] = ""
  if (depth > maxdepth) maxdepth = depth
  if (val != "") printf "%s=%s\n", path[depth], val
}
