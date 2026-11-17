class_name HudFormat
extends RefCounted
## Number formatting shared by HUD components.

const MINUS := "−"

static func signed(value: float, decimals: int = 1, suffix: String = "") -> String:
	if is_zero_approx(snappedf(value, pow(10.0, -decimals))):
		value = 0.0  # never show a negative zero
	var text := ("%+." + str(decimals) + "f") % value
	return text.replace("-", MINUS) + suffix

static func plain(value: float, decimals: int = 0) -> String:
	return (("%." + str(decimals) + "f") % value).replace("-", MINUS)

static func thousands(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return (MINUS if value < 0 else "") + digits + out

## "E", "+2" or "-1" (with a real minus sign).
static func relative_to_par(relative: int) -> String:
	if relative == 0:
		return "E"
	return ("+%d" % relative) if relative > 0 else (MINUS + str(-relative))
