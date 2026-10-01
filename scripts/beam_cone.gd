class_name BeamCone
## The (invisible) hitbox of a beam attack: an inverted cone that starts as wide as the character at the
## head and narrows to a point at the end of the beam. It is fixed to the caster's head, so it does not
## depend on the animation or on where the staff happens to be. (The beam you see still leaves the staff's orb.)

const HEAD_OFFSET := Vector2(0, -14)   # from the caster's feet to the middle of the head
const BASE_WIDTH := 10.0                # as wide as the character


## Where the cone starts.
static func head(caster: Node2D) -> Vector2:
	return caster.global_position + HEAD_OFFSET


## The direction the cone points: from the head toward the mouse.
static func direction(caster: Node2D, fallback: Vector2) -> Vector2:
	var aim: Vector2 = caster.aim_world - head(caster)
	return aim.normalized() if aim.length() > 1.0 else fallback


## Every physics body inside the cone (once each, the caster excluded).
static func bodies(caster: Node2D, dir: Vector2, length: float) -> Array:
	var origin := head(caster)
	var side := dir.orthogonal() * (BASE_WIDTH * 0.5)
	var shape := ConvexPolygonShape2D.new()
	shape.points = PackedVector2Array([origin - side, origin + side, origin + dir * length])
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.collision_mask = 1
	if caster is CollisionObject2D:
		q.exclude = [caster.get_rid()]
	var out: Array = []
	var seen := {}
	for hit in caster.get_world_2d().direct_space_state.intersect_shape(q, 64):
		var b := hit["collider"] as Node
		if b != null and not seen.has(b):
			seen[b] = true
			out.append(b)
	return out
