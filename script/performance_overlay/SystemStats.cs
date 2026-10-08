using Godot;
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

[GlobalClass]
public partial class SystemStats : Node
{
	private const uint PdhFmtDouble = 0x00000200;
	private const uint PdhFmtLarge = 0x00000400;
	private const int PdhMoreData = unchecked((int)0x800007D2);
	private const int PdhStatusValidData = 0;
	private const int PdhStatusNewData = 1;
	private const int MaxArrayBufferBytes = 16777216;
	private const int CollectIntervalMs = 500;

	private Thread _thread;
	private volatile bool _running;

	private IntPtr _query;
	private IntPtr _cpuCounter;
	private IntPtr _gpuCounter;
	private IntPtr _vramCounter;
	private IntPtr _processIdCounter;
	private IntPtr _wsPrivateCounter;
	private IntPtr _arrayBuffer;
	private int _arrayBufferCapacity;
	private string _processInstanceFilter;

	private double _cpuUsage = -1.0;
	private double _gpuUsage = -1.0;
	private long _vramUsed = -1;
	private long _ramUsed = -1;

	public double GetCpuUsage() => Volatile.Read(ref _cpuUsage);
	public double GetGpuUsage() => Volatile.Read(ref _gpuUsage);
	public long GetVramUsedBytes() => Volatile.Read(ref _vramUsed);
	public long GetRamUsedBytes() => Volatile.Read(ref _ramUsed);

	public override void _ExitTree() => Stop();

	public void Start()
	{
		if (_running || !OpenQuery())
			return;
		_running = true;
		_thread = new(CollectLoop)
		{
			IsBackground = true,
			Name = "SystemStats"
		};
		_thread.Start();
	}

	public void Stop()
	{
		_running = false;
		if (_thread is { IsAlive: true })
			_thread.Join(400);
		_thread = null;
		CloseQuery();
	}

	private bool OpenQuery()
	{
		CloseQuery();
		Volatile.Write(ref _cpuUsage, -1.0);
		Volatile.Write(ref _gpuUsage, -1.0);
		Volatile.Write(ref _vramUsed, -1L);
		Volatile.Write(ref _ramUsed, -1L);
		_processInstanceFilter = "pid_" + System.Environment.ProcessId + "_";
		if (PdhOpenQueryW(null, IntPtr.Zero, out _query) != 0 || _query == IntPtr.Zero)
		{
			_query = IntPtr.Zero;
			return false;
		}
		_cpuCounter = AddEnglishCounter("\\Processor(_Total)\\% Processor Time");
		_gpuCounter = AddEnglishCounter("\\GPU Engine(*)\\Utilization Percentage");
		_vramCounter = AddEnglishCounter("\\GPU Process Memory(*)\\Dedicated Usage");
		_processIdCounter = AddEnglishCounter("\\Process(*)\\ID Process");
		_wsPrivateCounter = AddEnglishCounter("\\Process(*)\\Working Set - Private");
		_arrayBufferCapacity = 262144;
		_arrayBuffer = Marshal.AllocHGlobal(_arrayBufferCapacity);
		return true;
	}

	private void CloseQuery()
	{
		if (_arrayBuffer != IntPtr.Zero)
		{
			Marshal.FreeHGlobal(_arrayBuffer);
			_arrayBuffer = IntPtr.Zero;
		}
		_arrayBufferCapacity = 0;
		if (_query != IntPtr.Zero)
		{
			PdhCloseQuery(_query);
			_query = IntPtr.Zero;
		}
		_cpuCounter = IntPtr.Zero;
		_gpuCounter = IntPtr.Zero;
		_vramCounter = IntPtr.Zero;
		_processIdCounter = IntPtr.Zero;
		_wsPrivateCounter = IntPtr.Zero;
		_processInstanceFilter = null;
	}

	private IntPtr AddEnglishCounter(string counterPath)
	{
		if (PdhAddEnglishCounterW(_query, counterPath, IntPtr.Zero, out IntPtr counter) != 0)
			return IntPtr.Zero;
		return counter;
	}

	private void CollectLoop()
	{
		while (_running)
		{
			if (PdhCollectQueryData(_query) == 0)
			{
				if (_cpuCounter != IntPtr.Zero)
					Volatile.Write(ref _cpuUsage, ReadSingleCounter(_cpuCounter, PdhFmtDouble, Volatile.Read(ref _cpuUsage)));
				if (_gpuCounter != IntPtr.Zero)
					Volatile.Write(ref _gpuUsage, ReadAggregatedCounter(_gpuCounter, PdhFmtDouble, Volatile.Read(ref _gpuUsage), _processInstanceFilter, true));
				if (_vramCounter != IntPtr.Zero)
					Volatile.Write(ref _vramUsed, (long)ReadAggregatedCounter(_vramCounter, PdhFmtLarge, Volatile.Read(ref _vramUsed), _processInstanceFilter, false));
			}
			if (_wsPrivateCounter != IntPtr.Zero && _processIdCounter != IntPtr.Zero)
				Volatile.Write(ref _ramUsed, ReadProcessPrivateWorkingSetBytes());
			for (int i = 0; i < CollectIntervalMs / 10 && _running; i++)
				Thread.Sleep(10);
		}
	}

	private double ReadSingleCounter(IntPtr counter, uint format, double fallback)
	{
		if (PdhGetFormattedCounterValue(counter, format, IntPtr.Zero, out PdhFmtCounterValue value) != 0)
			return fallback;
		if (value.CStatus != PdhStatusValidData && value.CStatus != PdhStatusNewData)
			return fallback;
		return format == PdhFmtLarge ? value.LongValue : value.DoubleValue;
	}

	private double ReadAggregatedCounter(IntPtr counter, uint format, double fallback, string instanceFilter, bool maximize)
	{
		uint bufferSize = (uint)_arrayBufferCapacity;
		int result = PdhGetFormattedCounterArrayW(counter, format, ref bufferSize, out uint itemCount, _arrayBuffer);
		if (result == PdhMoreData)
		{
			if (!GrowArrayBuffer((int)bufferSize))
				return fallback;
			bufferSize = (uint)_arrayBufferCapacity;
			result = PdhGetFormattedCounterArrayW(counter, format, ref bufferSize, out itemCount, _arrayBuffer);
		}
		if (result != 0)
			return fallback;
		int itemSize = Marshal.SizeOf<PdhFmtCounterValueItem>();
		double aggregate = maximize ? -1.0 : 0.0;
		bool anyValid = false;
		for (uint i = 0; i < itemCount; i++)
		{
			var value = Marshal.PtrToStructure<PdhFmtCounterValueItem>(IntPtr.Add(_arrayBuffer, (int)(i * itemSize)));
			if (value.FmtValue.CStatus != PdhStatusValidData && value.FmtValue.CStatus != PdhStatusNewData)
				continue;
			if (instanceFilter != null)
			{
				string name = Marshal.PtrToStringUni(value.Name);
				if (name == null || !name.Contains(instanceFilter))
					continue;
			}
			double itemValue = format == PdhFmtLarge ? value.FmtValue.LongValue : value.FmtValue.DoubleValue;
			if (maximize)
			{
				if (!anyValid || itemValue > aggregate)
					aggregate = itemValue;
			}
			else
			{
				aggregate += itemValue;
			}
			anyValid = true;
		}
		if (!anyValid)
			return fallback;
		return maximize ? Math.Max(aggregate, 0.0) : aggregate;
	}

	private bool GrowArrayBuffer(int requiredSize)
	{
		int newCapacity = Math.Max(requiredSize + 4096, _arrayBufferCapacity * 2);
		if (newCapacity > MaxArrayBufferBytes)
			return false;
		Marshal.FreeHGlobal(_arrayBuffer);
		_arrayBuffer = Marshal.AllocHGlobal(newCapacity);
		_arrayBufferCapacity = newCapacity;
		return true;
	}

	private long ReadProcessPrivateWorkingSetBytes()
	{
		Dictionary<string, long> pidByName = CollectLargeArrayByName(_processIdCounter);
		Dictionary<string, long> wsByName = CollectLargeArrayByName(_wsPrivateCounter);
		if (pidByName == null || wsByName == null)
			return -1;
		int processId = System.Environment.ProcessId;
		foreach (KeyValuePair<string, long> entry in wsByName)
		{
			if (pidByName.TryGetValue(entry.Key, out long pid) && pid == processId)
				return entry.Value;
		}
		return -1;
	}

	private Dictionary<string, long> CollectLargeArrayByName(IntPtr counter)
	{
		uint bufferSize = (uint)_arrayBufferCapacity;
		int result = PdhGetFormattedCounterArrayW(counter, PdhFmtLarge, ref bufferSize, out uint itemCount, _arrayBuffer);
		if (result == PdhMoreData)
		{
			if (!GrowArrayBuffer((int)bufferSize))
				return null;
			bufferSize = (uint)_arrayBufferCapacity;
			result = PdhGetFormattedCounterArrayW(counter, PdhFmtLarge, ref bufferSize, out itemCount, _arrayBuffer);
		}
		if (result != 0)
			return null;
		int itemSize = Marshal.SizeOf<PdhFmtCounterValueItem>();
		Dictionary<string, long> values = new((int)itemCount);
		for (uint i = 0; i < itemCount; i++)
		{
			var value = Marshal.PtrToStructure<PdhFmtCounterValueItem>(IntPtr.Add(_arrayBuffer, (int)(i * itemSize)));
			if (value.FmtValue.CStatus != PdhStatusValidData && value.FmtValue.CStatus != PdhStatusNewData)
				continue;
			string name = Marshal.PtrToStringUni(value.Name);
			if (name == null)
				continue;
			values[name] = value.FmtValue.LongValue;
		}
		return values;
	}

	[StructLayout(LayoutKind.Explicit)]
	private struct PdhFmtCounterValue
	{
		[FieldOffset(0)] public uint CStatus;
		[FieldOffset(8)] public double DoubleValue;
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

	[DllImport("pdh.dll")]
	private static extern int PdhGetFormattedCounterValue(IntPtr counter, uint format, IntPtr counterType, out PdhFmtCounterValue value);

	[DllImport("pdh.dll", CharSet = CharSet.Unicode)]
	private static extern int PdhGetFormattedCounterArrayW(IntPtr counter, uint format, ref uint bufferSize, out uint itemCount, IntPtr itemBuffer);
}