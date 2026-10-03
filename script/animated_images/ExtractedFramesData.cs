using Godot;

[GlobalClass]
public partial class ExtractedFramesData : RefCounted
{
	[Export] public Image[] Images { get; set; }
	[Export] public float[] Durations { get; set; }

	[Export] public Rect2I UnionRect { get; set; }
}
