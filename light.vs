vec4 lovrmain()
{
	return Projection * View * Transform * VertexPosition;
}