using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

[GlobalClass]
public partial class RamUsage : Node
{
	private const uint PdhFmtLarge = 0x00000400;
	private const int PdhMoreData = unchecked((int)0x800007D2);
	private const int PdhStatusValidData = 0;
	private const int PdhStatusNewData = 1;
	private const int MaxArrayBufferBytes = 16777216;
	private const float BytesToMiB = 1f / 1048576f;
	private const ulong PollIntervalMs = 250;

	private IntPtr _query;
	private IntPtr _pidCounter;
	private IntPtr _wsCounter;
	private byte[] _buffer = new byte[262144];

	private float _lastGoodMib = -1f;
	private float _peakMib = -1f;
	private Godot.Vector2 _cached = new(-1f, -1f);
	private ulong _nextPollMs;

	public override void _ExitTree() => CloseQuery();

	public Godot.Vector2 GetRamUsageMiB()
	{
		ulong now = Time.GetTicksMsec();
		if (now < _nextPollMs)
			return _cached;
		_nextPollMs = now + PollIntervalMs;
		_cached = Collect();
		return _cached;
	}

	private Godot.Vector2 Collect()
	{
		if (_query == IntPtr.Zero && !OpenQuery())
			return _cached;
		if (PdhCollectQueryData(_query) != 0)
			return _cached;
		Dictionary<string, long> pids = ReadLargeArray(_pidCounter);
		Dictionary<string, long> workingSets = ReadLargeArray(_wsCounter);
		if (pids == null || workingSets == null)
			return _cached;
		int processId = System.Environment.ProcessId;
		foreach (KeyValuePair<string, long> entry in workingSets)
		{
			if (pids.TryGetValue(entry.Key, out long instancePid) && instancePid == processId)
			{
				_lastGoodMib = entry.Value * BytesToMiB;
				if (_lastGoodMib > _peakMib)
					_peakMib = _lastGoodMib;
				return new Godot.Vector2(_lastGoodMib, _peakMib);
			}
		}
		return _cached;
	}

	private bool OpenQuery()
	{
		CloseQuery();
		if (PdhOpenQueryW(null, IntPtr.Zero, out _query) != 0 || _query == IntPtr.Zero)
		{
			_query = IntPtr.Zero;
			return false;
		}
		_pidCounter = AddCounter("\\Process(*)\\ID Process");
		_wsCounter = AddCounter("\\Process(*)\\Working Set - Private");
		if (_pidCounter == IntPtr.Zero || _wsCounter == IntPtr.Zero)
		{
			CloseQuery();
			return false;
		}
		return true;
	}

	private void CloseQuery()
	{
		_pidCounter = IntPtr.Zero;
		_wsCounter = IntPtr.Zero;
		if (_query != IntPtr.Zero)
		{
			PdhCloseQuery(_query);
			_query = IntPtr.Zero;
		}
	}

	private IntPtr AddCounter(string counterPath)
	{
		if (PdhAddEnglishCounterW(_query, counterPath, IntPtr.Zero, out IntPtr counter) != 0)
			return IntPtr.Zero;
		return counter;
	}

	private Dictionary<string, long> ReadLargeArray(IntPtr counter)
	{
		for (int attempt = 0; attempt < 2; attempt++)
		{
			GCHandle handle = GCHandle.Alloc(_buffer, GCHandleType.Pinned);
			int result;
			uint itemCount = 0;
			IntPtr bufferPtr = handle.AddrOfPinnedObject();
			try
			{
				uint bufferSize = (uint)_buffer.Length;
				result = PdhGetFormattedCounterArrayW(counter, PdhFmtLarge, ref bufferSize, out itemCount, bufferPtr);
				if (result == PdhMoreData)
				{
					if (!GrowBuffer((int)bufferSize))
						return null;
					continue;
				}
				if (result == 0)
					return ParseLargeArray(bufferPtr, itemCount);
				return null;
			}
			finally
			{
				handle.Free();
			}
		}
		return null;
	}

	private Dictionary<string, long> ParseLargeArray(IntPtr bufferPtr, uint itemCount)
	{
		int itemSize = Marshal.SizeOf<PdhFmtCounterValueItem>();
		Dictionary<string, long> values = new((int)itemCount);
		for (uint i = 0; i < itemCount; i++)
		{
			PdhFmtCounterValueItem value = Marshal.PtrToStructure<PdhFmtCounterValueItem>(IntPtr.Add(bufferPtr, (int)(i * itemSize)));
			if (value.FmtValue.CStatus != PdhStatusValidData && value.FmtValue.CStatus != PdhStatusNewData)
				continue;
			string name = Marshal.PtrToStringUni(value.Name);
			if (name == null)
				continue;
			values[name] = value.FmtValue.LongValue;
		}
		return values;
	}

	private bool GrowBuffer(int requiredSize)
	{
		int newSize = Math.Max(requiredSize + 4096, _buffer.Length * 2);
		if (newSize > MaxArrayBufferBytes)
			return false;
		_buffer = new byte[newSize];
		return true;
	}

	[StructLayout(LayoutKind.Explicit)]
	private struct PdhFmtCounterValue
	{
		[FieldOffset(0)] public uint CStatus;
		[FieldOffset(8)] public long LongValue;
	}

	[StructLayout(LayoutKind.Sequential)]
	private struct PdhFmtCounterValueItem
	{
		public IntPtr Name;
		public PdhFmtCounterValue FmtValue;
	}

	[DllImport("pdh.dll", CharSet = CharSet.Unicode)]
	private static extern int PdhOpenQueryW(string dataSource, IntPtr userData, out IntPtr query);

	[DllImport("pdh.dll", CharSet = CharSet.Unicode)]
	private static extern int PdhAddEnglishCounterW(IntPtr query, string counterPath, IntPtr userData, out IntPtr counter);

	[DllImport("pdh.dll")]
	private static extern int PdhCollectQueryData(IntPtr query);

	[DllImport("pdh.dll")]
	private static extern int PdhCloseQuery(IntPtr query);

	[DllImport("pdh.dll", CharSet = CharSet.Unicode)]
	private static extern int PdhGetFormattedCounterArrayW(IntPtr counter, uint format, ref uint bufferSize, out uint itemCount, IntPtr itemBuffer);
}
