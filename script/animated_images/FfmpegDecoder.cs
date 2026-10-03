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
	private const float MaxFrameDuration = 5.0f;
	private const float FallbackFrameDuration = 0.1f;

	private static readonly Regex ShowInfoRegex = new(
		@"n:\s*\d+\s+pts:\s*\d+\s+pts_time:\S+(?:\s+duration:\s*\d+\s+duration_time:(\S+))?",
		RegexOptions.Compiled);

	internal static FrameBatch DecodeFile(string filePath, int maxFrames)
	{
		string tempDir = CreateTempDirectory();
		try
		{
			List<float> durations = new();
			if (!DumpFrames(filePath, Path.Combine(tempDir, FrameFilePattern), maxFrames, durations))
			{
				GD.PushError($"{AnimatedImageRuntime.Tag}ffmpeg decoding failed: {filePath}");
				return null;
			}
			return LoadFrameBatch(tempDir, durations);
		}
		finally
		{
			TryDeleteDirectory(tempDir);
		}
	}

	internal static Image DecodeFirstFrame(string filePath)
		=> DecodeFile(filePath, 1)?.Frames.FirstOrDefault();

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
		return FFMpegArguments
			.FromFileInput(filePath)
			.OutputToFile(outputPattern, true, options => options
				.DisableChannel(Channel.Audio)
				.WithFrameOutputCount(maxFrames)
				.WithVideoCodec("libwebp")
				.WithCustomArgument($"-vf showinfo -fps_mode passthrough"))
			.WithLogLevel(FFMpegLogLevel.Info)
			.NotifyOnError(line => CollectFrameDuration(line, durations))
			.ProcessSynchronously(false);
	}

	private static FrameBatch LoadFrameBatch(string tempDir, List<float> durations)
	{
		FrameBatch batch = new();
		foreach (string file in Directory.EnumerateFiles(tempDir, "frame_*.webp").OrderBy(f => f, StringComparer.Ordinal))
		{
			Image image = Image.LoadFromFile(file);

			if (image == null)
			{
				GD.PushWarning($"{AnimatedImageRuntime.Tag}failed to load frame image: {file}");
				continue;
			}

			batch.Frames.Add(image);
			batch.Durations.Add(GetDuration(batch.Count - 1, durations));
		}

		return batch;
	}

	private static void CollectFrameDuration(string line, List<float> durations)
	{
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

	private static float GetDuration(int index, List<float> durations)
		=> index < durations.Count ? durations[index] : FallbackFrameDuration;

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
