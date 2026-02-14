# Bot Mod Development Priorities

**Last Updated:** February 14, 2026  
**Current Branch:** `zm-bots-gsc-helper-tests`  
**Status:** Phase 1 Complete - Native Framework Ready

---

## 🔥 IMMEDIATE PRIORITY - Barrier Rebuild Implementation

### Step 1: Reverse Engineer Barrier Memory Structure (CRITICAL)

**Goal:** Find memory offsets for `zbarrier` structure

**Tools Required:**
- Cheat Engine (memory scanner)
- Ghidra or IDA Pro (disassembler)
- x64dbg (debugger)

**Process:**

1. **Setup Safe Testing Environment**
   - Launch Plutonium T6 in **dedicated server mode** (local/private)
   - Load a zombies map with barriers
   - Attach Cheat Engine to `t6_zm.exe` process

2. **Find chunk_health Array**
   ```
   a. In-game, find a barrier with some boards missing
   b. In Cheat Engine:
      - Scan for "Array of bytes"
      - Look for patterns like: [100, 50, 100, 100] (max health, damaged, max health, max health)
      - Repair one board in-game
      - Scan for value changes
      - Repeat until you find the array
   c. Right-click address → "Find out what accesses this address"
   d. Note the base pointer and offsets
   ```

3. **Map Entity Structure**
   ```
   a. Find barrier entity in g_entities array
   b. Calculate offset from entity base to zbarrier pointer
   c. Calculate offset from zbarrier to chunk_health array
   d. Calculate offset to num_chunks (array size)
   ```

4. **Document Offsets**
   ```cpp
   // Add to barrier_rebuild.cpp
   #define OFFSET_ENTITY_ZBARRIER 0x??? // Find this
   #define OFFSET_ZBARRIER_CHUNK_HEALTH 0x??? // Find this
   #define OFFSET_ZBARRIER_NUM_CHUNKS 0x??? // Find this
   ```

**Expected Outcome:** Memory addresses that allow direct manipulation of barrier health

---

### Step 2: Implement Native Repair Function

**File:** `t6-gsc-helper/src/gsc/barrier_rebuild.cpp`

**Function to Complete:** `repair_barrier_chunk_direct()`

**Requirements:**
1. Read barrier entity from `g_entities[barrier_entnum]`
2. Access `zbarrier` pointer using found offset
3. Modify `chunk_health` array directly
4. Award points to bot (find point function address)
5. Trigger repair sound/animation

**Testing:**
```gsc
// In GSC console
barrier = level.exterior_goals[0];
result = player repair_barrier_chunk_direct(barrier GetEntityNumber(), 100);
IPrintLn("Repair result: " + result);
```

**Success Criteria:**
- Barrier boards visually repair
- Bot receives points
- No game crashes
- Works consistently

---

### Step 3: Implement Safety & Point Functions

**Functions to Complete:**
1. `is_safe_to_repair()` - Check zombie proximity
2. `award_repair_points()` - Hook game's point system

**Point Function Research:**
```
- Find Scr_AddPlayerScore or similar in game binary
- Signature scan for point awarding code
- Hook or call directly from C++
```

---

### Step 4: Compile & Test

**Build Process:**
```bash
# In t6-gsc-helper directory
generate.bat
# Open .sln in Visual Studio
# Build in Release mode
# Copy t6-gsc-helper.dll to %localappdata%\Plutonium\storage\t6\plugins\
```

**Testing Checklist:**
- [ ] Plugin loads without errors
- [ ] Native methods callable from GSC
- [ ] Barriers repair when bot nearby
- [ ] Points awarded correctly (10 per board)
- [ ] Repair sound plays
- [ ] No crashes or freezes
- [ ] Works on multiple maps

---

## 📋 SECONDARY PRIORITIES (After Barrier Rebuild Works)

### Priority 2: Advanced Pathfinding (Phase 3)

**Goal:** Implement A* pathfinding in C++ for better navigation

**Benefits:**
- Bots navigate complex maps better
- Avoid getting stuck
- Find optimal routes to objectives

**Implementation:**
- C++ A* algorithm with node graph
- GSC wrapper for path requests
- Cache computed paths

**Estimated Effort:** 2-3 weeks

---

### Priority 3: Player Assignment System (Phase 4)

**Goal:** Bots "partner" with human players

**Features:**
- Each bot assigned to a player
- Follow nearby, provide covering fire
- Revive assigned player first
- Share resources (doors, ammo crates)

**Implementation:**
- GSC logic with native helpers
- Assignment algorithm based on proximity
- Priority system for actions

**Estimated Effort:** 1-2 weeks

---

### Priority 4: Machine Learning Behavior (Phase 5)

**Goal:** Adaptive bot behavior based on player performance

**Features:**
- Learn player playstyle
- Adjust aggression/support balance
- Optimize resource usage

**Implementation:**
- C++ neural network or decision tree
- Training data from gameplay sessions
- GSC interface for behavior parameters

**Estimated Effort:** 4-6 weeks

---

## 🔧 MAINTENANCE TASKS (Ongoing)

### Code Quality
- [ ] Add error handling to all native functions
- [ ] Implement logging system for debugging
- [ ] Add unit tests for critical functions
- [ ] Document all public APIs

### Performance Optimization
- [ ] Profile native code for bottlenecks
- [ ] Reduce GSC function call overhead
- [ ] Optimize entity caching
- [ ] Minimize memory allocations

### Compatibility
- [ ] Test on all BO2 zombies maps
- [ ] Verify Origins-specific features work
- [ ] Check multiplayer stability (4+ bots)
- [ ] Test with various Plutonium versions

---

## 📊 PROGRESS TRACKING

### Completed Features ✅
- [x] Basic bot spawning and AI
- [x] Combat system (shooting, melee, grenades)
- [x] Perk purchasing (Juggernog, Quick Revive, Speed Cola, Double Tap)
- [x] Mystery box usage
- [x] Door/debris clearing
- [x] PAP machine usage
- [x] Origins-specific features (generators, staffs)
- [x] **Phase 1: Native framework for barrier rebuild**

### In Progress 🚧
- [ ] **Phase 2: Barrier rebuild memory implementation**

### Planned 📅
- [ ] Phase 3: Advanced pathfinding
- [ ] Phase 4: Player assignment
- [ ] Phase 5: Machine learning

---

## 🎯 SUCCESS METRICS

### Barrier Rebuild Success
- Bots repair 80%+ of damaged barriers within 30 seconds
- No performance impact (maintain 60+ FPS)
- Zero crashes in 1-hour test session

### Overall Bot Quality
- Bots reach round 30+ consistently
- Player satisfaction rating (qualitative feedback)
- Minimal human intervention required

---

## 🚨 KNOWN ISSUES

### Critical
- None currently

### High Priority
- Barrier rebuild native functions are stubs (in progress)

### Medium Priority
- Bots sometimes get stuck on geometry
- PAP usage could be more efficient
- Box usage cooldown might be too long

### Low Priority
- Bots don't use buildables optimally
- Shield usage not implemented
- Bank/fridge not utilized

---

## 📚 RESOURCES

### Documentation
- [Barrier Rebuild Implementation Guide](docs/BARRIER_REBUILD_IMPLEMENTATION.md)
- [Plutonium T6 Docs](https://plutonium.pw/docs/)
- [GSC Tool Compiler](https://github.com/xensik/gsc-tool)

### Tools
- [Cheat Engine](https://www.cheatengine.org/)
- [Ghidra](https://ghidra-sre.org/)
- [x64dbg](https://x64dbg.com/)
- [Visual Studio 2022](https://visualstudio.microsoft.com/)

### Communities
- [Plutonium Discord](https://discord.gg/plutonium)
- [BO2 Modding Forums](https://forum.plutonium.pw/)

---

## 📝 NOTES

### Anti-Cheat Considerations
- **Cheat Engine is SAFE** for local/private dedicated servers
- Do NOT use on public servers (may trigger anti-cheat)
- Plutonium allows client-side mods on private servers
- For development: use dedicated server mode, not public matchmaking

### Development Environment
- Windows 11 recommended
- Visual Studio 2022 (Community Edition is free)
- Minimum 8GB RAM for debugging
- SSD recommended for faster compilation

---

**Next Session Goals:**
1. Find barrier memory offsets using Cheat Engine
2. Implement `repair_barrier_chunk_direct()` with real memory writes
3. Test on local server
4. Capture logs and validate functionality
