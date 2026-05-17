## OpenIsopix - Isometric Renderer
## Renders the block-based world in isometric view

class_name IsometricRenderer
extends Node2D

@export var world_api: WorldAPI
@export var camera: IsometricCamera

## Rendering layers
var world_layer: Node2D
var fog_layer: CanvasLayer

## Cache for rendered sprites
var block_sprites: Dictionary = {}
var textures: Dictionary = {}
var animated_blocks: Dictionary = {}
var animation_time: float = 0.0

func _ready():
	pass

func _process(delta: float):
	if animated_blocks.is_empty():
		return

	animation_time += delta
	_update_animated_blocks()

func initialize():
	_setup_layers()
	_generate_placeholder_textures()

	if world_api:
		world_api.block_added.connect(_on_block_added)
		world_api.block_removed.connect(_on_block_removed)
		world_api.block_modified.connect(_on_block_modified)
		world_api.chunk_loaded.connect(_on_chunk_loaded)

	if camera:
		camera.heading_changed.connect(_on_heading_changed)
		camera.pitch_changed.connect(_on_pitch_changed)

func _setup_layers():
	world_layer = Node2D.new()
	add_child(world_layer)

	fog_layer = CanvasLayer.new()
	fog_layer.layer = 2
	add_child(fog_layer)

func _generate_placeholder_textures():
	# Load isometric SVG textures for block types
	textures["grass"] = load("res://assets/blocks/isometric-grass.svg")
	textures["stone"] = load("res://assets/blocks/isometric-stone.svg")
	textures["water"] = load("res://assets/blocks/isometric-water.svg")
	textures["wood"] = load("res://assets/blocks/isometric-wood.svg")
	textures["soil"] = load("res://assets/blocks/isometric-soil.svg")

	print("Loaded isometric block textures: ", textures.keys())

func render_world():
	# Clear existing sprites
	_clear_all_sprites()

	if not world_api:
		return

	# Get all chunks and render blocks
	for chunk_key in world_api.chunks.keys():
		var chunk = world_api.chunks[chunk_key]
		if chunk.is_loaded:
			_render_chunk(chunk)

func _render_chunk(chunk: Chunk):
	var blocks = chunk.get_all_blocks()
	# Sort for painter's algorithm (back to front)
	blocks.sort_custom(_sort_blocks_for_rendering)

	for block in blocks:
		_render_block(block)

func _render_block(block: BlockInstance):
	if not block or not block.block_type:
		return

	var world_pos = block.position
	var key = _world_pos_to_key(world_pos)

	# Create sprite if it doesn't exist
	if not block_sprites.has(key):
		var sprite = Sprite2D.new()
		world_layer.add_child(sprite)
		block_sprites[key] = sprite

	var sprite = block_sprites[key]

	# Set texture
	var texture = _get_block_texture(block)
	if texture:
		sprite.texture = texture
	else:
		print("WARNING: No texture for block type: ", block.block_type.id)

	var iso_pos = camera.world_to_iso(Vector3(world_pos.x, world_pos.y, world_pos.z))
	sprite.position = iso_pos
	var height_scale = block.height
	sprite.scale = Vector2(1, height_scale)

	# Apply lighting
	sprite.modulate = Color(block.light_level, block.light_level, block.light_level, 1.0)

	# Apply fog of war
	if not block.is_revealed:
		sprite.modulate.a = 0.3

	# Z-index for proper layering
	sprite.z_index = world_pos.x + world_pos.z + world_pos.y * 1000

	if _is_block_animated(block):
		animated_blocks[key] = block
	else:
		animated_blocks.erase(key)

func _get_block_texture(block: BlockInstance) -> Texture2D:
	if not block or not block.block_type:
		return null

	var frame = block.block_type.get_current_frame(animation_time)
	if frame:
		return frame

	return textures.get(block.block_type.id)

func _is_block_animated(block: BlockInstance) -> bool:
	return (
		block
		and block.block_type
		and block.block_type.animated
		and not block.block_type.animation_frames.is_empty()
	)

func _update_animated_blocks():
	for key in animated_blocks.keys():
		var block = animated_blocks[key]
		if not block or not block_sprites.has(key):
			animated_blocks.erase(key)
			continue

		var sprite = block_sprites[key]
		var texture = _get_block_texture(block)
		if texture:
			sprite.texture = texture

func _clear_all_sprites():
	for key in block_sprites.keys():
		var sprite = block_sprites[key]
		if sprite:
			sprite.queue_free()
	block_sprites.clear()
	animated_blocks.clear()

func _remove_sprite(world_pos: Vector3i):
	var key = _world_pos_to_key(world_pos)
	if block_sprites.has(key):
		var sprite = block_sprites[key]
		sprite.queue_free()
		block_sprites.erase(key)
	animated_blocks.erase(key)

func _world_pos_to_key(pos: Vector3i) -> String:
	return str(pos.x) + "," + str(pos.y) + "," + str(pos.z)

func _sort_blocks_for_rendering(a: BlockInstance, b: BlockInstance) -> bool:
	var depth_a = a.position.x + a.position.z + a.position.y * 1000
	var depth_b = b.position.x + b.position.z + b.position.y * 1000
	return depth_a < depth_b

## Signal handlers
func _on_block_added(position: Vector3i, block: BlockInstance):
	_render_block(block)

func _on_block_removed(position: Vector3i):
	_remove_sprite(position)

func _on_block_modified(position: Vector3i, block: BlockInstance):
	_render_block(block)

func _on_chunk_loaded(chunk_pos: Vector2i):
	render_world()

func _on_heading_changed(new_heading):
	# Re-render world with new rotation
	render_world()

func _on_pitch_changed(new_pitch):
	# Re-render world with new pitch
	render_world()
