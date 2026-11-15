extends RefCounted
## Short money text so big numbers always fit: $950, $12.5K, $2.05M, $3.10B, $1.00T

static func money(n: float) -> String:
	var sign := "-" if n < 0 else ""
	var a := absf(n)
	if a < 10000.0:
		return "%s$%d" % [sign, int(round(a))]
	if a < 1e6:
		return "%s$%.1fK" % [sign, a / 1e3]
	if a < 1e9:
		return "%s$%.2fM" % [sign, a / 1e6]
	if a < 1e12:
		return "%s$%.2fB" % [sign, a / 1e9]
	if a < 1e15:
		return "%s$%.2fT" % [sign, a / 1e12]
	return "%s$%.1fQ" % [sign, a / 1e15]

static func mult(m: float) -> String:
	if absf(m) >= 1000.0:
		return "x%d" % int(m)
	return "x%.2f" % m
