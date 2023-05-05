-- local midi = require "luamidi"
-- local phywire = require "phywire"
-- UI = require "ui/ui"

-- local vs = lovr.filesystem.read( "light.vs" )
-- local fs = lovr.filesystem.read( "light.fs" )
-- local shader = lovr.graphics.newShader( vs, fs )

-- local is_colliding = false


-- mdl_drum = lovr.graphics.newModel( "drum4.glb" )
-- mdl_cymbal = lovr.graphics.newModel( "cymbal2.glb" )
-- mdl_stick = lovr.graphics.newModel( "stick.glb" )

-- winpos = lovr.math.newMat4( -1, 1.3, -1.3 )
-- local hand_pose = lovr.math.newMat4()
-- local world = lovr.physics.newWorld()
-- local drum_collider = world:newCylinderCollider( 0, 1, -1, 0.38, 0.02 )
-- drum_collider:setOrientation( math.pi / 2, 1, 0, 0 )
-- drum_collider:setKinematic( true )
-- local drum_collider2 = world:newCylinderCollider( 0, 0.74, -1, 0.38, 0.5 )
-- drum_collider2:setOrientation( math.pi / 2, 1, 0, 0 )
-- drum_collider2:setKinematic( true )
-- local stick_collider = world:newCylinderCollider( 0, 0, 0, 0.01, 0.39 )

-- print( "Midi Output Ports: ", midi.getoutportcount() )
-- local outputdeveicename = midi.getOutPortName( 1 )
-- print( outputdeveicename )

-- function MapRange( from_min, from_max, to_min, to_max, v )
-- 	return (v - from_min) * (to_max - to_min) / (from_max - from_min) + to_min
-- end

-- function lovr.load()
-- 	UI.Init()
-- 	lovr.graphics.setBackgroundColor( 0.4, 0.4, 1 )
-- end

-- function lovr.update( dt )
-- 	world:update( dt )
-- 	UI.InputInfo()
-- 	hand_pose = mat4( vec3( lovr.headset.getPosition( "hand/right" ) ), vec3( 1, 1, 1 ), quat( lovr.headset.getOrientation( "hand/right" ) ) ):rotate( -0.35, 1, 0, 0 )
-- 	-- stick_collider:setPose( vec3( lovr.headset.getPosition( "hand/right" ) ), quat( lovr.headset.getOrientation( "hand/right" ) ) ):rotate( -1.9, 1, 0, 0 )
-- 	-- stick_collider:setPosition( vec3( lovr.headset.getPosition( "hand/right" ) ) )
-- 	-- stick_collider:setOrientation( quat( lovr.headset.getOrientation( "hand/right" ) ) )
-- 	local hp = mat4( hand_pose )
-- 	stick_collider:setPosition( vec3( hp:translate( 0, 0, -0.1 ) ) )
-- 	stick_collider:setOrientation( quat( hand_pose ) )


-- 	world:computeOverlaps()
-- 	for shapeA, shapeB in world:overlaps() do
-- 		local are_colliding = world:collide( shapeA, shapeB )

-- 		-- if are_colliding and shapeA:getCollider() == drum_collider and shapeB:getCollider() == stick_collider and (not is_colliding) then
-- 		-- 	midi.noteOn( 1, 38, 120, 1 )
-- 		-- 	is_colliding = true
-- 		-- elseif are_colliding and shapeA:getCollider() == drum_collider and shapeB:getCollider() == stick_collider and is_colliding then
-- 		-- 	is_colliding = true
-- 		-- end
-- 		if are_colliding and shapeA:getCollider() == drum_collider2 and shapeB:getCollider() == stick_collider then
-- 			-- print( "inside" )
-- 			if not is_colliding then
-- 				local x, y, z = lovr.headset.getVelocity( "hand/right" )
-- 				local mapped = MapRange( 0, 5, 50, 124, y * (-1) )
-- 				if mapped > 124 then mapped = 124 end
-- 				print( y, mapped )
-- 				midi.noteOn( 1, 38, mapped, 1 )
-- 				is_colliding = true
-- 			end
-- 		elseif not are_colliding and shapeA:getCollider() == drum_collider2 and shapeB:getCollider() == stick_collider then
-- 			-- print( "outside" )
-- 			is_colliding = false
-- 		end
-- 	end
-- end

-- function lovr.draw( pass )
-- 	pass:setColor( .1, .1, .12 )
-- 	pass:plane( 0, 0, 0, 25, 25, -math.pi / 2, 1, 0, 0 )
-- 	pass:setColor( .2, .2, .2 )
-- 	pass:plane( 0, 0, 0, 25, 25, -math.pi / 2, 1, 0, 0, 'line', 50, 50 )

-- 	UI.NewFrame( pass )

-- 	-- local lh_pose = lovr.math.newMat4( lovr.headset.getPose( "hand/left" ) )
-- 	-- lh_pose:rotate( -math.pi / 2, 1, 0, 0 )
-- 	UI.Begin( "FirstWindow", winpos )

-- 	UI.Label( "first window" )
-- 	if UI.Button( "MIDI" ) then
-- 		midi.noteOn( 1, 38, 120, 1 )
-- 	end
-- 	UI.End( pass )

-- 	local ui_passes = UI.RenderFrame( pass )

-- 	--------------------------------------------------------------------
-- 	pass:setShader( shader )

-- 	-- Set shader values
-- 	local lightPos = vec3( -3, 6.0, -1.0 )
-- 	pass:setColor( 1, 1, 1 )
-- 	-- pass:box( lightPos )
-- 	pass:send( 'ambience', { 0.05, 0.05, 0.05, 1.0 } )
-- 	pass:send( 'lightColor', { 1.0, 1.0, 1.0, 1.0 } )
-- 	pass:send( 'lightPos', lightPos )
-- 	pass:send( 'specularStrength', 0.5 )
-- 	pass:send( 'metallic', 32.0 )
-- 	local drum_pos = mat4( vec3( 0, 1, -2 ), vec3( 1, 1, 1 ), quat() )
-- 	pass:draw( mdl_stick, hand_pose )
-- 	pass:draw( mdl_cymbal, drum_pos )
-- 	phywire.draw( pass, world, phywire.render_shapes )
-- 	--------------------------------------------------------------------

-- 	table.insert( ui_passes, pass )
-- 	return lovr.graphics.submit( ui_passes )
-- end


App = require "app"

function lovr.load()
	cube = lovr.graphics.newTexture( {
		left = 'negx.jpg',
		right = 'posx.jpg',
		top = 'posy.jpg',
		bottom = 'negy.jpg',
		front = 'negz.jpg',
		back = 'posz.jpg'
	} )
	App.Init()
end

function lovr.update( dt )
	App.Update( dt )
end

function lovr.draw( pass )
	App.RenderFrame( pass )
	table.insert( ui_passes, pass )
	return lovr.graphics.submit( ui_passes )
end
