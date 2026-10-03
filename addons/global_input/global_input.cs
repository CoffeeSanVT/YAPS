#if TOOLS
using Godot;
using System;

[Tool]
public partial class global_input : EditorPlugin
{
	private const string GlobalInputGDAutoloadName = "GlobalInput";

	public override void _EnterTree()
	{
		AddAutoloadSingleton(GlobalInputGDAutoloadName, "res://addons/global_input/autoload/global_input_csharp/GlobalInputCSharp.tscn");
	}

	public override void _ExitTree()
	{
		RemoveAutoloadSingleton(GlobalInputGDAutoloadName);
	}
}
#endif
