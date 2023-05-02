App = {}

local MIDI = require "luamidi"
local UI = require "ui/ui"
local Phywire = require "phywire"

local e_axis = { x = 1, y = 2, z = 3 }

local e_drum_kit_piece_type = {
	snare = 1,
	kick = 2,
	tom = 3,
	hihat = 4,
	cymbal = 5,
}

local common_sizes = {
	snare = { { 14, 5 }, { 14, 6 }, { 14, 7 } },         -- 14x5 = [0.3556, 0.127]
	kick = { { 20, 15 }, { 22, 16 }, { 22, 17 } },       -- 22x16 = [0.5588, 0.4064]
	tom = { { 10, 8 }, { 12, 9 }, { 14, 10 }, { 16, 14 } }, -- All [0.254, 0.2032], [0.3048, 0.2286], [0.3556, 0.254], [0.4064, 0.3556]
	hihat = { 13, 14, 15 },                              -- 14 = [0.3556]
	cymbal = { 14, 18, 19, 21 },                         -- CrashL 18, CrashR 19, Ride 21 = [0.4572, 0.4826, 0.5334]
}

local MIDI_ports = {}
local cur_MIDI_port = 0
local setup_window_pose = lovr.math.newMat4( vec3( -0.5, 1.3, -0.5 ), quat( 1, 0, 0, 0 ) )
local cur_collider_id = nil
local show_colliders = true
local vs = lovr.filesystem.read( "light.vs" )
local fs = lovr.filesystem.read( "light.fs" )
local shader = lovr.graphics.newShader( vs, fs )
local world = lovr.physics.newWorld( 0, 0, 0, false, { "drums", "stickL", "stickR" } )
local mdl_stick, mdl_cymbal, mdl_drum
local cur_piece_index = 1
local cur_drum_kit_index = 1
local drum_kits = {}

local default_drum_kit = {
	name = "Default",
	num_pieces = 10,
	{
		type = e_drum_kit_piece_type.snare,
		pose = lovr.math.newMat4( vec3( 0, 0.78, -0.5 ), vec3( 0.3556, 0.127, 0.3556 ), quat() ),
		name = "Snare 14 X 15",
		collider = nil,
		note = 38
	},
	{
		type = e_drum_kit_piece_type.kick,
		pose = lovr.math.newMat4( vec3( 0.3437, 0.28, -0.70768 ), vec3( 0.5588, 0.4064, 0.5588 ), quat( 1.5708, 1, 0, 0 ) ),
		name = "Kick 22 X 16",
		collider = nil,
		note = 36
	},
	{
		type = e_drum_kit_piece_type.tom,
		pose = lovr.math.newMat4( vec3( 0, 0.87, -0.8152 ), vec3( 0.254, 0.2032, 0.254 ), quat( 0.5637, 1, 0, 0 ) ),
		name = "Tom 10 X 8",
		collider = nil,
		note = 48
	},
	{
		type = e_drum_kit_piece_type.tom,
		pose = lovr.math.newMat4( vec3( 0.2959, 0.86, -0.81908 ), vec3( 0.3048, 0.2286, 0.3048 ), quat( 0.541, 1, 0, 0 ) ),
		name = "Tom 12 X 9",
		collider = nil,
		note = 47
	},
	{
		type = e_drum_kit_piece_type.tom,
		pose = lovr.math.newMat4( vec3( 0.6398, 0.8, -0.6972 ), vec3( 0.3556, 0.254, 0.3556 ), quat( 0.6562, 1, 0, 0 ) ),
		name = "Tom 14 X 10",
		collider = nil,
		note = 43
	},
	{
		type = e_drum_kit_piece_type.tom,
		pose = lovr.math.newMat4( vec3( 0.6, 0.5, -0.3917 ), vec3( 0.4064, 0.3556, 0.4064 ), quat() ),
		name = "Tom 16 X 14",
		collider = nil,
		note = 41
	},
	{
		type = e_drum_kit_piece_type.hihat,
		pose = lovr.math.newMat4( vec3( 0.39312, 0.96, -0.32883 ), vec3( 0.3556, 0.5, 0.3556 ), quat() ),
		name = "Hihat 14",
		collider = nil,
		note = 61
	},
	{
		type = e_drum_kit_piece_type.cymbal,
		pose = lovr.math.newMat4( vec3( -0.19, 1.25, -0.913 ), vec3( 0.4572, 0.5, 0.4572 ), quat( 0.3839, 1, 0, 0 ) ),
		name = "Cymbal 18",
		collider = nil,
		note = 55
	},
	{
		type = e_drum_kit_piece_type.cymbal,
		pose = lovr.math.newMat4( vec3( 0.4599, 1.24, -0.9179 ), vec3( 0.4826, 0.5, 0.4826 ), quat( 0.5794, 1, 0, 0 ) ),
		name = "Cymbal 19",
		collider = nil,
		note = 57
	},
	{
		type = e_drum_kit_piece_type.cymbal,
		pose = lovr.math.newMat4( vec3( -0.5698, 1, -0.6482 ), vec3( 0.5334, 0.5, 0.5334 ), quat( 0.5235, 1, 0, 0 ) ),
		name = "Cymbal 21",
		collider = nil,
		note = 52
	},
}

local sticks = {
	left_collider = nil,
	right_collider = nil,
	left_tip = nil,
	right_tip = nil,
	left_len_prev = 0,
	left_len_cur = 0,
	right_len_prev = 0,
	right_len_cur = 0,
	left_vel = 0,
	right_vel = 0,
	length = 0.4318,
	rotation = -0.35,
	pivot_offset = 0.12,
	left = lovr.math.newMat4(),
	right = lovr.math.newMat4()
}

local function ShaderOn( pass )
	pass:setShader( shader )
	local lightPos = vec3( -3, 6.0, -1.0 )
	pass:setColor( 1, 1, 1 )
	pass:box( lightPos )
	pass:send( 'ambience', { 0.05, 0.05, 0.05, 1.0 } )
	pass:send( 'lightColor', { 1.0, 1.0, 1.0, 1.0 } )
	pass:send( 'lightPos', lightPos )
	pass:send( 'specularStrength', 0.5 )
	pass:send( 'metallic', 32.0 )
end

local function ShaderOff( pass )
	pass:setShader()
end

local function SetEnvironment( pass )
	pass:setColor( .1, .1, .12 )
	pass:plane( 0, 0, 0, 25, 25, -math.pi / 2, 1, 0, 0 )
	pass:setColor( .2, .2, .2 )
	pass:plane( 0, 0, 0, 25, 25, -math.pi / 2, 1, 0, 0, 'line', 50, 50 )
end

local function MapRange( from_min, from_max, to_min, to_max, v )
	return (v - from_min) * (to_max - to_min) / (from_max - from_min) + to_min
end

local function MoveDrumKit( axis, distance )
	local dx = 0
	local dy = 0
	local dz = 0
	if axis == e_axis.x then dx = distance end
	if axis == e_axis.y then dy = distance end
	if axis == e_axis.z then dz = distance end

	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		local x, y, z, sx, sy, sz, angle, ax, ay, az = drum_kits[ cur_drum_kit_index ][ i ].pose:unpack()
		drum_kits[ cur_drum_kit_index ][ i ].pose:set( vec3( x + dx, y + dy, z + dz ), vec3( sx, sy, sz ), quat( angle, ax, ay, az ) )
		drum_kits[ cur_drum_kit_index ][ i ].collider:setPosition( x + dx, y + dy, z + dz )
	end
end

local function DrawUI( pass )
	UI.NewFrame( pass )
	UI.Begin( "FirstWindow", setup_window_pose )

	UI.Label( "MIDI ports", true )
	local _, mp = UI.ListBox( "MIDI_ports", 5, 20, MIDI_ports, 1 )
	cur_MIDI_port = mp - 1

	UI.Label( "Drum Kits", true )
	local dkits = {}
	for i, v in ipairs( drum_kits ) do
		table.insert( dkits, v.name )
	end
	UI.ListBox( "kits", 5, 20, dkits, 1 )
	UI.SameLine()
	UI.Button( "Add kit", 300 )
	UI.SameColumn()
	UI.Button( "Delete kit", 300 )

	UI.Label( "Pieces", true )
	local pieces = {}
	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		table.insert( pieces, v.name )
	end
	local _, cur_piece_index = UI.ListBox( "pieces", 12, 20, pieces, 1 )
	UI.SameLine()
	UI.Button( "Add piece", 300 )
	UI.SameColumn()
	UI.Button( "Delete piece", 300 )

	if UI.Button( "-" ) then
		if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note > 0 then
			drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note - 1
		end
	end

	UI.SameLine()

	if UI.Button( "+" ) then
		if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note < 127 then
			drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note + 1
		end
	end

	UI.SameLine()
	local changed = false
	changed, drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note = UI.SliderInt( "Note", drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note, 0, 127 )

	if UI.Button( "-X" ) then MoveDrumKit( e_axis.x, -0.1 ) end
	UI.SameLine()
	if UI.Button( "+X" ) then MoveDrumKit( e_axis.x, 0.1 ) end
	UI.SameLine()
	if UI.Button( "-Y" ) then MoveDrumKit( e_axis.y, -0.1 ) end
	UI.SameLine()
	if UI.Button( "+Y" ) then MoveDrumKit( e_axis.y, 0.1 ) end
	UI.SameLine()
	if UI.Button( "-Z" ) then MoveDrumKit( e_axis.z, -0.1 ) end
	UI.SameLine()
	if UI.Button( "+Z" ) then MoveDrumKit( e_axis.z, 0.1 ) end

	if UI.CheckBox( "Show colliders", show_colliders ) then show_colliders = not show_colliders end
	UI.End( pass )

	ui_passes = UI.RenderFrame( pass )
end

local function UpdateSticksColliders()
	local hand_poseL = mat4( vec3( lovr.headset.getPosition( "hand/left" ) ), vec3( 1, 1, 1 ), quat( lovr.headset.getOrientation( "hand/left" ) ) ):rotate( sticks.rotation, 1, 0, 0 ):translate( 0, 0,
		-sticks.pivot_offset )
	sticks.left_collider:setPosition( vec3( hand_poseL ) )
	sticks.left_collider:setOrientation( quat( hand_poseL ) )

	local hand_poseR = mat4( vec3( lovr.headset.getPosition( "hand/right" ) ), vec3( 1, 1, 1 ), quat( lovr.headset.getOrientation( "hand/right" ) ) ):rotate( sticks.rotation, 1, 0, 0 ):translate( 0, 0,
		-sticks.pivot_offset )
	sticks.right_collider:setPosition( vec3( hand_poseR ) )
	sticks.right_collider:setOrientation( quat( hand_poseR ) )
end

local function UpdateSticksVelocity()
	local pos = vec3( lovr.headset.getPosition( "hand/left" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/left" ) )
	local m = mat4( pos, ori ):rotate( sticks.rotation, 1, 0, 0 ):translate( 0, 0, -sticks.pivot_offset / sticks.length ):scale( 0.05 )
	sticks.left_tip = vec3( m )
	sticks.left_len_cur = sticks.left_tip:length()
	sticks.left_vel = sticks.left_len_prev - sticks.left_len_cur
	sticks.left_len_prev = sticks.left_tip:length()

	local pos = vec3( lovr.headset.getPosition( "hand/right" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/right" ) )
	local m = mat4( pos, ori ):rotate( sticks.rotation, 1, 0, 0 ):translate( 0, 0, -sticks.pivot_offset / sticks.length ):scale( 0.05 )
	sticks.right_tip = vec3( m )
	sticks.right_len_cur = sticks.right_tip:length()
	sticks.right_vel = sticks.right_len_prev - sticks.right_len_cur
	sticks.right_len_prev = sticks.right_tip:length()
end

local function DrawDrumKit( pass )
	local cur_kit = drum_kits[ cur_drum_kit_index ]
	for i, v in ipairs( cur_kit ) do
		if v.type == e_drum_kit_piece_type.cymbal or v.type == e_drum_kit_piece_type.hihat then
			pass:draw( mdl_cymbal, v.pose )
		else
			pass:draw( mdl_drum, v.pose )
		end
	end
end

local function DrawSticks( pass )
	local pos = vec3( lovr.headset.getPosition( "hand/right" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/right" ) )

	local pose = mat4( pos, vec3( 0.43, 0.43, sticks.length ), ori ):rotate( sticks.rotation, 1, 0, 0 ):translate( 0, 0, sticks.pivot_offset / sticks.length )
	pass:draw( mdl_stick, pose )
	pass:box( pos, vec3( 0.03 ), ori )

	local pos = vec3( lovr.headset.getPosition( "hand/left" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/left" ) )

	local pose = mat4( pos, vec3( 0.43, 0.43, sticks.length ), ori ):rotate( sticks.rotation, 1, 0, 0 ):translate( 0, 0, sticks.pivot_offset / sticks.length )
	pass:draw( mdl_stick, pose )
end

function App.Init()
	UI.Init()

	-- Setup MIDI ports
	local num_ports = MIDI.getoutportcount()
	for i = 0, num_ports do
		if MIDI.getOutPortName( i ) == "" then
			table.insert( MIDI_ports, "--no name--" )
		else
			table.insert( MIDI_ports, MIDI.getOutPortName( i ) )
		end
	end
	-- Set default drum kit
	table.insert( drum_kits, default_drum_kit )
	-- Load models
	mdl_stick = lovr.graphics.newModel( "devmeshes/stick.glb" )
	mdl_cymbal = lovr.graphics.newModel( "devmeshes/cymbal2.glb" )
	mdl_drum = lovr.graphics.newModel( "devmeshes/drum2.glb" )

	-- Setup colliders
	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		local x, y, z, sx, sy, sz = v.pose:unpack()
		if v.type == e_drum_kit_piece_type.cymbal or v.type == e_drum_kit_piece_type.hihat then
			v.collider = world:newCylinderCollider( 0, 0, 0, sx / 2, 0.05 )
		else
			v.collider = world:newCylinderCollider( 0, 0, 0, sx / 2, sy )
		end
		local q = quat( v.pose )
		v.collider:setPosition( x, y, z )
		v.collider:setOrientation( quat( math.pi / 2, 1, 0, 0 ):mul( q ) )
		v.collider:setKinematic( true )
		v.collider:setTag( "drums" )
		v.collider:setUserData( i )
	end

	sticks.left_collider = world:newCylinderCollider( 0, 0, 0, 0.01, sticks.length )
	sticks.left_collider:setKinematic( true )
	sticks.left_collider:setTag( "stickL" )
	sticks.right_collider = world:newCylinderCollider( 0, 0, 0, 0.01, sticks.length )
	sticks.right_collider:setKinematic( true )
	sticks.right_collider:setTag( "stickR" )

	world:disableCollisionBetween( "stickL", "stickR" )
	world:disableCollisionBetween( "drums", "drums" )
end

function App.Update( dt )
	UpdateSticksColliders()
	UpdateSticksVelocity()

	world:update( dt )
	world:computeOverlaps()

	local collision_this_frame = false
	local vv = 0

	for shapeA, shapeB in world:overlaps() do
		local are_colliding = world:collide( shapeA, shapeB )
		if are_colliding and cur_collider_id == nil then
			collision_this_frame = true
			local vl = MapRange( 0, 0.07, 0, 125, sticks.left_vel )
			local vr = MapRange( 0, 0.07, 0, 125, sticks.right_vel )

			if shapeA:getCollider():getTag() == "drums" then
				cur_collider_id = shapeA:getCollider():getUserData()
				if shapeB:getCollider():getTag() == "stickL" then vv = vl end
				if shapeB:getCollider():getTag() == "stickR" then vv = vr end
				if vv > 125 then vv = 125 end
				if vv < 0 then vv = 0 end
				print( vv, "A", lovr.timer.getTime() )
				MIDI.noteOn( cur_MIDI_port, drum_kits[ cur_drum_kit_index ][ cur_collider_id ].note, vv, 1 )
				print( "port:", cur_MIDI_port )
			end
			if shapeB:getCollider():getTag() == "drums" then
				cur_collider_id = shapeB:getCollider():getUserData()
				if shapeA:getCollider():getTag() == "stickL" then vv = vl end
				if shapeA:getCollider():getTag() == "stickR" then vv = vr end
				if vv > 125 then vv = 125 end
				if vv < 0 then vv = 0 end
				print( vv, "B", lovr.timer.getTime() )
				MIDI.noteOn( cur_MIDI_port, drum_kits[ cur_drum_kit_index ][ cur_collider_id ].note, vv, 1 )
				print( "port:", cur_MIDI_port )
			end
		elseif are_colliding then
			collision_this_frame = true
			if shapeA:getCollider():getTag() == "drums" and shapeA:getCollider():getUserData() ~= cur_collider_id then
				cur_collider_id = nil
			end
			if shapeB:getCollider():getTag() == "drums" and shapeB:getCollider():getUserData() ~= cur_collider_id then
				cur_collider_id = nil
			end
		end
	end

	if not collision_this_frame then
		cur_collider_id = nil
	end


	UI.InputInfo()
end

function App.RenderFrame( pass )
	DrawUI( pass )
	SetEnvironment( pass )
	ShaderOn( pass )
	DrawDrumKit( pass )
	DrawSticks( pass )

	-- 0.4   0.1
	-- 1     X
	-- x = 0.1/0.4

	-- local pos = vec3( lovr.headset.getPosition( "hand/left" ) )
	-- local ori = quat( lovr.headset.getOrientation( "hand/left" ) )
	-- local m = mat4( pos, ori ):rotate( sticks.rotation, 1, 0, 0 ):translate( 0, 0, -sticks.pivot_offset / sticks.length):scale(0.05)
	-- pass:box( m )
	local m = mat4( sticks.left_tip, vec3( 0.03 ) )
	pass:box( m )

	ShaderOff( pass )
	if show_colliders then Phywire.draw( pass, world, Phywire.render_shapes ) end
end

return App
