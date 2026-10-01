class_name AttackGuard
extends RefCounted
## Ties a telegraphed attack (ground marker, blob, cone, knife...) to whoever
## cast it. If the caster's health hits 0 - or the caster disappears - the
## attack vanishes on the spot and never deals damage.
##
## Usage when spawning an attack:   AttackGuard.bind(attack, self)
## The attack needs a `_cancel()` method and should start its _process with:
##     if AttackGuard.owner_dead(self): _cancel(); return

static func bind(attack: Node, caster: Node) -> void:
	if caster == null:
		return
	attack.set_meta("guard_caster", caster.get_instance_id())
	var st := caster.get_node_or_null("Stats") as Stats
	if st:
		# connecting to the attack's own method: cleans itself up if the attack ends first
		st.died.connect(Callable(attack, "_cancel"))


static func owner_dead(attack: Node) -> bool:
	var id: int = attack.get_meta("guard_caster", 0)
	if id == 0:
		return false
	var c := instance_from_id(id) as Node
	if c == null or c.is_queued_for_deletion():
		return true
	var st := c.get_node_or_null("Stats") as Stats
	return st != null and st.health <= 0.0


## The caster an attack was bound to (null if unknown or gone).
static func caster_of(attack: Node) -> Node:
	var id: int = attack.get_meta("guard_caster", 0)
	return instance_from_id(id) as Node if id != 0 else null
