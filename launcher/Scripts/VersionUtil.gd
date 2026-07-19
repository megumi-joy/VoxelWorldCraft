class_name VersionUtil
extends RefCounted
## Small dependency-free semver-ish comparator. GDScript has no built-in
## version comparison, and we don't want a real semver library just to
## answer "is v0.3.0 newer than v0.2.9". Good enough for build-folder names
## and GitHub release tags like "0.3.0" or "v0.3.0"; ignores anything after
## a numeric run in a segment (so "0.3.0-beta" and "0.3.0+5" both compare
## as "0.3.0").

## Returns -1 if a < b, 0 if equal, 1 if a > b.
static func compare(a: String, b: String) -> int:
	var pa := _parse(a)
	var pb := _parse(b)
	var length: int = max(pa.size(), pb.size())
	for i in range(length):
		var va: int = pa[i] if i < pa.size() else 0
		var vb: int = pb[i] if i < pb.size() else 0
		if va != vb:
			return -1 if va < vb else 1
	return 0

static func is_newer(candidate: String, than: String) -> bool:
	return compare(candidate, than) > 0

static func _parse(v: String) -> Array:
	var s := v.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		s = s.substr(1)
	var parts := s.split(".")
	var out: Array = []
	for part in parts:
		var digits := ""
		for c in part:
			if c >= "0" and c <= "9":
				digits += c
			else:
				break
		out.append(int(digits) if digits != "" else 0)
	return out
