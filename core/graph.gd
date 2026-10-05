class_name MapGraph
extends RefCounted
## Граф карты (руководство §6–7): узлы — места, рёбра — тропы без направления. Расстояние — число троп.
## Обход в ширину, соседи по алфавиту — путь как в игре (TravelRules.route).


## Соседи: {место: [соседи по алфавиту]}. nodes — какие места есть сейчас ({} — все из рёбер).
static func adjacency(edges: Array, nodes: Dictionary = {}) -> Dictionary:
	var adj := {}
	for e: Array in edges:
		if e.size() != 2:
			continue
		for k in 2:
			var a := str(e[k])
			var b := str(e[1 - k])
			if not nodes.is_empty() and (not nodes.has(a) or not nodes.has(b)):
				continue
			if not adj.has(a):
				adj[a] = []
			if not (adj[a] as Array).has(b):
				(adj[a] as Array).append(b)
	for a2: String in adj:
		(adj[a2] as Array).sort()
	return adj


## Расстояния от from до всех достижимых: {место: шагов}. blocked(место) → true — туда не пройти;
## edge_ok(a, b) → false — по ребру не пройти (вода без лодки).
static func distances(adj: Dictionary, from: String, blocked: Callable = Callable(), edge_ok: Callable = Callable()) -> Dictionary:
	var out := {from: 0}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n: String in adj.get(cur, []):
			if out.has(n):
				continue
			if blocked.is_valid() and blocked.call(n):
				continue
			if edge_ok.is_valid() and not edge_ok.call(cur, n):
				continue
			out[n] = int(out[cur]) + 1
			queue.append(n)
	return out


## Кратчайший путь [следующее, …, to]; [] — нет пути или уже там.
static func route(adj: Dictionary, from: String, to: String, blocked: Callable = Callable(), edge_ok: Callable = Callable()) -> Array:
	if from == to or from == "" or to == "":
		return []
	var prev := {from: ""}
	var queue: Array = [from]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			break
		for n: String in adj.get(cur, []):
			if prev.has(n):
				continue
			if blocked.is_valid() and blocked.call(n):
				continue
			if edge_ok.is_valid() and not edge_ok.call(cur, n):
				continue
			prev[n] = cur
			queue.append(n)
	if not prev.has(to):
		return []
	var path: Array = []
	var at := to
	while at != from:
		path.push_front(at)
		at = str(prev[at])
	return path


## Связные части среди nodes: [[места], …], самая большая — первой.
static func components(nodes: Array, edges: Array) -> Array:
	var set := {}
	for n: String in nodes:
		set[n] = true
	var adj := adjacency(edges, set)
	var seen := {}
	var out: Array = []
	for n2: String in nodes:
		if seen.has(n2):
			continue
		var comp := distances(adj, n2).keys()
		for x: String in comp:
			seen[x] = true
		comp.sort()
		out.append(comp)
	out.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	return out


## Проверка связности как в игре (content_validator._spine_check): кто из nodes не связан с nodes[0].
## skip — пары троп, которые не считаются (завалы).
static func unreachable(nodes: Array, edges: Array, skip: Array = []) -> Array:
	if nodes.size() < 2:
		return []
	var seen := {nodes[0]: true}
	var queue: Array = [nodes[0]]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for e: Array in edges:
			if skip.any(func(sk: Array) -> bool: return sk.size() == 2 and sk.has(str(e[0])) and sk.has(str(e[1]))):
				continue
			for k in 2:
				if str(e[k]) == cur and nodes.has(str(e[1 - k])) and not seen.has(str(e[1 - k])):
					seen[str(e[1 - k])] = true
					queue.append(str(e[1 - k]))
	return nodes.filter(func(n: String) -> bool: return not seen.has(n))
