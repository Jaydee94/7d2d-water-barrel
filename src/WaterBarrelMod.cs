using HarmonyLib;
using System.Reflection;
using UnityEngine;

/// <summary>
/// Entry point for the AutomatedWaterBarrel mod.
/// Harmony patches are discovered automatically via annotation scanning.
/// </summary>
public class WaterBarrelMod : IModApi
{
    private static Harmony? _harmony;

    public void InitMod(Mod _modInstance)
    {
        _harmony = new Harmony("com.jaydee94.automatedwaterbarrel");
        _harmony.PatchAll(Assembly.GetExecutingAssembly());

        Debug.Log("[AutomatedWaterBarrel] Mod loaded - DewCollector -> WaterBarrel automation active.");
    }
}
