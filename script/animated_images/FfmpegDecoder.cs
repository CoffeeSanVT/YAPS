using Godot;
using FFMpegCore;
using FFMpegCore.Enums;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;

internal static class FfmpegDecoder
{
	private const string FrameFilePattern = "frame_%05d.webp";
	private const string CodecArgs = "-lossless 1 -pix_fmt yuva420p";
	private const float MaxFrameDuration = 5.0f;
	private const float FallbackFrameDuration = 0.1f;

	private static readonly Regex ShowInfoRegex = new(
		@"n:\s*\d+\s+pts:\s*\d+\s+pts_time:\S+(?:\s+duration:\s*\d+\s+duration_time:(\S+))?",
		RegexOptions.Compiled);

	internal static Image DecodeFirstFrame(string filePath)
	{
		string tempDir = CreateTempDirectory();
		try
		{
			if (!DumpFrames(filePath, Path.Combine(tempDir, FrameFilePattern), 1, null))
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

	internal static ExtractedFrameFilesData ExtractFramesToFolder(string filePath, string destFolder, string fileBase, int maxFrames)
	{
		List<float> durations = new();
		if (!DumpFrames(filePath, Path.Combine(destFolder, $"{fileBase}_%03d.webp"), maxFrames, durations))
		{
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

	private static bool DumpFrames(string filePath, string outputPattern, int maxFrames, List<float> durations)
	{
		string decoderArgs = ResolveInputDecoderArgs(filePath);
		string frameArgs = durations == null
			? CodecArgs
			: $"{CodecArgs} -vf showinfo -fps_mode passthrough";
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
}
