# Bot Optimization & Enhancement Guide

This guide explains the new optimizations and enhancements added to improve bot combat effectiveness and player support.

## Priority Ranking (Easiest → Hardest)

### ⭐ Priority 1: EASY (Quick Wins)
1. **Code Cleanup** - Remove duplicate functions, cache arrays
2. **Shoot While Downed** - Bots fire when in last stand
3. **Performance Fixes** - Optimized wait times and cleanup

### ⭐⭐ Priority 2: MEDIUM (Better Combat)
4. **Enhanced Threat Scoring** - Prioritize zombies near human players
5. **Improved Revive System** - Danger assessment + covering fire
6. **Player Support** - Stay in support range, watch player's back

### ⭐⭐⭐ Priority 3: HARD (Advanced AI)
7. **Squad Fire Coordination** - Avoid redundant targeting
8. **Tactical Positioning** - Use chokepoints and cover

---

## Implementation Instructions

### Step 1: Add Include Statements

Add to **`zm_bo2_bots.gsc`** at the top:
```gsc
#include scripts\zm\zm_bo2_bots_optimization;
```

Add to **`zm_bo2_bots_combat.gsc`** at the top:
```gsc
#include scripts\zm\zm_bo2_bots_optimization;
#include scripts\zm\zm_bo2_bots_combat_enhanced;
```

### Step 2: Integrate Priority 1 Features

#### A. Shoot While Downed
Add to `onspawn()` function in **`zm_bo2_bots.gsc`**:
```gsc
self waittill("spawned_player");
self thread bot_perks();
self thread bot_spawn();
self thread bot_combat_laststand();  // NEW: Enable shooting while downed
```

#### B. Cleanup on Death
Add to `bot_spawn_init()` in **`zm_bo2_bots.gsc`**:
```gsc
self thread bot_cleanup_on_death();  // NEW: Clean up resources
```

#### C. Use Cached Weapon Tiers
Replace `bot_should_take_weapon()` function to use cached tiers:
```gsc
// Replace tier array definitions with function calls
tier1_weapons = get_tier1_weapons();
tier2_weapons = get_tier2_weapons();
tier3_weapons = get_tier3_weapons();
tier4_weapons = get_tier4_weapons();
```

### Step 3: Integrate Priority 2 Features

#### A. Enhanced Threat Scoring
Replace `bot_calculate_threat_score()` in **`zm_bo2_bots_combat.gsc`** with:
```gsc
bot_calculate_threat_score(zombie)
{
    return bot_calculate_threat_score_enhanced(zombie);
}
```

#### B. Improved Revive System
Replace the `bot_revive_teammates()` function in **`zm_bo2_bots.gsc`**:
```gsc
bot_revive_teammates()
{
    if(!maps\mp\zombies\_zm_laststand::player_any_player_in_laststand())
    {
        self cancelgoal("revive");
        return;
    }
    
    if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
        return;
        
    teammate = self get_closest_downed_teammate();
    if(!isDefined(teammate))
        return;
    
    // NEW: Check danger level
    danger_level = bot_assess_revive_danger(teammate);
    
    // NEW: Clear zombies if too dangerous
    if(danger_level > 5 && isDefined(self.bot.threat.entity))
    {
        closest_zombie = bot_get_closest_enemy(teammate.origin);
        if(isDefined(closest_zombie) && Distance(closest_zombie.origin, teammate.origin) < 200)
        {
            self.bot.threat.entity = closest_zombie;
            return; // Kill zombies first
        }
    }
    
    if(!self hasgoal("revive"))
    {
        self AddGoal(teammate.origin, 50, 4, "revive");
    }
    else
    {
        if(self AtGoal("revive") || Distance(self.origin, teammate.origin) < 75)
        {
            // NEW: Provide covering fire
            self thread bot_cover_while_reviving(teammate);
            
            teammate.revivetrigger disable_trigger();
            wait 0.75;
            teammate.revivetrigger enable_trigger();
            
            if(!self maps\mp\zombies\_zm_laststand::player_is_in_laststand() && 
               teammate maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            {
                teammate maps\mp\zombies\_zm_laststand::auto_revive(self);
            }
        }
    }
}
```

#### C. Player Support
Add to `bot_main()` loop in **`zm_bo2_bots.gsc`**:
```gsc
self bot_combat_think(damage, attacker, direction);
self bot_update_follow_host();
self bot_support_human_player();  // NEW: Stay in support range
self bot_update_lookat();
```

### Step 4: Integrate Priority 3 Features (Advanced)

#### A. Squad Coordination
Replace `bot_best_enemy_enhanced()` calls with:
```gsc
sight = bot_best_enemy_with_coordination();
```

Add to `bot_main()` loop:
```gsc
self bot_coordinate_fire();  // NEW: Avoid redundant targeting
```

#### B. Tactical Positioning
Add to `bot_main()` loop (after combat think):
```gsc
self bot_use_tactical_positioning();  // NEW: Use chokepoints
```

---

## Feature Descriptions

### Priority 1 Features

#### 1. Shoot While Downed ✓
- **What**: Bots continue shooting zombies when in last stand
- **Benefit**: More team firepower, better survival
- **Implementation**: Spawns thread on bot spawn

#### 2. Code Cleanup ✓
- **What**: Removes duplicate functions, caches weapon tier arrays
- **Benefit**: Better performance, less memory usage
- **Implementation**: Global cached functions

#### 3. Cleanup on Death ✓
- **What**: Clears cached data and goals when bot dies
- **Benefit**: Prevents memory leaks
- **Implementation**: Waittill death/disconnect

### Priority 2 Features

#### 4. Enhanced Threat Scoring ✓
- **What**: Prioritizes zombies attacking human players (800 points bonus)
- **Benefit**: Bots protect human players better
- **Scoring System**:
  - Zombies near human player: +800 points
  - Zombies near downed player: +500 points  
  - Zombies in player's line of fire: +400 points
  - Special zombies (Brutus): +600 points
  - Distance penalty: decreases with range

#### 5. Improved Revive System ✓
- **What**: Assesses danger before reviving, provides covering fire
- **Benefit**: Safer revives, less bot deaths
- **Features**:
  - Danger assessment (counts nearby zombies)
  - Clears area if danger > 5 zombies
  - Shoots while reviving

#### 6. Player Support ✓
- **What**: Maintains 200-400 unit distance from human player
- **Benefit**: Better formation, watches player's back
- **Behavior**:
  - Moves closer if >500 units away
  - Gives space if <120 units
  - Looks in opposite direction to cover flanks

### Priority 3 Features

#### 7. Squad Fire Coordination ✓
- **What**: Prevents multiple bots from targeting same zombie
- **Benefit**: Better target distribution, more efficient
- **Logic**:
  - Checks if 2+ bots targeting same zombie
  - Finds alternate target with less contention
  - Prioritizes uncontested high-threat zombies

#### 8. Tactical Positioning ✓
- **What**: Uses chokepoints, corners, and elevated positions
- **Benefit**: Better defensive positioning, funnel zombies
- **Scoring**:
  - Chokepoints (narrow approach): +120 points
  - Support range (200-400 units): +80 points
  - Nearby cover: +50 points
  - Elevation: +30 points

---

## Testing Checklist

### Priority 1 (Easy)
- [ ] Bots shoot while downed
- [ ] No duplicate array_combine errors
- [ ] Bots clean up goals on death
- [ ] No memory leaks after multiple rounds

### Priority 2 (Medium)
- [ ] Bots prioritize zombies near human player
- [ ] Bots clear area before reviving in dangerous situations
- [ ] Bots provide covering fire during revives
- [ ] Bots stay within support range (200-400 units)
- [ ] Bots watch player's back (look opposite direction)

### Priority 3 (Hard)
- [ ] Multiple bots don't all target same zombie
- [ ] Bots spread targets effectively
- [ ] Bots use chokepoints when available
- [ ] Bots position near corners/cover
- [ ] Bots maintain good formation

---

## Performance Notes

**Optimized**:
- Cached zombie lists (updates every 0.5s instead of every frame)
- Cached weapon tier arrays (defined once globally)
- Goal cleanup on death (prevents memory leaks)
- Reduced redundant distance calculations

**Trade-offs**:
- Squad coordination adds ~1500ms between checks
- Tactical positioning adds ~3000ms between checks
- Both use low-priority goals to avoid interfering with combat

---

## Debugging Tips

1. **Bots not shooting while downed?**
   - Check `bot_combat_laststand()` is threaded in `onspawn()`
   - Verify `allowattack(1)` is being called

2. **Bots clustering together?**
   - Verify `bot_coordinate_fire()` is being called in main loop
   - Check console for targeting distribution

3. **Performance issues?**
   - Reduce check frequency in Priority 3 features
   - Disable tactical positioning temporarily
   - Monitor entity cache updates

4. **Bots not protecting player?**
   - Check `get_human_player()` returns valid player
   - Verify threat scoring calculation
   - Print threat scores to console for debugging

---

## Recommended Implementation Order

1. **Start with Priority 1** - Easy wins, immediate improvement
2. **Test thoroughly** - Ensure no crashes or errors
3. **Add Priority 2** - Medium difficulty, significant combat improvement
4. **Test in-game** - Verify player protection and revive system
5. **Add Priority 3** - Advanced features, test performance impact
6. **Fine-tune** - Adjust thresholds and timings based on gameplay

---

## Configuration Options (Future)

Consider adding Dvars for:
- `bot_support_distance` - Optimal distance from player (default: 300)
- `bot_revive_danger_threshold` - Max zombies before clearing (default: 5)
- `bot_coordination_enabled` - Enable squad coordination (default: 1)
- `bot_tactical_positioning` - Enable tactical positioning (default: 1)

---

## Links

- [zm_bo2_bots_optimization.gsc](scripts/zm/zm_bo2_bots_optimization.gsc) - Priority 1 & 2 features
- [zm_bo2_bots_combat_enhanced.gsc](scripts/zm/zm_bo2_bots_combat_enhanced.gsc) - Priority 3 features
- [zm_bo2_bots.gsc](scripts/zm/zm_bo2_bots.gsc) - Main bot file
- [zm_bo2_bots_combat.gsc](scripts/zm/zm_bo2_bots_combat.gsc) - Combat logic file