using HarmonyLib;
using System;
using System.Collections.Generic;
using UnityEngine;

/// <summary>
/// Harmony Postfix patch for <see cref="TileEntityDewCollector.HandleUpdate"/>.
///
/// Server-side automation logic:
///   1. Runs at most once every <see cref="CheckIntervalSeconds"/> seconds per
///      collector position to keep CPU overhead low.
///   2. Checks whether the Dew Collector's output slot contains an item.
///   3. If it does, scans a <see cref="SearchRadius"/>-block cube for either:
///        a) a block named "automatedWaterBarrel", or
///        b) any <see cref="TileEntityLootContainer"/> whose block has the
///           property tag "WaterStorage".
///   4. If a valid container with free space is found, the water item is moved
///      into the container and the Dew Collector's output slot is cleared so
///      that the next production cycle can begin immediately.
/// </summary>
[HarmonyPatch(typeof(TileEntityDewCollector), "HandleUpdate")]
public static class DewCollectorToWaterBarrelPatch
{
    // ---------------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------------

    /// <summary>Seconds between automation checks for the same collector.</summary>
    private const double CheckIntervalSeconds = 10.0;

    /// <summary>Cube half-side radius (in blocks) to search for a storage barrel.</summary>
    private const int SearchRadius = 5;

    /// <summary>
    /// Name of the custom block that acts as an automated water storage barrel.
    /// Must match the value used in Config/blocks.xml.
    /// </summary>
    private const string WaterBarrelBlockName = "automatedWaterBarrel";

    /// <summary>
    /// Block property tag value used to mark any loot container as water storage.
    /// Set <c>&lt;property name="Tags" value="WaterStorage"/&gt;</c> in the block XML.
    /// </summary>
    private const string WaterStorageTag = "WaterStorage";

    // ---------------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------------

    /// <summary>Tracks the last time each collector position was checked.</summary>
    private static readonly Dictionary<Vector3i, double> _lastCheckTime =
        new Dictionary<Vector3i, double>();

    // ---------------------------------------------------------------------------
    // Patch
    // ---------------------------------------------------------------------------

    /// <summary>
    /// Called by Harmony immediately after every <c>TileEntityDewCollector.HandleUpdate</c>
    /// invocation.
    /// </summary>
    /// <param name="__instance">The Dew Collector tile entity being updated.</param>
    /// <param name="_world">The game world (injected by Harmony from the callee's parameter).</param>
    [HarmonyPostfix]
    public static void Postfix(TileEntityDewCollector __instance, World _world)
    {
        try
        {
            // ----------------------------------------------------------------
            // 1. Server-side guard
            // ----------------------------------------------------------------
            if (_world == null || !_world.IsServer())
                return;

            // ----------------------------------------------------------------
            // 2. Rate-limit: only check every CheckIntervalSeconds
            // ----------------------------------------------------------------
            Vector3i pos = __instance.ToWorldPos();
            double now = GetGameTime();
            if (_lastCheckTime.TryGetValue(pos, out double lastCheck) &&
                now - lastCheck < CheckIntervalSeconds)
            {
                return;
            }
            _lastCheckTime[pos] = now;

            // ----------------------------------------------------------------
            // 3. Check output slot
            // ----------------------------------------------------------------
            ItemStack[]? items = __instance.items;
            if (items == null || items.Length == 0)
                return;

            // The Dew Collector places its produced water item in slot 0.
            const int OutputSlot = 0;
            ItemStack outputItem = items[OutputSlot];
            if (outputItem == null || outputItem.IsEmpty())
                return;

            // ----------------------------------------------------------------
            // 4. Find a nearby storage container
            // ----------------------------------------------------------------
            TileEntityLootContainer? storage = FindNearbyStorage(_world, pos);
            if (storage == null)
                return;

            // ----------------------------------------------------------------
            // 5. Transfer item and clear output slot
            // ----------------------------------------------------------------
            if (TryTransferItem(ref outputItem, storage))
            {
                items[OutputSlot] = ItemStack.Empty.Clone();
                __instance.SetModified();
                storage.SetModified();

                Log.Out(
                    $"[AutomatedWaterBarrel] Transferred water from DewCollector at {pos} " +
                    $"to storage at {storage.ToWorldPos()}.");
            }
        }
        catch (Exception ex)
        {
            Log.Error($"[AutomatedWaterBarrel] Patch error: {ex}");
        }
    }

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    /// <summary>
    /// Returns a monotonically increasing game time value (wall-clock seconds).
    /// Uses <see cref="Time.realtimeSinceStartup"/> which is available on any
    /// thread and does not require the main-thread <see cref="Time.time"/>.
    /// </summary>
    private static double GetGameTime() => Time.realtimeSinceStartup;

    /// <summary>
    /// Searches a cube of side (2*<see cref="SearchRadius"/>+1) centred on
    /// <paramref name="origin"/> for a valid water storage container.
    /// Returns the first container found that also has at least one free slot,
    /// or <c>null</c> if none is found.
    /// </summary>
    private static TileEntityLootContainer? FindNearbyStorage(World world, Vector3i origin)
    {
        for (int dx = -SearchRadius; dx <= SearchRadius; dx++)
        {
            for (int dy = -SearchRadius; dy <= SearchRadius; dy++)
            {
                for (int dz = -SearchRadius; dz <= SearchRadius; dz++)
                {
                    Vector3i checkPos = new Vector3i(
                        origin.x + dx,
                        origin.y + dy,
                        origin.z + dz);

                    BlockValue blockValue = world.GetBlock(checkPos);
                    if (blockValue.isair || blockValue.Block == null)
                        continue;

                    bool isWaterBarrelByName =
                        string.Equals(
                            blockValue.Block.GetBlockName(),
                            WaterBarrelBlockName,
                            StringComparison.OrdinalIgnoreCase);

                    bool isWaterStorageByTag =
                        BlockHasTag(blockValue.Block, WaterStorageTag);

                    if (!isWaterBarrelByName && !isWaterStorageByTag)
                        continue;

                    // GetTileEntity's first argument is the "clrIdx" (cluster/colour index
                    // used by 7D2D's chunk system). Passing 0 is the standard convention in
                    // all official and community mods because tile entities do not depend on
                    // that index for retrieval — it is used only for multi-colour chunk splits
                    // which are not present in vanilla worlds.
                    TileEntityLootContainer? te =
                        world.GetTileEntity(0, checkPos) as TileEntityLootContainer;

                    if (te != null && HasFreeSlot(te))
                        return te;
                }
            }
        }

        return null;
    }

    /// <summary>
    /// Checks whether a block's "Tags" property contains the given tag value.
    /// Matches the XML: <c>&lt;property name="Tags" value="WaterStorage"/&gt;</c>
    /// </summary>
    private static bool BlockHasTag(Block block, string tag)
    {
        if (block?.Properties == null)
            return false;

        string tags = block.Properties.GetString("Tags");
        return !string.IsNullOrEmpty(tags) &&
               tags.IndexOf(tag, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    /// <summary>Returns <c>true</c> if the container has at least one empty or
    /// partially-fillable slot for the same item type.</summary>
    private static bool HasFreeSlot(TileEntityLootContainer container)
    {
        if (container.items == null)
            return false;

        foreach (ItemStack slot in container.items)
        {
            if (slot == null || slot.IsEmpty())
                return true;
        }
        return false;
    }

    /// <summary>
    /// Attempts to move <paramref name="source"/> into <paramref name="container"/>.
    /// Tries stacking on existing same-type items first, then fills an empty slot.
    /// Modifies <paramref name="source"/> count in-place if only a partial transfer
    /// occurs (the Dew Collector clears the slot on full transfer only).
    /// Returns <c>true</c> when the entire stack was transferred.
    /// </summary>
    private static bool TryTransferItem(ref ItemStack source, TileEntityLootContainer container)
    {
        ItemStack[] slots = container.items;
        if (slots == null)
            return false;

        int remaining = source.count;

        // Pass 1: stack onto existing same-type items.
        // ItemStack is a value type (struct), so we must modify slots[i] directly
        // rather than a local copy.
        for (int i = 0; i < slots.Length && remaining > 0; i++)
        {
            if (slots[i] == null || slots[i].IsEmpty() ||
                slots[i].itemValue.type != source.itemValue.type)
            {
                continue;
            }

            int maxStack = slots[i].itemValue.ItemClass?.Stacknumber.Value ?? 1;
            int space = maxStack - slots[i].count;
            if (space <= 0)
                continue;

            int move = Math.Min(space, remaining);
            slots[i].count += move;
            remaining -= move;
        }

        // Pass 2: place remainder into the first empty slot
        if (remaining > 0)
        {
            for (int i = 0; i < slots.Length; i++)
            {
                if (slots[i] != null && !slots[i].IsEmpty())
                    continue;

                slots[i] = source.Clone();
                slots[i].count = remaining;
                remaining = 0;
                break;
            }
        }

        // Only clear the Dew Collector's slot when the full stack was transferred
        return remaining == 0;
    }
}
