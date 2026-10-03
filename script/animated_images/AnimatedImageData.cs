using Godot;

[GlobalClass]
public partial class AnimatedImageData : RefCounted
{
	[Export] public Texture2D[] Frames { get; set; }
	[Export] public float[] Durations { get; set; }

	[Export] public Rect2I UnionRect { get; set; }
}
