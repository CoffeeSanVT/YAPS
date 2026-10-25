using Godot;
using FFMpegCore;
using System;
using System.Threading;

[GlobalClass]
public partial class AnimatedImageRuntime : RefCounted
{
	internal const string Tag = "[AnimatedImage] ";
	internal const int MaxFrames = 256;

	private static readonly object _initLock = new();
	private static bool _initialized;

	private static void EnsureInitialized()
	{
		if (_initialized) return;
		lock (_initLock)
		{
			if (_initialized) return;
			GlobalFFOptions.Configure(options => options.BinaryFolder = ResolveBinaryFolder());
			_initialized = true;
		}
	}

	private static string ResolveBinaryFolder()
	{
		string exeName = OperatingSystem.IsWindows() ? "ffmpeg.exe" : "ffmpeg";
		string[] roots =
		{
			System.IO.Path.GetDirectoryName(typeof(AnimatedImageRuntime).Assembly.Location),
			AppDomain.CurrentDomain.BaseDirectory
		};
		foreach (string root in roots)
		{
			if (string.IsNullOrEmpty(root))
				continue;
			
			string candidate = System.IO.Path.Combine(root, "addons", "ffmpeg", "bin");

			if (System.IO.File.Exists(System.IO.Path.Combine(candidate, exeName))
				|| System.IO.File.Exists(System.IO.Path.Combine(candidate, "x64", exeName)))
				return candidate;
		}
		return string.Empty;
	}

	// NOTE: optional C# parameters are not optional when called from GDScript
	// (all arguments become required there), so every caller must pass maxWidth.
	public static Godot.Collections.Dictionary LoadFirstFrameData(string filePath, bool compressTextures, int maxWidth)
	{
		EnsureInitialized();
		return ToFirstFrameData(DecodeGuarded(filePath, token => FfmpegDecoder.DecodeFirstFrame(filePath, token, maxWidth)), compressTextures);
	}

	public static ExtractedFrameFilesData ExtractFrameFiles(string filePath, string destFolder, string fileBase, int maxWidth)
	{
		EnsureInitialized();
		return DecodeGuarded(filePath, token => FfmpegDecoder.ExtractFramesToFolder(filePath, destFolder, fileBase, MaxFrames, token, maxWidth));
	}

	/// <summary>
	/// Kills any running ffmpeg decode whose source file path matches.
	/// The path must match the one previously handed to ExtractFrameFiles.
	/// </summary>
	public static void CancelExtraction(string filePath)
	{
		FfmpegDecoder.CancelScope(filePath);
	}

	/// <summary>Used on app shutdown so no ffmpeg decode can block exiting.</summary>
	public static void CancelAllExtractions()
	{
		FfmpegDecoder.CancelAllScopes();
	}

	private static T DecodeGuarded<T>(string filePath, Func<CancellationToken, T> decode) where T : class
	{
		if (string.IsNullOrEmpty(filePath))
			return null;

		if (!System.IO.File.Exists(filePath))
		{
			GD.PushError($"{Tag}file not found: '{filePath}'");
			return null;
		}
		var cts = FfmpegDecoder.BeginCancelScope(filePath);
		try
		{
			return decode(cts.Token);
		}
		catch (Exception err)
		{
			if (cts.IsCancellationRequested)
			{
				GD.PushWarning($"{Tag}decoding cancelled: '{filePath}'");
				return null;
			}
			GD.PushError($"{Tag}exception decoding '{filePath}': {err.Message}\n{err.StackTrace}");
			return null;
		}
		finally
		{
			FfmpegDecoder.EndCancelScope(filePath, cts);
		}
	}

	public const int CompressSkipped = 0;
	public const int CompressDone = 1;
	public const int CompressFailed = 2;

	public static int CompressTexture(Image image)
	{
		if (image == null || image.IsEmpty() || image.IsCompressed())
			return CompressSkipped;
		if (image.GetWidth() % 4 != 0 || image.GetHeight() % 4 != 0)
			return CompressSkipped;
		if (image.GetFormat() != Image.Format.Rgba8)
			image.Convert(Image.Format.Rgba8);
		if (image.Compress(Image.CompressMode.Bptc, Image.CompressSource.Generic) != Error.Ok
			&& image.Compress(Image.CompressMode.S3Tc, Image.CompressSource.Generic) != Error.Ok)
		{
			GD.PushWarning($"{Tag}no VRAM compressor available in this build; keeping RGBA8");
			return CompressFailed;
		}
		return CompressDone;
	}

	private static Godot.Collections.Dictionary ToFirstFrameData(Image image, bool compressTextures)
	{
		if (image == null)
		{
			GD.PushWarning($"{Tag}no frames decoded for first frame data");
			return null;
		}

		Rect2I usedRect = image.GetUsedRect();
		if (compressTextures)
			CompressTexture(image);

		return new Godot.Collections.Dictionary
		{
			["texture"] = ImageTexture.CreateFromImage(image),
			["used_rect"] = usedRect
		};
	}

	public static AnimatedImagePlayer AttachPlayer(AnimatedImageData data, TextureRect target)
	{
		if (data == null || target == null)
		{
			GD.PushError("AttachPlayer: invalid arguments (data or target is null)");
			return null;
		}

		var player = new AnimatedImagePlayer
		{
			Name = "AnimatedImagePlayer",
			Target = target,
			Data = data
		};

		target.AddChild(player);
		
		return player;
	}
}