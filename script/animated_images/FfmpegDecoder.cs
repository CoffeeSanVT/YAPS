using Godot;
using FFMpegCore;
using FFMpegCore.Enums;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;

internal static class FfmpegDecoder
{
	private const string FrameFilePattern = "frame_%05d.webp";
	// Lossy VP8 at high quality: visually indistinguishable for sticker-sized
	// playback but orders of magnitude faster to encode than lossless VP8L
	// (which cost ~10min on 256 full-res frames).
	private const string CodecArgs = "-lossless 0 -q:v 90 -pix_fmt yuva420p";
	private const float MaxFrameDuration = 5.0f;
	private const float FallbackFrameDuration = 0.1f;

	private static readonly object _cancelLock = new();
	private static readonly Dictionary<string, List<CancellationTokenSource>> _cancelScopes = new();

	private static readonly Regex ShowInfoRegex = new(
		@"n:\s*\d+\s+pts:\s*\d+\s+pts_time:\S+(?:\s+duration:\s*\d+\s+duration_time:(\S+))?",
		RegexOptions.Compiled);

	internal static Image DecodeFirstFrame(string filePath, CancellationToken token, int maxWidth = 0, int maxHeight = 0)
	{
		string tempDir = CreateTempDirectory();
		try
		{
			if (!DumpFrames(filePath, Path.Combine(tempDir, FrameFilePattern), 1, null, token, maxWidth, maxHeight))
			{
				GD.PushError($"{AnimatedImageRuntime.Tag}ffmpeg decoding failed: {filePath}");
				return null;
			}

			string frame = Directory.EnumerateFiles(tempDir, "frame_*.webp")
				.OrderBy(f => f, StringComparer.Ordinal)
				.FirstOrDefault();
			return frame == null ? null : Image.LoadFromFile(frame);
		}
		finally
		{
			TryDeleteDirectory(tempDir);
		}
	}

	internal static ExtractedFrameFilesData ExtractFramesToFolder(string filePath, string destFolder, string fileBase, int maxFrames, CancellationToken token, int maxWidth = 0, int maxHeight = 0)
	{
		List<float> durations = new();
		if (!DumpFrames(filePath, Path.Combine(destFolder, $"{fileBase}_%03d.webp"), maxFrames, durations, token, maxWidth, maxHeight))
		{
			if (!token.IsCancellationRequested)
				GD.PushError($"{AnimatedImageRuntime.Tag}ffmpeg frame extraction failed: {filePath}");
			return null;
		}

		string[] files = [.. Directory.GetFiles(destFolder, $"{fileBase}_*.webp")
			.OrderBy(f => f, StringComparer.Ordinal)
			.Take(durations.Count)];
		if (files.Length == 0)
		{
			GD.PushError($"{AnimatedImageRuntime.Tag}no frames written to: {destFolder}");
			return null;
		}

		return new ExtractedFrameFilesData
		{
			FileNames = [.. files.Select(Path.GetFileName)],
			Durations = [.. durations.Take(files.Length)]
		};
	}

	private static bool DumpFrames(string filePath, string outputPattern, int maxFrames, List<float> durations, CancellationToken token, int maxWidth, int maxHeight)
	{
		string decoderArgs = ResolveInputDecoderArgs(filePath);
		// Positive limits preserve aspect ratio and avoid upscaling normal inputs.
		// Two-pixel minimums and even dimensions keep tiny/extreme-aspect sources
		// compatible with yuva420p WebP output instead of producing zero sizes.
		string scaleFilter = string.Empty;
		if (maxWidth > 0 && maxHeight > 0)
		{
			string ratio = $"min(1,min({maxWidth}/iw,{maxHeight}/ih))";
			scaleFilter = $"scale=w='max(2,2*trunc(iw*{ratio}/2))':h='max(2,2*trunc(ih*{ratio}/2))'";
		}
		else if (maxWidth > 0)
			scaleFilter = $"scale='min({maxWidth},iw)':-2";
		string frameArgs;
		if (durations == null)
			frameArgs = scaleFilter.Length > 0 ? $"{CodecArgs} -vf {scaleFilter}" : CodecArgs;
		else
		{
			string filters = scaleFilter.Length > 0 ? $"{scaleFilter},showinfo" : "showinfo";
			frameArgs = $"{CodecArgs} -vf {filters} -fps_mode passthrough";
		}
		return FFMpegArguments
			.FromFileInput(filePath, false, options =>
			{
				if (decoderArgs.Length > 0)
					options.WithCustomArgument(decoderArgs);
			})
			.OutputToFile(outputPattern, true, options => options
				.DisableChannel(Channel.Audio)
				.WithFrameOutputCount(maxFrames)
				.WithVideoCodec("libwebp")
				.WithCustomArgument(frameArgs))
			.WithLogLevel(FFMpegLogLevel.Info)
			.NotifyOnError(line => CollectFrameDuration(line, durations))
			.CancellableThrough(token)
			.ProcessSynchronously(false);
	}

	private static string ResolveInputDecoderArgs(string filePath)
	{
		if (!filePath.EndsWith(".webm", StringComparison.OrdinalIgnoreCase))
			return string.Empty;
		return FindWebmCodecId(filePath) switch
		{
			"V_VP9" => "-c:v libvpx-vp9",
			"V_VP8" => "-c:v libvpx",
			_ => string.Empty
		};
	}

	private static string FindWebmCodecId(string filePath)
	{
		try
		{
			using FileStream stream = File.OpenRead(filePath);
			Span<byte> buffer = new byte[1 << 18];
			int read = stream.Read(buffer);
			string head = System.Text.Encoding.ASCII.GetString(buffer[..read]);
			if (head.Contains("V_VP9", StringComparison.Ordinal))
				return "V_VP9";
			if (head.Contains("V_VP8", StringComparison.Ordinal))
				return "V_VP8";
		}
		catch (Exception err)
		{
			GD.PushWarning($"{AnimatedImageRuntime.Tag}could not inspect webm codec id: {err.Message}");
		}
		return string.Empty;
	}

	private static void CollectFrameDuration(string line, List<float> durations)
	{
		if (durations == null)
			return;

		Match match = ShowInfoRegex.Match(line);

		if (!match.Success)
			return;

		float duration = FallbackFrameDuration;

		if (match.Groups[1].Success
			&& float.TryParse(match.Groups[1].Value, NumberStyles.Float, CultureInfo.InvariantCulture, out float parsed)
			&& parsed > 0.0f && parsed < MaxFrameDuration)
			duration = parsed;

		durations.Add(duration);
	}

	private static string CreateTempDirectory()
	{
		string dir = Path.Combine(Path.GetTempPath(), "yaps_animated_" + Guid.NewGuid().ToString("N"));
		Directory.CreateDirectory(dir);

		return dir;
	}

	private static void TryDeleteDirectory(string path)
	{
		try
		{
			Directory.Delete(path, true);
		}
		catch (Exception err)
		{
			GD.PushError($"{AnimatedImageRuntime.Tag}{err}");
		}
	}

	internal static CancellationTokenSource BeginCancelScope(string filePath)
	{
		var cts = new CancellationTokenSource();
		lock (_cancelLock)
		{
			if (!_cancelScopes.TryGetValue(filePath, out var scopes))
				_cancelScopes[filePath] = scopes = new List<CancellationTokenSource>();
			scopes.Add(cts);
		}
		return cts;
	}

	internal static void EndCancelScope(string filePath, CancellationTokenSource cts)
	{
		lock (_cancelLock)
		{
			if (!_cancelScopes.TryGetValue(filePath, out var scopes))
				return;
			scopes.Remove(cts);
			if (scopes.Count == 0)
				_cancelScopes.Remove(filePath);
		}
	}

	internal static void CancelScope(string filePath)
	{
		if (string.IsNullOrEmpty(filePath))
			return;
		lock (_cancelLock)
		{
			if (!_cancelScopes.TryGetValue(filePath, out var scopes))
				return;
			foreach (CancellationTokenSource cts in scopes)
				cts.Cancel();
		}
	}

	internal static void CancelAllScopes()
	{
		lock (_cancelLock)
		{
			foreach (List<CancellationTokenSource> scopes in _cancelScopes.Values)
				foreach (CancellationTokenSource cts in scopes)
					cts.Cancel();
		}
	}
}
