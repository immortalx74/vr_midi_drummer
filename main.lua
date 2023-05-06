App = require "app"

function lovr.load()
	-- cube = lovr.graphics.newTexture( {
	-- 	left = 'negx.png',
	-- 	right = 'posx.png',
	-- 	top = 'posy.png',
	-- 	bottom = 'negy.png',
	-- 	front = 'negz.png',
	-- 	back = 'posz.png'
	-- } )
	cube = lovr.graphics.newTexture("skybox1.png")
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
