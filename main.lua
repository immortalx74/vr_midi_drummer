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
