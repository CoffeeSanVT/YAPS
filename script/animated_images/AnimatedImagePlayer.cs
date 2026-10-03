using Godot;

[GlobalClass]
public partial class AnimatedImagePlayer : Node
{
	[Export] public TextureRect Target { get; set; }
	[Export] public AnimatedImageData Data { get; set; }
	[Export] public bool Loop { get; set; } = true;

	public int CurrentFrame => _index;
	public int FrameCount => Data?.Frames?.Length ?? 0;
	public bool IsPlaying => _playing;

	[Signal] public delegate void FrameChangedEventHandler(int frame);

	private int _index;
	private float _time;
	private bool _playing = true;

	public override void _Process(double delta)
	{
		if (!_playing || !IsInstanceValid(Target) || Data == null || Data.Frames == null || Data.Frames.Length == 0)
			return;

		float duration = _index < Data.Durations.Length ? Data.Durations[_index] : 0.1f;
		_time += (float)delta;

		if (_time < duration)
			return;

		_time -= duration;

		if (_index + 1 >= Data.Frames.Length)
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

		Target.Texture = Data.Frames[_index];

		EmitSignal(SignalName.FrameChanged, _index);
	}

    public void Play() => _playing = true;

    public void Pause() => _playing = false;

    public void Stop()
	{
		_playing = false;
		_index = 0;
		_time = 0f;

		if (IsInstanceValid(Target) && Data?.Frames?.Length > 0)
		{
			Target.Texture = Data.Frames[0];
			EmitSignal(SignalName.FrameChanged, 0);
		}
	}

	public void Seek(int frame)
	{
		if (Data?.Frames == null || Data.Frames.Length == 0)
			return;

		_index = Mathf.Clamp(frame, 0, Data.Frames.Length - 1);
		_time = 0f;

		if (IsInstanceValid(Target))
		{
			Target.Texture = Data.Frames[_index];
			EmitSignal(SignalName.FrameChanged, _index);
		}
	}
}
