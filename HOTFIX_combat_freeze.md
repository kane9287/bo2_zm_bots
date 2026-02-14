# HOTFIX: Bot Freeze Issue

## Problem
Bots freeze on spawn because `return` statements exit the entire combat loop instead of continuing to the next iteration.

## Solution
Change `return;` to `continue;` in the main combat loop.

## Changes Required in `zm_bo2_bots_combat.gsc`

### Location 1: Around line 52
**BEFORE:**
```gsc
if(self GetCurrentWeapon() == "none")
    return;
```

**AFTER:**
```gsc
if(self GetCurrentWeapon() == "none")
    continue;  // Changed from return
```

### Location 2: Around line 57
**BEFORE:**
```gsc
sight = self bot_best_enemy_enhanced();
if(!isdefined(self.bot.threat.entity))
    return;
```

**AFTER:**
```gsc
sight = self bot_best_enemy_enhanced();
if(!isdefined(self.bot.threat.entity))
    continue;  // Changed from return
```

### Location 3: Around line 60
**BEFORE:**
```gsc
if ( threat_dead() )
{
    self bot_combat_dead();
    return;
}
```

**AFTER:**
```gsc
if ( threat_dead() )
{
    self bot_combat_dead();
    continue;  // Changed from return
}
```

## Explanation

The `for ( ;; )` loop in `bot_combat_think()` should continuously run. When using `return`, it exits the entire function, stopping the bot completely. By using `continue`, the loop skips to the next iteration and keeps running.

**Why this happens:**
- On spawn: Bot briefly has no weapon (`GetCurrentWeapon() == "none"`)
- No enemies yet: `bot_best_enemy_enhanced()` returns 0, so `threat.entity` is undefined
- These conditions cause early `return`, exiting combat loop entirely
- Bot never re-enters combat loop → **frozen**

**The fix:**
- Use `continue` to skip current iteration
- Loop continues running
- Bot keeps checking for weapons/enemies
- Bot starts working when conditions are met

## Quick Fix

Find these 3 locations in your `zm_bo2_bots_combat.gsc` and change `return;` to `continue;`:

1. After `if(self GetCurrentWeapon() == "none")`
2. After `if(!isdefined(self.bot.threat.entity))`  
3. Inside `if ( threat_dead() )` block

That's it! Bots should work immediately after this change.