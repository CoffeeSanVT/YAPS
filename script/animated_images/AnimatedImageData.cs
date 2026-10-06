using Godot;

[GlobalClass]
public partial class AnimatedImageData : RefCounted
{
	[Export] public Texture2D[] Frames { get; set; }
	[Export] public string[] FramePaths { get; set; }
	[Export] public float[] Durations { get; set; }

	[Export] public Rect2I UnionRect { get; set; }

	public void SetFrameTexture(int index, Texture2D texture)
	{
		if (Frames == null || index < 0 || index >= Frames.Length)
			return;
		Frames[index] = texture;
	}
}