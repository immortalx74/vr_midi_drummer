App = {}

local MIDI = require "luamidi"
local UI = require "ui/ui"
local Phywire = require "phywire"
local Json = require "json"

local e_mode = { play = 1, move_piece = 2, move_kit = 3 }
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

local drag_table = {}
local len_test = 0
local moved_piece = nil
local drag_offset = lovr.math.newMat4()
local MIDI_ports = {}
local cur_MIDI_port = 0
local mode = e_mode.play
local setup_window_pose = lovr.math.newMat4( vec3( -0.5, 1.5, -0.5 ), quat( 1, 0, 0, 0 ) )
local show_colliders = true
local vs = lovr.filesystem.read( "light.vs" )
local fs = lovr.filesystem.read( "light.fs" )
local shader = lovr.graphics.newShader( vs, fs )
local world = lovr.physics.newWorld( 0, 0, 0, false, { "drums", "stickL", "stickR" } )
local mdl_stick, mdl_cymbal, mdl_drum
local cur_piece_index = 1
local cur_drum_kit_index = 1
local event_info = { note = 0, velocity = 0 }
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
		pose = lovr.math.newMat4( vec3( 0.75, 0.5, -0.2917 ), vec3( 0.4064, 0.3556, 0.4064 ), quat() ),
		name = "Tom 16 X 14",
		collider = nil,
		note = 41
	},
	{
		type = e_drum_kit_piece_type.hihat,
		pose = lovr.math.newMat4( vec3( 0.39312, 1, -0.32883 ), vec3( 0.3556, 0.5, 0.3556 ), quat() ),
		name = "Hihat 14",
		collider = nil,
		note = 61
	},
	{
		type = e_drum_kit_piece_type.cymbal,
		pose = lovr.math.newMat4( vec3( -0.19, 1.5, -0.913 ), vec3( 0.4572, 0.5, 0.4572 ), quat( 0.3839, 1, 0, 0 ) ),
		name = "Cymbal 18",
		collider = nil,
		note = 55
	},
	{
		type = e_drum_kit_piece_type.cymbal,
		pose = lovr.math.newMat4( vec3( 0.4599, 1.5, -0.9179 ), vec3( 0.4826, 0.5, 0.4826 ), quat( 0.5794, 1, 0, 0 ) ),
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
	left_tip = lovr.math.newVec3( 0, 0, 0 ),
	right_tip = lovr.math.newVec3( 0, 0, 0 ),
	left_vel = 0,
	right_vel = 0,
	left_colliding_drum = nil,
	right_colliding_drum = nil,
	left_colliding_drum_prev = nil,
	right_colliding_drum_prev = nil,
	length = 0.4318,
	rotation = -0.35,
	pivot_offset = 0.12,
	left = lovr.math.newMat4(),
	right = lovr.math.newMat4(),
	left_tip_prev = lovr.math.newVec3( 0, 0, 0 ),
	right_tip_prev = lovr.math.newVec3( 0, 0, 0 )
}

local function ReadFileToSTring( filename )
	local f = assert( io.open( filename, "rb" ) )
	local str = f:read( "*all" )
	f:close()
	return str
end

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
	pass:setColor( 1, 1, 1 )
	pass:skybox( cube )
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
		-- drum_kits[ cur_drum_kit_index ][ i ].pose:set( vec3( x + dx, y + dy, z + dz ), vec3( sx, sy, sz ), quat( angle, ax, ay, az ) )
		drum_kits[ cur_drum_kit_index ][ i ].pose[ 1 ] = drum_kits[ cur_drum_kit_index ][ i ].pose[ 1 ] + dy
		-- drum_kits[ cur_drum_kit_index ][ i ].collider:setPosition( x + dx, y + dy, z + dz )
		local x, y, z, sx, sy, sz, angle, ax, ay, az = drum_kits[ cur_drum_kit_index ][ i ].pose:unpack()
		drum_kits[ cur_drum_kit_index ][ i ].collider:setPose( vec3( x, y, z ), quat( angle, ax, ay, az ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )
	end
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
	sticks.left_tip = lovr.math.newVec3( m )
	sticks.left_vel = MapRange( 0, 0.14, 0, 127, sticks.left_tip:distance( sticks.left_tip_prev ) )
	if sticks.left_tip.y > sticks.left_tip_prev.y then sticks.left_vel = 0 end
	sticks.left_vel = math.floor( sticks.left_vel )
	if sticks.left_vel < 0 then sticks.left_vel = 0 end
	if sticks.left_vel > 127 then sticks.left_vel = 127 end
	sticks.left_tip_prev = sticks.left_tip

	local pos = vec3( lovr.headset.getPosition( "hand/right" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/right" ) )
	local m = mat4( pos, ori ):rotate( sticks.rotation, 1, 0, 0 ):translate( 0, 0, -sticks.pivot_offset / sticks.length ):scale( 0.05 )
	sticks.right_tip = lovr.math.newVec3( m )
	sticks.right_vel = MapRange( 0, 0.14, 0, 127, sticks.right_tip:distance( sticks.right_tip_prev ) )
	if sticks.right_tip.y > sticks.right_tip_prev.y then sticks.right_vel = 0 end
	sticks.right_vel = math.floor( sticks.right_vel )
	if sticks.right_vel < 0 then sticks.right_vel = 0 end
	if sticks.right_vel > 127 then sticks.right_vel = 127 end
	sticks.right_tip_prev = sticks.right_tip
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

local function LoadKits()
	local str = ReadFileToSTring( "kitout.txt" )
	local decoded = Json.decode( str )
	local kits = Json.decode( str )

	local num_kits = #kits
	for i = 1, num_kits do
		local cur_kit = {}
		cur_kit.name = kits[ i ][ "kitname" ]
		local num_pieces = #kits[ i ][ "kitpieces" ]

		for j = 1, num_pieces do
			local cur_piece = {}
			cur_piece.name = kits[ i ][ "kitpieces" ][ j ][ "name" ]
			cur_piece.note = kits[ i ][ "kitpieces" ][ j ][ "note" ]
			cur_piece.type = kits[ i ][ "kitpieces" ][ j ][ "type" ]
			local f = kits[ i ][ "kitpieces" ][ j ][ "pose" ]
			cur_piece.pose = lovr.math.newMat4( vec3( f[ 1 ], f[ 2 ], f[ 3 ] ), vec3( f[ 4 ], f[ 5 ], f[ 6 ] ), quat( f[ 7 ], f[ 8 ], f[ 9 ], f[ 10 ] ) )
			table.insert( cur_kit, cur_piece )
		end
		table.insert( drum_kits, cur_kit )
	end
end

local function SaveKits()
	local f = io.open( "kitout.txt", "wb" )
	local kits = {}
	local num_kits = #drum_kits

	for i = 1, num_kits do
		local cur_kit = {}
		cur_kit[ "kitname" ] = drum_kits[ i ].name
		cur_kit[ "kitpieces" ] = {}
		local num_pieces = #drum_kits[ i ]
		for j = 1, num_pieces do
			local cur_piece = {}
			cur_piece[ "name" ] = drum_kits[ i ][ j ].name
			cur_piece[ "note" ] = drum_kits[ i ][ j ].note
			cur_piece[ "type" ] = drum_kits[ i ][ j ].type
			local x, y, z, sx, sy, sz, angle, ax, ay, az = drum_kits[ i ][ j ].pose:unpack()
			local pose = { x, y, z, sx, sy, sz, angle, ax, ay, az }
			cur_piece.pose = pose
			table.insert( cur_kit[ "kitpieces" ], cur_piece )
		end
		table.insert( kits, cur_kit )
	end

	local out = Json.encode( kits )
	f:write( out )
	io.close( f )
end

local function DrawUI( pass )
	UI.NewFrame( pass )
	UI.Begin( "FirstWindow", setup_window_pose )

	UI.Label( "Event: Note - " .. event_info.note .. ", Velocity - " .. event_info.velocity )

	UI.Label( "MIDI ports", true )
	local _, mp = UI.ListBox( "MIDI_ports", 5, 27, MIDI_ports, 1 )
	cur_MIDI_port = mp - 1

	UI.Label( "Drum Kits", true )
	local dkits = {}
	for i, v in ipairs( drum_kits ) do
		table.insert( dkits, v.name )
	end
	UI.ListBox( "kits", 6, 27, dkits, 1 )
	UI.SameLine()
	UI.Button( "Add kit", 300 )
	UI.SameColumn()
	UI.Button( "Delete kit", 300 )
	UI.SameColumn()
	if UI.Button( "Save all", 300 ) then
		SaveKits()
	end

	UI.Label( "Pieces", true )
	local pieces = {}
	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		table.insert( pieces, v.name )
	end
	local _, cur_piece_index = UI.ListBox( "pieces", 12, 27, pieces, 1 )
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
	changed, drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note = UI.SliderInt( "Mapped note", drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note, 0, 127 )

	if UI.CheckBox( "Show colliders", show_colliders ) then show_colliders = not show_colliders end
	UI.End( pass )

	ui_passes = UI.RenderFrame( pass )
end

function lovr.keypressed( key, scancode, repeating )
	if key == "space" then
		MIDI.noteOn( cur_MIDI_port, drum_kits[ cur_drum_kit_index ][ 2 ].note, 127, 1 )
	end
	local m = key
	print( m )
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
	-- Load models
	mdl_stick = lovr.graphics.newModel( "devmeshes/stick.glb" )
	mdl_cymbal = lovr.graphics.newModel( "devmeshes/cymbal5.glb" )
	mdl_drum = lovr.graphics.newModel( "devmeshes/drum3.glb" )

	LoadKits()

	-- Setup colliders
	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		local x, y, z, sx, sy, sz = v.pose:unpack()
		if v.type == e_drum_kit_piece_type.cymbal or v.type == e_drum_kit_piece_type.hihat then
			v.collider = world:newCylinderCollider( 0, 0, 0, sx / 2, 0.1 )
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

	if lovr.headset.isDown( "hand/right", "a" ) then
		mode = e_mode.move_piece
	end
	if lovr.headset.wasReleased( "hand/right", "a" ) then
		moved_piece = nil
		mode = e_mode.play
	end

	if lovr.headset.isDown( "hand/right", "b" ) then
		mode = e_mode.move_kit
	end
	if lovr.headset.wasReleased( "hand/right", "b" ) then
		moved_piece = nil
		mode = e_mode.play
	end

	if mode == e_mode.move_piece then
		if moved_piece == nil then
			for shapeA, shapeB in world:overlaps() do
				local are_colliding = world:collide( shapeA, shapeB )
				if are_colliding then
					if shapeB:getCollider():getTag() == "drums" and shapeA:getCollider():getTag() == "stickR" and lovr.headset.wasPressed( "hand/right", "a" ) then
						moved_piece = shapeB:getCollider():getUserData()
						drag_offset:set( mat4( lovr.headset.getPose( "hand/right" ) ):invert() * drum_kits[ cur_drum_kit_index ][ moved_piece ].pose )
					end
					if shapeA:getCollider():getTag() == "drums" and shapeB:getCollider():getTag() == "stickR" and lovr.headset.wasPressed( "hand/right", "a" ) then
						moved_piece = shapeA:getCollider():getUserData()
						drag_offset:set( mat4( lovr.headset.getPose( "hand/right" ) ):invert() * drum_kits[ cur_drum_kit_index ][ moved_piece ].pose )
					end
				end
			end
		end

		if moved_piece ~= nil then
			drum_kits[ cur_drum_kit_index ][ moved_piece ].pose:set( mat4( lovr.headset.getPose( "hand/right" ) ) * drag_offset )
			drum_kits[ cur_drum_kit_index ][ moved_piece ].collider:setPose( vec3( drum_kits[ cur_drum_kit_index ][ moved_piece ].pose ),
				quat( drum_kits[ cur_drum_kit_index ][ moved_piece ].pose ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )
		end
	end

	if mode == e_mode.move_kit then
		if moved_piece == nil then
			for shapeA, shapeB in world:overlaps() do
				local are_colliding = world:collide( shapeA, shapeB )
				if are_colliding then
					if shapeB:getCollider():getTag() == "drums" and shapeA:getCollider():getTag() == "stickR" and lovr.headset.wasPressed( "hand/right", "b" ) then
						moved_piece = shapeB:getCollider():getUserData()
						drag_table = {}
						for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
							local m = lovr.math.newMat4()
							m:set( mat4( lovr.headset.getPose( "hand/right" ) ):invert() * drum_kits[ cur_drum_kit_index ][ i ].pose )
							table.insert( drag_table, m )
						end
					end
					if shapeA:getCollider():getTag() == "drums" and shapeB:getCollider():getTag() == "stickR" and lovr.headset.wasPressed( "hand/right", "b" ) then
						moved_piece = shapeA:getCollider():getUserData()
						drag_table = {}
						for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
							local m = lovr.math.newMat4()
							m:set( mat4( lovr.headset.getPose( "hand/right" ) ):invert() * drum_kits[ cur_drum_kit_index ][ i ].pose )
							table.insert( drag_table, m )
						end
					end
				end
			end
		end

		if moved_piece ~= nil then
			for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
				drum_kits[ cur_drum_kit_index ][ i ].pose:set( mat4( lovr.headset.getPose( "hand/right" ) ) * drag_table[ i ] )
				drum_kits[ cur_drum_kit_index ][ i ].collider:setPose( vec3( drum_kits[ cur_drum_kit_index ][ i ].pose ),
					quat( drum_kits[ cur_drum_kit_index ][ i ].pose ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )
			end
		end
	end

	if mode == e_mode.play then
		local L_col_this_frame = false
		local R_col_this_frame = false

		for shapeA, shapeB in world:overlaps() do
			local are_colliding = world:collide( shapeA, shapeB )
			if are_colliding then
				if shapeA:getCollider():getTag() == "drums" then
					if shapeB:getCollider():getTag() == "stickL" then
						L_col_this_frame = true
						if sticks.left_colliding_drum == nil then
							sticks.left_colliding_drum = shapeA:getCollider():getUserData()
						end
					elseif shapeB:getCollider():getTag() == "stickR" then
						R_col_this_frame = true
						if sticks.right_colliding_drum == nil then
							sticks.right_colliding_drum = shapeA:getCollider():getUserData()
						end
					end
				elseif shapeB:getCollider():getTag() == "drums" then
					if shapeA:getCollider():getTag() == "stickL" then
						L_col_this_frame = true
						if sticks.left_colliding_drum == nil then
							sticks.left_colliding_drum = shapeB:getCollider():getUserData()
						end
					elseif shapeA:getCollider():getTag() == "stickR" then
						R_col_this_frame = true
						if sticks.right_colliding_drum == nil then
							sticks.right_colliding_drum = shapeB:getCollider():getUserData()
						end
					end
				end
			end
		end

		if sticks.left_colliding_drum ~= nil then
			if sticks.left_colliding_drum_prev == nil or sticks.left_colliding_drum_prev ~= sticks.left_colliding_drum then
				MIDI.noteOn( cur_MIDI_port, drum_kits[ cur_drum_kit_index ][ sticks.left_colliding_drum ].note, sticks.left_vel, 1 )
				sticks.left_colliding_drum_prev = sticks.left_colliding_drum
				event_info.note = drum_kits[ cur_drum_kit_index ][ sticks.left_colliding_drum ].note
				if sticks.left_vel > 0 then event_info.velocity = sticks.left_vel end
			end
		end

		if sticks.right_colliding_drum ~= nil then
			if sticks.right_colliding_drum_prev == nil or sticks.right_colliding_drum_prev ~= sticks.right_colliding_drum then
				MIDI.noteOn( cur_MIDI_port, drum_kits[ cur_drum_kit_index ][ sticks.right_colliding_drum ].note, sticks.right_vel, 1 )
				sticks.right_colliding_drum_prev = sticks.right_colliding_drum
				event_info.note = drum_kits[ cur_drum_kit_index ][ sticks.right_colliding_drum ].note
				if sticks.right_vel > 0 then event_info.velocity = sticks.right_vel end
			end
		end

		if not L_col_this_frame then
			sticks.left_colliding_drum = nil
			sticks.left_colliding_drum_prev = nil
		end
		if not R_col_this_frame then
			sticks.right_colliding_drum = nil
			sticks.right_colliding_drum_prev = nil
		end
	end

	UI.InputInfo()
end

function App.RenderFrame( pass )
	DrawUI( pass )
	SetEnvironment( pass )
	ShaderOn( pass )
	DrawDrumKit( pass )
	DrawSticks( pass )

	local m = mat4( sticks.left_tip, vec3( 0.03 ) )
	-- pass:box( m )

	ShaderOff( pass )
	if show_colliders then Phywire.draw( pass, world, Phywire.render_shapes ) end
end

return App
