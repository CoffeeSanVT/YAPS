using Godot;
using System.Collections.Generic;

internal sealed class FrameBatch
{
	public List<Image> Frames = new();
	public List<float> Durations = new();
	public int Count => Frames.Count;
}
