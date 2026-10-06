using Godot;

[GlobalClass]
public partial class AnimatedImagePlayer : Node
{
	[Export] public TextureRect Target { get; set; }
	[Export] public AnimatedImageData Data { get; set; }
	[Export] public bool Loop { get; set; } = true;

	public int CurrentFrame => _index;
	public int FrameCount => Data?.FramePaths?.Length ?? Data?.Frames?.Length ?? 0;
	public bool IsPlaying => _playing;

	[Signal] public delegate void FrameChangedEventHandler(int frame);
	[Signal] public delegate void FrameNeededEventHandler(int frame);

	private int _index;
	private float _time;
	private bool _playing = true;

	public override void _Process(double delta)
	{
		if (!_playing || !IsInstanceValid(Target) || !HasData())
			return;

		float duration = Data.Durations != null && _index < Data.Durations.Length ? Data.Durations[_index] : 0.1f;
		_time += (float)delta;

		if (_time < duration)
			return;

		_time -= duration;

		if (_index + 1 >= FrameCount)
		{
			if (!Loop)
			{
				_playing = false;
				return;
			}
			_index = 0;
		}
		else
			_index++;

		ShowCurrentFrame();
	}

    public void Play() => _playing = true;

    public void Pause() => _playing = false;

    public void Stop()
	{
		_playing = false;
		_index = 0;
		_time = 0f;

		if (!HasData())
			return;

		Texture2D texture = FrameAt(0);
		if (IsInstanceValid(Target) && texture != null)
			Target.Texture = texture;
		EmitSignal(SignalName.FrameChanged, 0);
		if (texture == null)
			EmitSignal(SignalName.FrameNeeded, 0);
	}

	public void Seek(int frame)
	{
		if (!HasData())
			return;

		_index = Mathf.Clamp(frame, 0, FrameCount - 1);
		_time = 0f;

		Texture2D texture = FrameAt(_index);
		if (IsInstanceValid(Target) && texture != null)
			Target.Texture = texture;
		EmitSignal(SignalName.FrameChanged, _index);
		if (texture == null)
			EmitSignal(SignalName.FrameNeeded, _index);
	}

	private bool HasData()
		=> Data != null && FrameCount > 0;

	private Texture2D FrameAt(int index)
		=> Data?.Frames != null && index >= 0 && index < Data.Frames.Length ? Data.Frames[index] : null;

	private void ShowCurrentFrame()
	{
		Texture2D texture = FrameAt(_index);
		if (texture == null)
		{
			_time = 0f;
			EmitSignal(SignalName.FrameNeeded, _index);
			return;
		}

		Target.Texture = texture;
		EmitSignal(SignalName.FrameChanged, _index);
	}
}