using Godot;
using FFMpegCore;
using System;

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

	public static AnimatedImageData LoadFrames(string filePath, bool compressTextures = false)
	{
		EnsureInitialized();
		return ToAnimatedImageData(DecodeGuarded(filePath, () => FfmpegDecoder.DecodeFile(filePath, MaxFrames)), compressTextures);
	}

	public static Godot.Collections.Dictionary LoadFirstFrameData(string filePath, bool compressTextures = false)
	{
		EnsureInitialized();
		return ToFirstFrameData(DecodeGuarded(filePath, () => FfmpegDecoder.DecodeFirstFrame(filePath)), compressTextures);
	}

	public static ExtractedFramesData ExtractFrameImages(string filePath)
	{
		EnsureInitialized();
		return ToExtractedFrames(DecodeGuarded(filePath, () => FfmpegDecoder.DecodeFile(filePath, MaxFrames)));
	}

	public static ExtractedFrameFilesData ExtractFrameFiles(string filePath, string destFolder, string fileBase)
	{
		EnsureInitialized();
		return DecodeGuarded(filePath, () => FfmpegDecoder.ExtractFramesToFolder(filePath, destFolder, fileBase, MaxFrames));
	}

	private static T DecodeGuarded<T>(string filePath, Func<T> decode) where T : class
	{
		if (string.IsNullOrEmpty(filePath))
			return null;

		if (!System.IO.File.Exists(filePath))
		{
			GD.PushError($"{Tag}file not found: '{filePath}'");
			return null;
		}
		try
		{
			return decode();
		}
		catch (Exception err)
		{
			GD.PushError($"{Tag}exception decoding '{filePath}': {err.Message}\n{err.StackTrace}");
			return null;
		}
	}

	private static AnimatedImageData ToAnimatedImageData(FrameBatch batch, bool compressTextures)
	{
		if (batch == null || batch.Count <= 1)
			return null;

		var textures = new Texture2D[batch.Count];
		Rect2I union = UnionOfUsedRects(batch.Frames);

		for (int i = 0; i < batch.Count; i++)
		{
			Image image = batch.Frames[i];
			if (compressTextures)
				CompressTexture(image);
			textures[i] = ImageTexture.CreateFromImage(image);
		}

		return new AnimatedImageData
		{
			Frames = textures,
			Durations = batch.Durations.ToArray(),
			UnionRect = union
		};
	}

	public static bool EncodeBc(Image image)
	{
		if (image == null || image.IsEmpty() || image.IsCompressed())
			return false;
		if (image.GetWidth() % 4 != 0 || image.GetHeight() % 4 != 0)
			return false;
		if (image.GetFormat() != Image.Format.Rgba8)
			return false;

		int width = image.GetWidth();
		int height = image.GetHeight();
		byte[] src = image.GetData();

		bool hasAlpha = false;
		for (int i = 3; i < src.Length; i += 4)
		{
			if (src[i] != 255) { hasAlpha = true; break; }
		}

		int blocksX = width / 4;
		int blocksY = height / 4;
		int bytesPerBlock = hasAlpha ? 16 : 8;
		byte[] outData = new byte[blocksX * blocksY * bytesPerBlock];
		int[] pixelAlpha = new int[16];
		int[] alphaPalette = new int[8];

		for (int by = 0; by < blocksY; by++)
		{
			for (int bx = 0; bx < blocksX; bx++)
			{
				int o = (by * blocksX + bx) * bytesPerBlock;
				if (hasAlpha)
					EncodeAlphaBlock(src, bx, by, width, outData, o, pixelAlpha, alphaPalette);
				EncodeColorBlock(src, bx, by, width, outData, o + (hasAlpha ? 8 : 0));
			}
		}

		var format = hasAlpha ? Image.Format.Dxt5 : Image.Format.Dxt1;
		image.SetData(width, height, false, format, outData);
		return true;
	}

	private static void EncodeAlphaBlock(byte[] src, int bx, int by, int width, byte[] outData, int o, int[] pixelAlpha, int[] palette)
	{
		int min = 255, max = 0;
		for (int i = 0; i < 16; i++)
		{
			int p = ((by * 4 + (i >> 2)) * width + (bx * 4 + (i & 3))) * 4 + 3;
			int a = src[p];
			pixelAlpha[i] = a;
			if (a < min) min = a;
			if (a > max) max = a;
		}

		outData[o] = (byte)max;
		outData[o + 1] = (byte)min;
		if (min == max)
		{
			for (int k = 2; k < 8; k++)
				outData[o + k] = 0;
			return;
		}

		palette[0] = max;
		palette[1] = min;
		for (int i = 2; i < 8; i++)
			palette[i] = ((8 - i) * max + (i - 1) * min) / 7;

		ulong bits = 0;
		for (int i = 0; i < 16; i++)
		{
			int best = 0, bestDist = int.MaxValue;
			for (int p = 0; p < 8; p++)
			{
				int d = pixelAlpha[i] - palette[p];
				if (d < 0) d = -d;
				if (d < bestDist) { bestDist = d; best = p; }
			}
			bits |= (ulong)best << (i * 3);
		}
		for (int k = 0; k < 6; k++)
			outData[o + 2 + k] = (byte)(bits >> (k * 8));
	}

	private static void EncodeColorBlock(byte[] src, int bx, int by, int width, byte[] outData, int o)
	{
		int rmin = 255, rmax = 0, gmin = 255, gmax = 0, bmin = 255, bmax = 0;
		for (int i = 0; i < 16; i++)
		{
			int p = ((by * 4 + (i >> 2)) * width + (bx * 4 + (i & 3))) * 4;
			int r = src[p], g = src[p + 1], b = src[p + 2];
			if (r < rmin) rmin = r;
			if (r > rmax) rmax = r;
			if (g < gmin) gmin = g;
			if (g > gmax) gmax = g;
			if (b < bmin) bmin = b;
			if (b > bmax) bmax = b;
		}

		int rRange = rmax - rmin, gRange = gmax - gmin, bRange = bmax - bmin;
		rmin += rRange >> 4; rmax -= rRange >> 4;
		gmin += gRange >> 4; gmax -= gRange >> 4;
		bmin += bRange >> 4; bmax -= bRange >> 4;

		int c0 = To565(rmax, gmax, bmax);
		int c1 = To565(rmin, gmin, bmin);
		if (c0 < c1) { int tmp = c0; c0 = c1; c1 = tmp; }

		int r0 = Expand5((c0 >> 11) & 31), g0 = Expand6((c0 >> 5) & 63), b0 = Expand5(c0 & 31);
		int r1 = Expand5((c1 >> 11) & 31), g1 = Expand6((c1 >> 5) & 63), b1 = Expand5(c1 & 31);
		int r2 = (2 * r0 + r1) / 3, g2 = (2 * g0 + g1) / 3, b2 = (2 * b0 + b1) / 3;
		int r3 = (r0 + 2 * r1) / 3, g3 = (g0 + 2 * g1) / 3, b3 = (b0 + 2 * b1) / 3;

		outData[o] = (byte)c0;
		outData[o + 1] = (byte)(c0 >> 8);
		outData[o + 2] = (byte)c1;
		outData[o + 3] = (byte)(c1 >> 8);

		uint idx = 0;
		for (int y = 0; y < 4; y++)
		{
			for (int x = 0; x < 4; x++)
			{
				int p = ((by * 4 + y) * width + (bx * 4 + x)) * 4;
				int r = src[p], g = src[p + 1], b = src[p + 2];

				int best = 0, bestDist = Dist(r, g, b, r0, g0, b0);
				int d = Dist(r, g, b, r1, g1, b1);
				if (d < bestDist) { bestDist = d; best = 1; }
				d = Dist(r, g, b, r2, g2, b2);
				if (d < bestDist) { bestDist = d; best = 2; }
				d = Dist(r, g, b, r3, g3, b3);
				if (d < bestDist) { best = 3; }

				idx |= (uint)best << ((3 - y) * 8 + x * 2);
			}
		}

		outData[o + 4] = (byte)idx;
		outData[o + 5] = (byte)(idx >> 8);
		outData[o + 6] = (byte)(idx >> 16);
		outData[o + 7] = (byte)(idx >> 24);
	}

	private static int To565(int r, int g, int b)
		=> ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3);

	private static int Expand5(int v) => (v << 3) | (v >> 2);

	private static int Expand6(int v) => (v << 2) | (v >> 4);

	private static int Dist(int r, int g, int b, int pr, int pg, int pb)
	{
		int dr = r - pr, dg = g - pg, db = b - pb;
		return dr * dr + dg * dg + db * db;
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
			&& image.Compress(Image.CompressMode.S3Tc, Image.CompressSource.Generic) != Error.Ok
			&& !EncodeBc(image))
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

	private static ExtractedFramesData ToExtractedFrames(FrameBatch batch)
	{
		if (batch == null || batch.Count <= 1)
			return null;

		return new ExtractedFramesData
		{
			Images = batch.Frames.ToArray(),
			Durations = batch.Durations.ToArray(),
			UnionRect = UnionOfUsedRects(batch.Frames)
		};
	}

	private static Rect2I UnionOfUsedRects(System.Collections.Generic.IReadOnlyList<Image> images)
	{
		Rect2I union = new();
		bool any = false;

		foreach (Image image in images)
		{
			Rect2I rect = image.GetUsedRect();
			if (rect.Size.X <= 0 || rect.Size.Y <= 0)
				continue;
			union = any ? union.Merge(rect) : rect;
			any = true;
		}

		return any ? union : new Rect2I();
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