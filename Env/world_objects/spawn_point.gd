extends Node3D

# ─────────────────────────────────────────────
# SPAWN POINT — where the player comes in.
#
# The green box is an AUTHORING marker. It has to be visible in the editor,
# because a spawn point with no mesh is an invisible empty you cannot place or
# rotate by eye — and the rotation matters now that the player actually faces
# the way it points. In the running game it is a green box sitting in the world
# for the first second of every mission.
#
# So it is hidden here rather than unticked in the scene: unticking would take
# it out of the editor too, which is the one place it earns its keep.
#
# The node's TRANSFORM is what everything reads (world.gd places the player off
# it), and hiding a Node3D does not touch its transform — only whether its
# visual children draw.
# ─────────────────────────────────────────────


func _ready() -> void:
	# Not in the editor: a @tool script would hide it in the viewport, which is
	# exactly backwards.
	if Engine.is_editor_hint():
		return
	visible = false
