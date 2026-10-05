class_name Words
extends RefCounted
## Слова для человека вместо технических имён (просьба владельца: мало цифр и терминов, расчёты — под капотом).

const STATES := {"dry": "обычный", "dry_b": "обычный, вариант 2", "dry_c": "обычный, вариант 3", "flooded": "под водой",
	"silt": "ил после отлива", "storm": "шторм", "ravaged": "разорено", "burning": "горит", "burned": "сгорело",
	"alarm": "тревога", "fight": "бой", "damaged": "повреждено", "ruined": "разрушено", "repair": "ремонт",
	"barricaded": "баррикада", "crowded": "много людей", "overcrowded": "переполнено", "collapsed": "обрушено",
	"cracked": "трещины", "temporary": "временное", "sealed": "закрыто", "closed": "закрыто", "closed_night": "закрыто ночью",
	"open": "открыто", "opened": "открыто", "empty": "пусто", "lit": "огонь горит", "bonfire": "костёр", "beacon": "маяк",
	"blood": "кровь", "red": "красное", "banner": "знамя", "molting": "линька", "night_glow": "ночное сияние",
	"charmed": "чары", "wrath": "гнев", "hunted": "охота", "buried": "засыпано", "dug": "раскопано", "siege": "осада",
	"busy": "людно", "statues_moved": "статуи сдвинулись", "awake": "проснулось", "boat_ready": "лодка готова",
	"dim": "тускло", "signal": "сигнал", "leak": "течь", "lockdown": "карантин", "breached": "прорыв", "infested": "заражено",
	"restored": "восстановлено", "found": "найдено", "picked": "обобрано", "fresh_graves": "свежие могилы", "old": "старое",
	"abandoned": "брошено", "broken": "сломано", "hidden": "скрыто", "cleared": "расчищено", "occupied": "занято",
	"fresh": "свежее", "glowing": "светится", "dormant": "спит", "active": "активно"}

const HEIGHTS := {"low": "низина — тонет в каждый прилив", "mid": "средняя — может уйти под воду",
	"high": "высота — не тонет никогда", "": "не задано"}
const HEIGHT_SHORT := {"low": "низина", "mid": "средняя", "high": "высота", "": "—"}

const PHASES := {"": "любая", "day": "День", "dawn": "Рассвет", "dusk": "Сумерки", "night": "Ночь", "storm": "Шторм",
	"blood_moon": "Кровавая луна", "ash_storm": "Пепельная буря", "eclipse": "Затмение"}

const TIDES := {"normal": "обычная вода", "warn": "вода подступает", "flood": "прилив", "storm": "штормовой прилив"}

const KINDS := {"base": "основа", "height": "карта высот", "place": "место", "decal": "метка", "strip": "полоса",
	"tile": "плитка", "token": "фишка", "tech": "служебная"}

const SERVICES := {"heal": "лечение", "view": "обзор с высоты", "water": "вода", "shop": "лавка", "repair": "починка",
	"sharpen": "заточка", "unwear": "снятие износа"}


static func state(st: String) -> String:
	return str(STATES.get(st, st.replace("_", " ")))


static func phase(ph: String) -> String:
	return str(PHASES.get(ph, ph.replace("_", " ")))


## Опасность ночи (0..1) словами.
static func danger(x: float) -> String:
	if x <= 0.06:
		return "тихо"
	if x <= 0.15:
		return "спокойно"
	if x <= 0.3:
		return "неспокойно"
	if x <= 0.5:
		return "опасно"
	return "очень опасно"


## Отдых (психика за ночь) словами.
static func rest(n: int) -> String:
	if n >= 16:
		return "отличный отдых"
	if n >= 11:
		return "хороший отдых"
	if n >= 7:
		return "так себе отдых"
	return "почти без отдыха"


## Размер места (доля ширины основы) словами.
static func place_size(s: float) -> String:
	if s < 0.09:
		return "крошечное"
	if s < 0.12:
		return "маленькое"
	if s < 0.16:
		return "среднее"
	if s < 0.2:
		return "большое"
	return "огромное"


static func steps(n: int) -> String:
	if n == 0:
		return "здесь"
	if n < 0:
		return "не дойти"
	return "%d %s" % [n, plural(n, "шаг", "шага", "шагов")]


static func plural(n: int, one: String, few: String, many: String) -> String:
	var n10 := n % 10
	var n100 := n % 100
	if n10 == 1 and n100 != 11:
		return one
	if n10 >= 2 and n10 <= 4 and (n100 < 10 or n100 >= 20):
		return few
	return many


static func q(s: String) -> String:
	return "«%s»" % s
