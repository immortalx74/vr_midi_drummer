App = require "app"

function lovr.load()
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
