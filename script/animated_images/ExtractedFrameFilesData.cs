using Godot;

[GlobalClass]
public partial class ExtractedFrameFilesData : RefCounted
{
	[Export] public string[] FileNames { get; set; }
	[Export] public float[] Durations { get; set; }
}