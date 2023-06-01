App = {}

local MIDI = require "sampler"
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

local available_pieces = {
	{ "Snare 14 X 5", 0.3556, 0.127,  1 },
	{ "Snare 14 X 6", 0.3556, 0.1524, 1 },
	{ "Snare 14 X 7", 0.3556, 0.1778, 1 },
	{ "Kick 20 X 15", 0.508,  0.381,  2 },
	{ "Kick 22 X 16", 0.5588, 0.4064, 2 },
	{ "Kick 22 X 17", 0.5588, 0.4318, 2 },
	{ "Tom 10 X 8",   0.254,  0.2032, 3 },
	{ "Tom 12 X 9",   0.3048, 0.2286, 3 },
	{ "Tom 14 X 10",  0.3556, 0.254,  3 },
	{ "Tom 16 X 14",  0.4064, 0.3556, 3 },
	{ "Hihat 13",     0.3302, 0,      4 },
	{ "Hihat 14",     0.3556, 0,      4 },
	{ "Hihat 15",     0.381,  0,      4 },
	{ "Cymbal 14",    0.3556, 0,      5 },
	{ "Cymbal 18",    0.4572, 0,      5 },
	{ "Cymbal 19",    0.4826, 0,      5 },
	{ "Cymbal 21",    0.5334, 0,      5 },
}

local hihat_open_value = 127
local drum_kit_name = ""
local hihat_closed = false
local hihat_keybind = nil
local scheduled_off_notes = {}
local enable_haptics = true
local enable_hit_highlight = true
local keybind_window_open = false
local add_piece_window_open = false
local rename_kit_window_open = false
local key_pressed = nil
local drag_table = {}
local dragged_piece = nil
local drag_offset = lovr.math.newMat4()
local MIDI_ports = {}
local cur_MIDI_port = 0
local mode = e_mode.play
local setup_window_pose = lovr.math.newMat4( vec3( -1, 1, -0.6 ), quat( math.pi / 4, 0, 1, 0 ) )
local show_colliders = false
local skybox_tex = lovr.graphics.newTexture( "res/skybox.hdr", { mipmaps = false } )
local vs = lovr.filesystem.read( "light.vs" )
local fs = lovr.filesystem.read( "light.fs" )
local shader = lovr.graphics.newShader( vs, fs, { flags = { glow = true, normalMap = true, vertexTangents = false, tonemap = false } } )
local world = lovr.physics.newWorld( 0, 0, 0, false, { "drums", "stickL", "stickR", "drums_inner" } )
local mdl_stick, mdl_cymbal, mdl_drum, mdl_drum_highlight, mdl_cymbal_highlight
local cur_piece_index = 1
local cur_drum_kit_index = 1
local event_info = { note = 0, velocity = 0 }
local drum_kits = {}

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
	pass:skybox( skybox_tex )
	pass:setColor( 1, 1, 1 )
	pass:setShader( shader )
	local lightPos = vec3( 0, 2.5, -1.3 )
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
	lovr.graphics.setBackgroundColor( 1, 1, 1 )
	ShaderOff( pass )
	pass:setColor( 1, 1, 1 )
end

local function MapRange( from_min, from_max, to_min, to_max, v )
	return (v - from_min) * (to_max - to_min) / (from_max - from_min) + to_min
end

local function UpdateSticksColliders()
	local pos = vec3( lovr.headset.getPosition( "hand/left" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/left" ) )
	local pose = mat4( pos, quat() ):rotate( ori:mul( quat( sticks.rotation, 1, 0, 0 ) ) ):scale( vec3( 0.43, 0.43, sticks.length ) ):translate( 0, 0, -0.5 + (sticks.pivot_offset / sticks.length) )
	sticks.left_collider:setPose( vec3( pose ), quat( pose ) )

	local pos = vec3( lovr.headset.getPosition( "hand/right" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/right" ) )
	local pose = mat4( pos, quat() ):rotate( ori:mul( quat( sticks.rotation, 1, 0, 0 ) ) ):scale( vec3( 0.43, 0.43, sticks.length ) ):translate( 0, 0, -0.5 + (sticks.pivot_offset / sticks.length) )
	sticks.right_collider:setPose( vec3( pose ), quat( pose ) )
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

local function SetupDrumColliders()
	for i, v in ipairs( drum_kits ) do
		for j, k in ipairs( drum_kits[ i ] ) do
			if drum_kits[ i ][ j ].collider then
				drum_kits[ i ][ j ].collider:destroy()
				drum_kits[ i ][ j ].collider = nil
				drum_kits[ i ][ j ].collider_inner:destroy()
				drum_kits[ i ][ j ].collider_inner = nil
			end
		end
	end

	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		local x, y, z, sx, sy, sz = v.pose:unpack()

		if v.type == e_drum_kit_piece_type.cymbal or v.type == e_drum_kit_piece_type.hihat then
			v.collider = world:newCylinderCollider( 0, 0, 0, sx / 2, 0.08 )
			v.collider_inner = world:newCylinderCollider( 0, 0, 0, sx / 8, 0.08 )
		else
			v.collider = world:newCylinderCollider( 0, 0, 0, sx / 2, sy )
			v.collider_inner = world:newCylinderCollider( 0, 0, 0, sx / 2.6, sy )
		end

		local x, y, z, sx, sy, sz, angle, ax, ay, az = drum_kits[ cur_drum_kit_index ][ i ].pose:unpack()
		drum_kits[ cur_drum_kit_index ][ i ].collider:setPose( vec3( drum_kits[ cur_drum_kit_index ][ i ].pose ), quat( drum_kits[ cur_drum_kit_index ][ i ].pose ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )
		drum_kits[ cur_drum_kit_index ][ i ].collider_inner:setPose( vec3( drum_kits[ cur_drum_kit_index ][ i ].pose ),
			quat( drum_kits[ cur_drum_kit_index ][ i ].pose ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )

		v.collider:setKinematic( true )
		v.collider:setTag( "drums" )
		v.collider:setUserData( i )
		v.collider_inner:setKinematic( true )
		v.collider_inner:setTag( "drums_inner" )
		v.collider_inner:setUserData( i )
	end
end

local function DrawDrumKit( pass )
	local cur_kit = drum_kits[ cur_drum_kit_index ]

	for i, v in ipairs( cur_kit ) do
		if v.type == e_drum_kit_piece_type.cymbal then
			pass:draw( mdl_cymbal, v.pose )
			if enable_hit_highlight then
				if sticks.left_colliding_drum == i or sticks.right_colliding_drum == i then
					local m = mat4( v.pose ):translate( 0, 0.001, 0 )
					pass:setColor( 1, 0.9, 0.9 )
					pass:draw( mdl_cymbal_highlight, m )
					pass:setColor( 1, 1, 1 )
				end
			end
		elseif v.type == e_drum_kit_piece_type.hihat then
			local hihat_top_pose = mat4( v.pose )
			local dist = MapRange( 0, 127, 0, 0.03, hihat_open_value )
			hihat_top_pose:translate( 0, dist, 0 )
			pass:draw( mdl_cymbal, hihat_top_pose )
			local hihat_bottom_pose = mat4( v.pose ):rotate( math.pi, 1, 0, 0 )
			pass:draw( mdl_cymbal, hihat_bottom_pose )

			if enable_hit_highlight then
				if sticks.left_colliding_drum == i or sticks.right_colliding_drum == i then
					local m = mat4( hihat_top_pose ):translate( 0, 0.001, 0 )
					pass:setColor( 1, 0.9, 0.9 )
					pass:draw( mdl_cymbal_highlight, m )
					pass:setColor( 1, 1, 1 )
				end
			end
		else
			pass:draw( mdl_drum, v.pose )
			if enable_hit_highlight then
				if sticks.left_colliding_drum == i or sticks.right_colliding_drum == i then
					local m = mat4( v.pose ):translate( 0, 0.001, 0 )
					pass:setColor( 1, 0.9, 0.9 )
					pass:draw( mdl_drum_highlight, m )
					pass:setColor( 1, 1, 1 )
				end
			end
		end
	end
	pass:setColor( 1, 1, 1 )
end

local function DrawSticks( pass )
	local pos = vec3( lovr.headset.getPosition( "hand/left" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/left" ) )
	local pose = mat4( pos, quat() ):rotate( ori:mul( quat( sticks.rotation, 1, 0, 0 ) ) ):scale( vec3( 0.43, 0.43, sticks.length ) ):translate( 0, 0, sticks.pivot_offset / sticks.length )
	pass:draw( mdl_stick, pose )

	local pos = vec3( lovr.headset.getPosition( "hand/right" ) )
	local ori = quat( lovr.headset.getOrientation( "hand/right" ) )
	local pose = mat4( pos, quat() ):rotate( ori:mul( quat( sticks.rotation, 1, 0, 0 ) ) ):scale( vec3( 0.43, 0.43, sticks.length ) ):translate( 0, 0, sticks.pivot_offset / sticks.length )
	pass:draw( mdl_stick, pose )
end

local function LoadKits()
	local str = ReadFileToSTring( "kits.json" )
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
			cur_piece.note = { kits[ i ][ "kitpieces" ][ j ][ "note" ][ 1 ], kits[ i ][ "kitpieces" ][ j ][ "note" ][ 2 ] }
			cur_piece.type = kits[ i ][ "kitpieces" ][ j ][ "type" ]
			cur_piece.channel = kits[ i ][ "kitpieces" ][ j ][ "channel" ]

			if cur_piece.type == e_drum_kit_piece_type.hihat then
				cur_piece.note[ 3 ] = kits[ i ][ "kitpieces" ][ j ][ "note" ][ 3 ]
			end

			cur_piece.keybind = kits[ i ][ "kitpieces" ][ j ][ "keybind" ]

			local f = kits[ i ][ "kitpieces" ][ j ][ "pose" ]
			cur_piece.pose = lovr.math.newMat4( vec3( f[ 1 ], f[ 2 ], f[ 3 ] ), vec3( f[ 4 ], f[ 5 ], f[ 6 ] ), quat( f[ 7 ], f[ 8 ], f[ 9 ], f[ 10 ] ) )
			table.insert( cur_kit, cur_piece )
		end
		table.insert( drum_kits, cur_kit )
	end
end

local function SaveKits()
	local f = io.open( "kits.json", "wb" )
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
			cur_piece[ "note" ] = { drum_kits[ i ][ j ].note[ 1 ], drum_kits[ i ][ j ].note[ 2 ] }
			cur_piece[ "type" ] = drum_kits[ i ][ j ].type
			cur_piece[ "channel" ] = drum_kits[ i ][ j ].channel

			if cur_piece.type == e_drum_kit_piece_type.hihat then
				cur_piece[ "note" ][ 3 ] = drum_kits[ i ][ j ].note[ 3 ]
			end

			cur_piece[ "keybind" ] = drum_kits[ i ][ j ].keybind
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

local function AddKit()
	local new_kit = { name = "Custom kit" }

	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		local piece = {}
		piece.name = v.name
		piece.type = v.type
		piece.channel = v.channel
		piece.note = v.note
		piece.keybind = v.keybind
		piece.collider = v.collider
		piece.collider_inner = v.collider_inner
		local x, y, z, sx, sy, sz, angle, ax, ay, az = v.pose:unpack()
		piece.pose = lovr.math.newMat4( vec3( x, y, z ), vec3( sx, sy, sz ), quat( angle, ax, ay, az ) )
		table.insert( new_kit, piece )
	end
	table.insert( drum_kits, new_kit )
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

	local changed, idx = UI.ListBox( "kits", 9, 27, dkits, 1 )
	if changed then
		cur_drum_kit_index = idx
		cur_piece_index = 1
		SetupDrumColliders()
	end
	UI.SameLine()
	if UI.Button( "Add kit", 300 ) then
		AddKit()
	end
	UI.SameColumn()
	if UI.Button( "Delete kit", 300 ) then
		if #drum_kits > 1 then
			for i = #drum_kits[ cur_drum_kit_index ], 1, -1 do
				drum_kits[ cur_drum_kit_index ][ i ].collider:destroy()
				drum_kits[ cur_drum_kit_index ][ i ].collider_inner:destroy()
				table.remove( drum_kits[ cur_drum_kit_index ], i )
			end

			drum_kits[ cur_drum_kit_index ].name = nil
			table.remove( drum_kits, cur_drum_kit_index )
			cur_drum_kit_index = 1
			SetupDrumColliders()
			return
		end
	end
	UI.SameColumn()
	if UI.Button( "Rename kit", 300 ) then
		rename_kit_window_open = true
	end

	UI.SameColumn()
	if UI.Button( "Save all", 300 ) then
		SaveKits()
	end

	UI.Label( "Pieces", true )
	local pieces = {}
	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		table.insert( pieces, v.name )
	end
	local changed, cur_piece_index = UI.ListBox( "pieces", 12, 27, pieces, 1 )
	UI.SameLine()
	if UI.Button( "Add piece", 300 ) then
		add_piece_window_open = true
	end
	UI.SameColumn()
	if UI.Button( "Delete piece", 300 ) then
		if #drum_kits[ cur_drum_kit_index ] > 1 then -- prevent deleting last piece
			drum_kits[ cur_drum_kit_index ][ cur_piece_index ].collider:destroy()
			table.remove( drum_kits[ cur_drum_kit_index ], cur_piece_index )
			return
		end
	end

	if UI.Button( "-" ) then
		if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 1 ] > 0 then
			drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 1 ] = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 1 ] - 1
		end
	end

	UI.SameLine()

	if UI.Button( "+" ) then
		if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 1 ] < 127 then
			drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 1 ] = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 1 ] + 1
		end
	end

	UI.SameLine()
	local changed
	changed, drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 1 ] = UI.SliderInt( "Note inner", drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 1 ], 0, 127 )


	if UI.Button( "-" ) then
		if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 2 ] > 0 then
			drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 2 ] = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 2 ] - 1
		end
	end

	UI.SameLine()

	if UI.Button( "+" ) then
		if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 2 ] < 127 then
			drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 2 ] = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 2 ] + 1
		end
	end

	UI.SameLine()
	local changed
	changed, drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 2 ] = UI.SliderInt( "Note outer", drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 2 ], 0, 127 )

	-- hihat has 1 additional note (pedal down)
	local selected_piece_type = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].type
	if selected_piece_type == e_drum_kit_piece_type.hihat then
		if UI.Button( "-" ) then
			if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 3 ] > 0 then
				drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 3 ] = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 3 ] - 1
			end
		end

		UI.SameLine()

		if UI.Button( "+" ) then
			if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 3 ] < 127 then
				drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 3 ] = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 3 ] + 1
			end
		end

		UI.SameLine()
		local changed
		changed, drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 3 ] = UI.SliderInt( "Note pedal down", drum_kits[ cur_drum_kit_index ][ cur_piece_index ].note[ 3 ], 0, 127 )
	end

	local cur_piece_channel = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].channel
	if UI.Button( "-" ) and cur_piece_channel > 0 then
		drum_kits[ cur_drum_kit_index ][ cur_piece_index ].channel = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].channel - 1
	end
	UI.SameLine()
	if UI.Button( "+" ) and cur_piece_channel < 15 then
		drum_kits[ cur_drum_kit_index ][ cur_piece_index ].channel = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].channel + 1
	end
	UI.SameLine()
	local changed
	changed, drum_kits[ cur_drum_kit_index ][ cur_piece_index ].channel = UI.SliderInt( "MIDI Channel", drum_kits[ cur_drum_kit_index ][ cur_piece_index ].channel, 0, 15 )

	local cur_bind = "-- none --"
	if drum_kits[ cur_drum_kit_index ][ cur_piece_index ].keybind ~= "" then
		cur_bind = drum_kits[ cur_drum_kit_index ][ cur_piece_index ].keybind
	end

	if UI.Button( "Assign key..." ) then
		keybind_window_open = true
	end
	UI.SameLine()
	UI.Label( "Current Keybind: " .. cur_bind )

	UI.Dummy( 0, 20 )
	UI.Separator()
	UI.Dummy( 0, 20 )

	if UI.CheckBox( "Show colliders", show_colliders ) then show_colliders = not show_colliders end
	if UI.CheckBox( "Enable haptics", enable_haptics ) then enable_haptics = not enable_haptics end
	if UI.CheckBox( "Enable hit highlight", enable_hit_highlight ) then enable_hit_highlight = not enable_hit_highlight end

	local released
	released, sticks.pivot_offset = UI.SliderFloat( "Stick pivot", sticks.pivot_offset, 0, 0.3 )
	released, sticks.length = UI.SliderFloat( "Stick length", sticks.length, 0.381, 0.4445 )
	if released then
		sticks.left_collider:destroy()
		sticks.right_collider:destroy()
		sticks.left_collider = world:newCylinderCollider( 0, 0, 0, 0.01, sticks.length )
		sticks.left_collider:setKinematic( true )
		sticks.left_collider:setTag( "stickL" )
		sticks.right_collider = world:newCylinderCollider( 0, 0, 0, 0.01, sticks.length )
		sticks.right_collider:setKinematic( true )
		sticks.right_collider:setTag( "stickR" )
	end
	released, sticks.rotation = UI.SliderFloat( "Stick rotation", sticks.rotation, -1, 0.3 )
	UI.End( pass )

	-- add piece window
	if add_piece_window_open then
		local m = mat4( setup_window_pose )
		m:translate( 0, 0, 0.01 )
		UI.Begin( "add_piece_window", m, true )
		UI.Label( "Select piece" )

		local pcs = {}
		for i, v in ipairs( available_pieces ) do
			local str = available_pieces[ i ][ 1 ]
			table.insert( pcs, str )
		end

		local _, pc_idx = UI.ListBox( "availablepieceslst", 25, 27, pcs, 1 )
		if UI.Button( "OK" ) then
			local new_piece = {}
			new_piece.name = available_pieces[ pc_idx ][ 1 ]
			new_piece.type = available_pieces[ pc_idx ][ 4 ]
			new_piece.note = { 0, 0 }
			new_piece.channel = 0
			if new_piece.type == e_drum_kit_piece_type.hihat then
				new_piece.note[ 3 ] = 0
			end
			new_piece.keybind = ""
			local sy = available_pieces[ pc_idx ][ 3 ]
			if new_piece.type == e_drum_kit_piece_type.cymbal or new_piece.type == e_drum_kit_piece_type.hihat then
				sy = 0.5
			end
			new_piece.pose = lovr.math.newMat4( vec3( 0, 0.7, -0.6 ), vec3( available_pieces[ pc_idx ][ 2 ], sy, available_pieces[ pc_idx ][ 2 ] ), quat() )
			table.insert( drum_kits[ cur_drum_kit_index ], new_piece )
			SetupDrumColliders()
			add_piece_window_open = false
			UI.EndModalWindow()
		end
		UI.SameLine()
		if UI.Button( "Cancel" ) then
			add_piece_window_open = false
			UI.EndModalWindow()
		end
		UI.End( pass )
	end

	-- keybind window
	if keybind_window_open then
		local m = mat4( setup_window_pose )
		m:translate( 0, 0, 0.01 )
		UI.Begin( "keybind_window", m, true )
		UI.Label( "Press key to assign..." )

		local detected = ""
		if key_pressed then
			detected = key_pressed
		end
		UI.Label( "Key:" .. detected )
		if UI.Button( "OK" ) then
			if key_pressed then
				drum_kits[ cur_drum_kit_index ][ cur_piece_index ].keybind = key_pressed
			end
			keybind_window_open = false
			key_pressed = nil
			UI.EndModalWindow()
		end
		UI.SameLine()
		if UI.Button( "Cancel" ) then
			keybind_window_open = false
			key_pressed = nil
			UI.EndModalWindow()
		end
		UI.End( pass )
	end

	-- rename kit window
	if rename_kit_window_open then
		local m = mat4( setup_window_pose )
		m:translate( 0, 0, 0.01 )
		UI.Begin( "rename_kit_window", m, true )
		UI.Label( "Enter a new name for this kit" )

		local old_name = drum_kits[ cur_drum_kit_index ].name
		local got_focus, buffer_changed, id
		got_focus, buffer_changed, id, drum_kit_name = UI.TextBox( "kit name", 27, "" )

		if got_focus then
			UI.SetTextBoxText( id, old_name )
		end

		if UI.Button( "OK" ) then
			if drum_kit_name ~= "" then
				drum_kits[ cur_drum_kit_index ].name = drum_kit_name
			end
			rename_kit_window_open = false
			UI.EndModalWindow()
		end
		UI.SameLine()
		if UI.Button( "Cancel" ) then
			rename_kit_window_open = false
			UI.EndModalWindow()
		end
		UI.End( pass )
	else
		old_name = drum_kits[ cur_drum_kit_index ].name
	end

	ui_passes = UI.RenderFrame( pass )
end

local function UpdateNoteOffEvents()
	-- scheduled_off_notes fields: 1 = note, 2 = frame count, 3 = channel
	for i, v in ipairs( scheduled_off_notes ) do
		v[ 2 ] = v[ 2 ] + 1
	end

	for i = #scheduled_off_notes, 1, -1 do
		if scheduled_off_notes[ i ][ 2 ] > 15 then
			MIDI.noteOn( cur_MIDI_port, scheduled_off_notes[ i ][ 1 ], 0, scheduled_off_notes[ i ][ 3 ] )
			table.remove( scheduled_off_notes, i )
		end
	end
end

function lovr.keypressed( key, scancode, repeating )
	if keybind_window_open then
		if key then
			key_pressed = key
		end
	else
		local pieces = drum_kits[ cur_drum_kit_index ]
		for i, v in ipairs( pieces ) do
			if key == pieces[ i ].keybind then
				if drum_kits[ cur_drum_kit_index ][ i ].type ~= e_drum_kit_piece_type.hihat then
					MIDI.noteOn( cur_MIDI_port, drum_kits[ cur_drum_kit_index ][ i ].note[ 1 ], 127, drum_kits[ cur_drum_kit_index ][ i ].channel )
					table.insert( scheduled_off_notes, { drum_kits[ cur_drum_kit_index ][ i ].note[ 1 ], 0 } )
					break
				elseif not hihat_closed and drum_kits[ cur_drum_kit_index ][ i ].type == e_drum_kit_piece_type.hihat then
					hihat_open_value = 0
					MIDI.noteOn( cur_MIDI_port, drum_kits[ cur_drum_kit_index ][ i ].note[ 3 ], 127, drum_kits[ cur_drum_kit_index ][ i ].channel )
					MIDI.sendMessage( cur_MIDI_port, 176, 4, 127 )
					table.insert( scheduled_off_notes, { drum_kits[ cur_drum_kit_index ][ i ].note[ 3 ], 0 } )
					break
				end
			end
		end
	end
end

function lovr.keyreleased( key, scancode )
	if not keybind_window_open then
		local pieces = drum_kits[ cur_drum_kit_index ]
		for i, v in ipairs( pieces ) do
			if key == pieces[ i ].keybind then
				if drum_kits[ cur_drum_kit_index ][ i ].type == e_drum_kit_piece_type.hihat then
					hihat_open_value = 127
					MIDI.sendMessage( cur_MIDI_port, 176, 4, 0 )
				end
			end
		end
	end
end

function App.Init()
	lovr.filesystem.mount( lovr.filesystem.getExecutablePath():gsub( '[^/]+$', '/' ) )
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
	mdl_stick = lovr.graphics.newModel( "res/stick.glb" )
	mdl_cymbal = lovr.graphics.newModel( "res/cymbal.glb" )
	mdl_drum = lovr.graphics.newModel( "res/drum.glb" )
	mdl_room = lovr.graphics.newModel( "res/room.glb" )
	mdl_drum_highlight = lovr.graphics.newModel( "res/drum_highlight.glb" )
	mdl_cymbal_highlight = lovr.graphics.newModel( "res/cymbal_highlight.glb" )
	mdl_glass = lovr.graphics.newModel( "res/glass.glb" )
	mdl_sofa = lovr.graphics.newModel( "res/sofa.glb" )
	mdl_window = lovr.graphics.newModel( "res/window.glb" )
	mdl_plant = lovr.graphics.newModel( "res/plant.glb" )
	mdl_poster = lovr.graphics.newModel( "res/poster.glb" )
	mdl_light = lovr.graphics.newModel( "res/light.glb" )
	mdl_bookself = lovr.graphics.newModel( "res/bookself.glb" )
	mdl_table = lovr.graphics.newModel( "res/table.glb" )
	mdl_misc = lovr.graphics.newModel( "res/misc.glb" )
	mdl_books = lovr.graphics.newModel( "res/books.glb" )
	mdl_carpet = lovr.graphics.newModel( "res/carpet.glb" )
	mdl_handle = lovr.graphics.newModel( "res/handle.glb" )

	LoadKits()
	SetupDrumColliders()

	sticks.left_collider = world:newCylinderCollider( 0, 0, 0, 0.01, sticks.length )
	sticks.left_collider:setKinematic( true )
	sticks.left_collider:setTag( "stickL" )
	sticks.right_collider = world:newCylinderCollider( 0, 0, 0, 0.01, sticks.length )
	sticks.right_collider:setKinematic( true )
	sticks.right_collider:setTag( "stickR" )

	world:disableCollisionBetween( "stickL", "stickR" )
	world:disableCollisionBetween( "drums", "drums" )
	world:disableCollisionBetween( "drums_inner", "drums_inner" )
	world:disableCollisionBetween( "drums", "drums_inner" )
end

function App.Update( dt )
	-- MIDI in test

	-- local a, b, c = MIDI.getMessage( 1 )
	-- if a and b == 44 then
	-- 	hihat_open_value = MapRange( 127, 0, 0, 127, c )
	-- 	if hihat_open_value < 0 then hihat_open_value = 0 end
	-- 	if hihat_open_value > 127 then hihat_open_value = 127 end
	-- 	MIDI.sendMessage( cur_MIDI_port, 208, 36, c )
	-- end

	for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
		if drum_kits[ cur_drum_kit_index ][ i ].type == e_drum_kit_piece_type.hihat then
			hihat_keybind = drum_kits[ cur_drum_kit_index ][ i ].keybind
		end
	end
	if hihat_keybind and hihat_keybind ~= "" and lovr.system.isKeyDown( hihat_keybind ) then
		hihat_closed = true
	else
		hihat_closed = false
	end

	if lovr.headset.wasPressed( "hand/left", "y" ) then
		MIDI.sendMessage( cur_MIDI_port, 193, 1, 0 )
	end
	if lovr.headset.wasPressed( "hand/left", "x" ) then
		MIDI.sendMessage( cur_MIDI_port, 193, 90, 0 )
	end
	UpdateNoteOffEvents()
	UpdateSticksColliders()
	UpdateSticksVelocity()
	world:update( dt )
	world:computeOverlaps()

	if lovr.headset.isDown( "hand/right", "a" ) then
		mode = e_mode.move_piece
	end
	if lovr.headset.wasReleased( "hand/right", "a" ) then
		dragged_piece = nil
		mode = e_mode.play
	end

	if lovr.headset.isDown( "hand/right", "b" ) then
		mode = e_mode.move_kit
	end
	if lovr.headset.wasReleased( "hand/right", "b" ) then
		dragged_piece = nil
		mode = e_mode.play
	end

	if mode == e_mode.move_piece then
		if dragged_piece == nil then
			for shapeA, shapeB in world:overlaps() do
				local are_colliding = world:collide( shapeA, shapeB )
				if are_colliding then
					if shapeB:getCollider():getTag() == "drums" and shapeA:getCollider():getTag() == "stickR" and lovr.headset.wasPressed( "hand/right", "a" ) then
						dragged_piece = shapeB:getCollider():getUserData()
						drag_offset:set( mat4( lovr.headset.getPose( "hand/right" ) ):invert() * drum_kits[ cur_drum_kit_index ][ dragged_piece ].pose )
					end
					if shapeA:getCollider():getTag() == "drums" and shapeB:getCollider():getTag() == "stickR" and lovr.headset.wasPressed( "hand/right", "a" ) then
						dragged_piece = shapeA:getCollider():getUserData()
						drag_offset:set( mat4( lovr.headset.getPose( "hand/right" ) ):invert() * drum_kits[ cur_drum_kit_index ][ dragged_piece ].pose )
					end
				end
			end
		end

		if dragged_piece ~= nil then
			drum_kits[ cur_drum_kit_index ][ dragged_piece ].pose:set( mat4( lovr.headset.getPose( "hand/right" ) ) * drag_offset )
			drum_kits[ cur_drum_kit_index ][ dragged_piece ].collider:setPose( vec3( drum_kits[ cur_drum_kit_index ][ dragged_piece ].pose ),
				quat( drum_kits[ cur_drum_kit_index ][ dragged_piece ].pose ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )
			drum_kits[ cur_drum_kit_index ][ dragged_piece ].collider_inner:setPose( vec3( drum_kits[ cur_drum_kit_index ][ dragged_piece ].pose ),
				quat( drum_kits[ cur_drum_kit_index ][ dragged_piece ].pose ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )
		end
	end

	if mode == e_mode.move_kit then
		if dragged_piece == nil then
			for shapeA, shapeB in world:overlaps() do
				local are_colliding = world:collide( shapeA, shapeB )
				if are_colliding then
					if shapeB:getCollider():getTag() == "drums" and shapeA:getCollider():getTag() == "stickR" and lovr.headset.wasPressed( "hand/right", "b" ) then
						dragged_piece = shapeB:getCollider():getUserData()
						drag_table = {}
						for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
							local m = lovr.math.newMat4()
							m:set( mat4( lovr.headset.getPose( "hand/right" ) ):invert() * drum_kits[ cur_drum_kit_index ][ i ].pose )
							table.insert( drag_table, m )
						end
					end
					if shapeA:getCollider():getTag() == "drums" and shapeB:getCollider():getTag() == "stickR" and lovr.headset.wasPressed( "hand/right", "b" ) then
						dragged_piece = shapeA:getCollider():getUserData()
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

		if dragged_piece ~= nil then
			for i, v in ipairs( drum_kits[ cur_drum_kit_index ] ) do
				drum_kits[ cur_drum_kit_index ][ i ].pose:set( mat4( lovr.headset.getPose( "hand/right" ) ) * drag_table[ i ] )
				drum_kits[ cur_drum_kit_index ][ i ].collider:setPose( vec3( drum_kits[ cur_drum_kit_index ][ i ].pose ),
					quat( drum_kits[ cur_drum_kit_index ][ i ].pose ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )
				drum_kits[ cur_drum_kit_index ][ i ].collider_inner:setPose( vec3( drum_kits[ cur_drum_kit_index ][ i ].pose ),
					quat( drum_kits[ cur_drum_kit_index ][ i ].pose ):mul( quat( math.pi / 2, 1, 0, 0 ) ) )
			end
		end
	end

	if mode == e_mode.play then
		local L_col_this_frame = false
		local R_col_this_frame = false
		local L_inner_col_this_frame = false
		local R_inner_col_this_frame = false

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

		-- 2nd overlap test
		world:computeOverlaps()
		for shapeA, shapeB in world:overlaps() do
			local are_colliding = world:collide( shapeA, shapeB )
			if are_colliding then
				if sticks.left_colliding_drum ~= nil then
					if shapeA:getCollider():getTag() == "drums_inner" and shapeB:getCollider():getTag() == "stickL" then
						L_inner_col_this_frame = true
					end
					if shapeB:getCollider():getTag() == "drums_inner" and shapeA:getCollider():getTag() == "stickL" then
						L_inner_col_this_frame = true
					end
				end
				if sticks.right_colliding_drum ~= nil then
					if shapeA:getCollider():getTag() == "drums_inner" and shapeB:getCollider():getTag() == "stickR" then
						R_inner_col_this_frame = true
					end
					if shapeB:getCollider():getTag() == "drums_inner" and shapeA:getCollider():getTag() == "stickR" then
						R_inner_col_this_frame = true
					end
				end
			end
		end

		if sticks.left_colliding_drum ~= nil then
			if sticks.left_colliding_drum_prev == nil or sticks.left_colliding_drum_prev ~= sticks.left_colliding_drum then
				local triggered_note = drum_kits[ cur_drum_kit_index ][ sticks.left_colliding_drum ].note[ 2 ]
				if L_inner_col_this_frame then triggered_note = drum_kits[ cur_drum_kit_index ][ sticks.left_colliding_drum ].note[ 1 ] end
				MIDI.noteOn( cur_MIDI_port, triggered_note, sticks.left_vel, drum_kits[ cur_drum_kit_index ][ sticks.left_colliding_drum ].channel )

				table.insert( scheduled_off_notes, { triggered_note, 0, drum_kits[ cur_drum_kit_index ][ sticks.left_colliding_drum ].channel } )
				if enable_haptics then
					local strength = MapRange( 0, 127, 0, 1, sticks.left_vel )
					lovr.headset.vibrate( "hand/left", strength, 0.1 )
				end
				sticks.left_colliding_drum_prev = sticks.left_colliding_drum
				event_info.note = triggered_note
				if sticks.left_vel > 0 then event_info.velocity = sticks.left_vel end
			end
		end

		if sticks.right_colliding_drum ~= nil then
			if sticks.right_colliding_drum_prev == nil or sticks.right_colliding_drum_prev ~= sticks.right_colliding_drum then
				local triggered_note = drum_kits[ cur_drum_kit_index ][ sticks.right_colliding_drum ].note[ 2 ]
				if R_inner_col_this_frame then triggered_note = drum_kits[ cur_drum_kit_index ][ sticks.right_colliding_drum ].note[ 1 ] end

				MIDI.noteOn( cur_MIDI_port, triggered_note, sticks.right_vel, drum_kits[ cur_drum_kit_index ][ sticks.right_colliding_drum ].channel )
				table.insert( scheduled_off_notes, { triggered_note, 0, drum_kits[ cur_drum_kit_index ][ sticks.right_colliding_drum ].channel } )
				if enable_haptics then
					local strength = MapRange( 0, 127, 0, 1, sticks.right_vel )
					lovr.headset.vibrate( "hand/right", strength, 0.1 )
				end
				sticks.right_colliding_drum_prev = sticks.right_colliding_drum
				event_info.note = triggered_note
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
	pass:rotate( 3.07, 0, 1, 0 )
	SetEnvironment( pass )
	ShaderOn( pass )
	pass:origin()
	DrawDrumKit( pass )
	DrawSticks( pass )
	pass:draw( mdl_room )
	pass:draw( mdl_sofa )
	pass:draw( mdl_window )
	pass:draw( mdl_plant )
	pass:draw( mdl_poster )
	pass:draw( mdl_light )
	pass:draw( mdl_bookself )
	pass:draw( mdl_table )
	pass:draw( mdl_misc )
	pass:draw( mdl_books )
	pass:draw( mdl_carpet )
	pass:draw( mdl_handle )

	pass:draw( mdl_glass )

	ShaderOff( pass )
	Phywire.render_shapes.show_contacts = true
	if show_colliders then Phywire.draw( pass, world, Phywire.render_shapes ) end
end

return App
