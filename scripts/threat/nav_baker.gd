class_name NavBaker
extends RefCounted
## Bakes the Keeper's navigation mesh from the level's static colliders at load.
## Door panels are left out of the bake (the Keeper opens unlocked doors itself and
## is stopped by locked ones at runtime), so every doorway is connected.

const PATROL := [
	Vector3(0.0, 0, 2.5), Vector3(-1.2, 0, 6.2),
	Vector3(0.0, 0, -3.0), Vector3(0.0, 0, -11.0), Vector3(0.0, 0, -19.5),
	Vector3(-5.0, 0, -2.5), Vector3(-8.5, 0, -6.5), Vector3(-3.2, 0, -8.0),
	Vector3(4.5, 0, -5.0), Vector3(6.5, 0, -9.5), Vector3(3.0, 0, -10.0),
	Vector3(-4.5, 0, -13.5), Vector3(-6.5, 0, -17.0), Vector3(-3.0, 0, -17.6),
	Vector3(-3.0, 0, -25.0), Vector3(3.5, 0, -27.0), Vector3(0.0, 0, -32.0), Vector3(-4.0, 0, -31.0),
	Vector3(3.6, 0, -14.0), Vector3(5.0, 0, -19.0), Vector3(7.5, 0, -20.0),
]
const LAIR := Vector3(3.1, 0.0, -31.0)


static func bake(level: Node3D) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	region.name = "KeeperNav"
	level.add_child(region)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.agent_radius = 0.4
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 40.0
	nm.region_min_size = 4.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1 | 8
	nm.filter_baking_aabb = AABB(Vector3(-26, -1, -36), Vector3(56, 6, 46))
	# leave the doors out of the bake
	var saved := []
	for d in level.get_tree().get_nodes_in_group("doors"):
		var panel: CollisionObject3D = d.get("_panel")
		if panel:
			saved.append([panel, panel.collision_layer])
			panel.collision_layer = 0
	for h in level.get_tree().get_nodes_in_group("hiding_spots"):
		saved.append([h, (h as CollisionObject3D).collision_layer])
		(h as CollisionObject3D).collision_layer = 0
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, level)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	for s in saved:
		(s[0] as CollisionObject3D).collision_layer = s[1]
	var map := level.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	region.navigation_mesh = nm
	return region
