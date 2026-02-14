# Barrier Rebuild Implementation Guide

## Overview
This document explains the barrier rebuild system for bots in Black Ops 2 Zombies. The system uses **native C++ hooks** via t6-gsc-helper to bypass engine limitations that prevent pure GSC solutions.

## The Problem

### Why Pure GSC Doesn't Work
The Black Ops 2 engine's barrier repair system requires:
1. A player entity to be within range of the barrier
2. The player to **physically hold the use button** (actual controller/keyboard input)
3. The engine validates this input at a low level before processing repair

Bots cannot trigger this because:
- `UseButtonPressed()` in GSC doesn't register as actual player input
- `notify("trigger")` events are ignored for barrier repairs
- The engine checks for **human input state** before allowing repairs

### Previous Attempts
Your debugging (see `zm_bo2_bots_barrier_rebuild.gsc` attached) showed:
- ✅ Successfully identified barriers via `level.exterior_goals`
- ✅ Successfully detected damage via `barrier.zbarrier.chunk_health`
- ✅ Tried all trigger methods (unitrigger_stub, trigger_func, repair_board notifies)
- ❌ `chunk_health` values never changed - engine ignored bot triggers

## The Solution

### Native C++ Hook Approach
We bypass the use button requirement by:
1. **Hooking the game's barrier repair function** at the native code level
2. **Directly modifying barrier health** in game memory
3. **Awarding points** to bots programmatically
4. **Triggering repair sounds/animations** via game functions

---

## Implementation Status

### ✅ Completed (Phase 1 - Setup)

#### t6-gsc-helper Plugin ([commit 69a262e](https://github.com/kane9287/t6-gsc-helper/commit/69a262ee00033b59d0a218ba4c21bfa8c8656140))

**Files Created:**
- `src/gsc/barrier_rebuild.cpp` - Native barrier repair functions
- `src/gsc/barrier_rebuild.hpp` - Header declarations  
- `src/stdafx.hpp` - Updated with includes
- `src/main.cpp` - Initialized barrier system

**Native Methods Available:**
```cpp
// Force repair a barrier chunk (bypasses use button)
self force_repair_barrier(barrier_entnum, chunk_index)

// Repair all damaged chunks instantly
self repair_barrier_chunk_direct(barrier_entnum, max_health)

// Check if safe to repair (no zombies nearby)
self is_safe_to_repair(barrier_position, safe_distance)

// Award points to bot for repair
self award_repair_points(points)
```

#### Bot Mod ([commit d70e9ea](https://github.com/kane9287/bo2_zm_bots/commit/d70e9eac85c20a9970471a3e855450801bab4e49))

**Files Created:**
- `scripts/zm/zm_bo2_bots_barrier_rebuild.gsc` - GSC wrapper for native functions
- `scripts/zm/zm_bo2_bots.gsc` - Integrated into main bot loop

**GSC Functions:**
```gsc
bot_rebuild_barriers()           // Main repair logic
find_closest_damaged_barrier()  // Find nearest damaged barrier
is_barrier_damaged(barrier)      // Check if barrier needs repair
can_safely_repair_barrier(barrier) // Safety check
repair_barrier_native(barrier)   // Execute repair via native
```

**Configuration:**
```gsc
level.bot_repair_check_interval = 5000;  // Check every 5 seconds
level.bot_repair_safe_distance = 200;    // Min zombie distance
level.bot_repair_search_radius = 300;    // Max search range
level.bot_repair_points_per_board = 10;  // Points per board
```

---

### ⚠️ To-Do (Phase 2 - Implementation)

The native functions are **stubs** that need implementation. Here's what's required:

#### 1. Reverse Engineering Required

You need to find these game functions/addresses:

**Barrier Data Structures:**
```cpp
// Find in game memory
struct zbarrier_t {
    // ...
    int* chunk_health;      // Array of board healths
    int num_chunks;         // Number of boards
    // ...
};

struct barrier_entity_t {
    // ...
    zbarrier_t* zbarrier;   // Pointer to barrier data
    // ...
};
```

**Game Functions to Find:**
```cpp
// Search for these in t6_zm.exe or game_mp.dll
void* Scr_AddPlayerScore;        // Award points function
void* Scr_PlaySound;             // Play repair sound
void* Barrier_RepairChunk;       // Native repair function (if exists)
```

#### 2. Memory Manipulation

**Direct Repair Implementation:**
```cpp
void repair_barrier_chunk_direct(game::scr_entref_t ent)
{
    auto* bot = &game::g_entities[ent.entnum];
    auto barrier_entnum = gsc::value::get<int>(0);
    auto max_health = gsc::value::get<int>(1);
    
    if(barrier_entnum < 0 || barrier_entnum >= 2048)
    {
        gsc::value::add<int>(0);
        return;
    }
    
    auto* barrier = &game::g_entities[barrier_entnum];
    
    // TODO: Find these offsets through reverse engineering
    // Example (offsets are placeholders):
    auto* zbarrier = *(void**)((uintptr_t)barrier + 0xABC); // Find actual offset
    auto* chunk_health = *(int**)((uintptr_t)zbarrier + 0xDEF); // Find actual offset
    int num_chunks = *(int*)((uintptr_t)zbarrier + 0x123); // Find actual offset
    
    // Repair all damaged chunks
    int boards_repaired = 0;
    for(int i = 0; i < num_chunks; i++)
    {
        if(chunk_health[i] < max_health)
        {
            chunk_health[i] = max_health;
            boards_repaired++;
        }
    }
    
    // Award points
    if(boards_repaired > 0)
    {
        int points = boards_repaired * 10;
        // Call game's point awarding function
        // Example: Scr_AddPlayerScore(bot, points, "repair");
    }
    
    gsc::value::add<int>(1); // Success
}
```

#### 3. Tools Needed

**For Reverse Engineering:**
- [Ghidra](https://ghidra-sre.org/) - Free decompiler
- [IDA Pro](https://hex-rays.com/ida-pro/) - Professional disassembler  
- [Cheat Engine](https://www.cheatengine.org/) - Memory scanner
- [x64dbg](https://x64dbg.com/) - Debugger

**Process:**
1. Attach Cheat Engine to `t6_zm.exe`
2. Find barrier entities in memory (search for `chunk_health` arrays)
3. Note memory offsets from entity base
4. Use Ghidra to find functions that modify `chunk_health`
5. Implement in C++

#### 4. Testing Procedure

**Step 1: Verify Native Methods Load**
```gsc
// In GSC, test if native methods exist
if(isDefined(self.repair_barrier_chunk_direct))
    IPrintLn("Native barrier methods loaded!");
else
    IPrintLn("ERROR: Native methods not found!");
```

**Step 2: Test Safety Check**
```gsc
// Test zombie proximity detection
safe = self is_safe_to_repair((0,0,0), 200);
IPrintLn("Safe to repair: " + safe);
```

**Step 3: Test Repair**
```gsc
// Find a barrier and try to repair
barrier = level.exterior_goals[0];
result = self repair_barrier_chunk_direct(barrier.entnum, 100);
IPrintLn("Repair result: " + result);
```

---

## Integration into Main Bot System

### Bot Main Loop
```gsc
// In bot_main() - runs every 5 seconds
if(GetTime() > self.bot.last_barrier_check)
{
    self.bot.last_barrier_check = GetTime() + 5000;
    self scripts\zm\zm_bo2_bots_barrier_rebuild::bot_rebuild_barriers();
}
```

### Execution Flow
1. **Every 5 seconds**, bot checks for damaged barriers within 300 units
2. **Selects closest** damaged barrier
3. **Safety check**: Ensures no zombies within 200 units  
4. **Navigation**: Moves to barrier if too far (>100 units)
5. **Repair**: Calls native function to repair all damaged chunks
6. **Rewards**: Awards 10 points per board repaired
7. **Audio**: Plays repair sound effect

---

## Compilation Instructions

### t6-gsc-helper Plugin

1. Navigate to t6-gsc-helper directory
2. Run `generate.bat` to create Visual Studio project
3. Open generated `.sln` in Visual Studio
4. Build in **Release** mode
5. Copy `t6-gsc-helper.dll` to `%localappdata%\Plutonium\storage\t6\plugins\`

### Bot Mod

1. Compile GSC scripts using [GSC Compiler](https://github.com/xensik/gsc-tool)
2. Place compiled scripts in `t6r/data/scripts/zm/`
3. Launch Plutonium T6 dedicated server
4. Bot mod will auto-load with native barrier support

---

## Next Steps

### Immediate Priority
1. **Reverse engineer** barrier structure offsets
2. **Implement** `repair_barrier_chunk_direct()` with real memory writes
3. **Test** on a local dedicated server
4. **Verify** points are awarded and barriers actually repair

### After Barrier Rebuild Works
**Phase 3: Complex Pathfinding** - A* algorithm in C++
**Phase 4: Player Assignment** - Bot-player partnerships
**Phase 5: Machine Learning** - Adaptive bot behavior

---

## Troubleshooting

### Plugin Doesn't Load
- Check Plutonium logs in `%localappdata%\Plutonium\storage\t6\`
- Ensure DLL is in correct plugins folder
- Verify DLL is compiled for correct architecture (x86/x64)

### Native Methods Not Found in GSC
- Plugin might not be loading
- Check `gsc::barrier::init()` is called in `main.cpp`
- Verify method names match exactly in C++ and GSC

### Barrier Doesn't Repair
- Native functions are stubs - implementation needed
- Check console for error messages
- Verify barrier entity numbers are valid

---

## References

- [Plutonium T6 Documentation](https://plutonium.pw/docs/)
- [GSC Tool Compiler](https://github.com/xensik/gsc-tool)
- [T6 GSC Helper Example](https://github.com/kane9287/t6-gsc-helper)
- [BO2 Modding Discord](https://discord.gg/plutonium)

---

**Created:** February 14, 2026  
**Status:** Phase 1 Complete - Awaiting Implementation  
**Branch:** `zm-bots-gsc-helper-tests`
