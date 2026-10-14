class_name Calendar
extends RefCounted
## Converts the world's running minute counter into dates and times.
##
## The world stores a single integer: minutes elapsed since 00:00 on day 1 of
## the starting year. Everything else (hour, season, year) is derived here.

const MINUTES_PER_HOUR := 60
const MINUTES_PER_DAY := 1440


static func days_per_season() -> int:
	return int(GameData.calendar().get("days_per_season", 30))


static func seasons() -> Array:
	return GameData.calendar().get("seasons", ["Spring", "Summer", "Autumn", "Winter"])


static func days_per_year() -> int:
	return days_per_season() * seasons().size()


static func start_year() -> int:
	return int(GameData.calendar().get("start_year", 1187))


static func start_minutes() -> int:
	return int(GameData.calendar().get("start_hour", 7)) * MINUTES_PER_HOUR


## Zero-based day index since the calendar began.
static func day_index(minutes: int) -> int:
	return floori(minutes / float(MINUTES_PER_DAY))


static func hour(minutes: int) -> int:
	return floori((minutes % MINUTES_PER_DAY) / float(MINUTES_PER_HOUR))


static func minute(minutes: int) -> int:
	return minutes % MINUTES_PER_HOUR


## Fractional hour 0.0-24.0, useful for lighting.
static func hour_f(minutes: float) -> float:
	return fmod(minutes, MINUTES_PER_DAY) / MINUTES_PER_HOUR


static func year(minutes: int) -> int:
	return start_year() + floori(day_index(minutes) / float(days_per_year()))


static func season_name(minutes: int) -> String:
	var day_of_year := day_index(minutes) % days_per_year()
	return seasons()[floori(day_of_year / float(days_per_season()))]


static func day_of_season(minutes: int) -> int:
	return (day_index(minutes) % days_per_season()) + 1


static func format_time(minutes: int) -> String:
	return "%02d:%02d" % [hour(minutes), minute(minutes)]


static func format_date(minutes: int) -> String:
	return "%s %d, Year %d" % [season_name(minutes), day_of_season(minutes), year(minutes)]


static func format_full(minutes: int) -> String:
	return "%s  %s" % [format_date(minutes), format_time(minutes)]
