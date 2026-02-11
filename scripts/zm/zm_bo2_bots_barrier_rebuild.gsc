#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_laststand;

init()
{
    level.barrier_log_initialized = false;
}

log_barrier(message)
{
    // Initialize log file on first write
    if(!isDefined(level.barrier_log_initialized) || !level.barrier_log_initialized)
    {
        logPrint("\n========================================\n");
        logPrint("BARRIER DEBUG LOG - " + getTime() + "\n");
        logPrint("========================================\n\n");
        level.barrier_log_initialized = true;
    }

    logPrint(message + "\n");
}

// Returns true if barrier needs repair
is_barrier_damaged(barrier)
{
    if (!isDefined(barrier) || !isDefined(barrier.zbarrier) || !isDefined(barrier.zbarrier.chunk_health))
        return false;

    max_health = 0;
    for (i = 0; i < barrier.zbarrier.chunk_health.size; i++)
    {
        if (barrier.zbarrier.chunk_health[i] > max_health)
            max_health = barrier.zbarrier.chunk_health[i];
    }

    // If max_health is 0, treat as "no boards" / ignore
    if (max_health == 0)
        return false;

    for (i = 0; i < barrier.zbarrier.chunk_health.size; i++)
    {
        if (barrier.zbarrier.chunk_health[i] < max_health)
            return true;
    }

    return false;
}

// Returns true if barrier is fully repaired
barrier_fully_repaired(barrier)
{
    if (!isDefined(barrier) || !isDefined(barrier.zbarrier) || !isDefined(barrier.zbarrier.chunk_health))
        return false;

    max_health = 0;
    for (i = 0; i < barrier.zbarrier.chunk_health.size; i++)
    {
        if (barrier.zbarrier.chunk_health[i] > max_health)
            max_health = barrier.zbarrier.chunk_health[i];
    }

    // If max_health is 0, consider this "no boards" / ignore
    if (max_health == 0)
        return false;

    for (i = 0; i < barrier.zbarrier.chunk_health.size; i++)
    {
        if (barrier.zbarrier.chunk_health[i] < max_health)
            return false;
    }

    return true;
}

// Repair loop - simulates player holding use button
repair_barrier_loop(barrier)
{
    if (!isDefined(barrier) || !isDefined(barrier.zbarrier))
        return;

    max_attempts = 15;
    attempts = 0;

    log_barrier("  REPAIR LOOP START: max_attempts=" + max_attempts);
    
    // Store original position
    original_pos = self.origin;
    original_angles = self.angles;
    
    // Move bot very close to barrier if not already there
    repair_distance = Distance(self.origin, barrier.origin);
    if(repair_distance > 75)
    {
        log_barrier("    Moving bot closer to barrier (was " + int(repair_distance) + " units away)");
        // Position bot at barrier location with slight offset to avoid clipping
        offset_pos = barrier.origin + (0, 0, 5);
        self SetOrigin(offset_pos);
        wait 0.1;
    }

    while (attempts < max_attempts && !barrier_fully_repaired(barrier))
    {
        // Log chunk health before repair attempt
        chunk_str = "";
        for (i = 0; i < barrier.zbarrier.chunk_health.size; i++)
        {
            chunk_str += barrier.zbarrier.chunk_health[i];
            if (i < barrier.zbarrier.chunk_health.size - 1)
                chunk_str += ",";
        }
        log_barrier("    ATTEMPT " + attempts + " BEFORE: [" + chunk_str + "]");

        // Simulate holding use button
        self UseButtonPressed();
        
        // Look directly at barrier center
        self lookat(barrier.origin);
        
        // Fire repair events using multiple methods for maximum compatibility
        if (isDefined(barrier.unitrigger_stub))
        {
            // This is the most reliable method for BO2 barriers
            barrier.unitrigger_stub notify("trigger", self);
            log_barrier("      Fired unitrigger_stub trigger");
            
            // Try calling the trigger function directly if it exists
            if(isDefined(barrier.unitrigger_stub.trigger_func))
            {
                self thread [[barrier.unitrigger_stub.trigger_func]](barrier.unitrigger_stub);
                log_barrier("      Called trigger_func directly");
            }
        }
        else if (isDefined(barrier.trigger_use))
        {
            barrier.trigger_use notify("trigger", self);
            log_barrier("      Fired trigger_use trigger");
        }
        else
        {
            log_barrier("      No standard trigger found, using fallback");
        }
        
        // Always fire these for maximum compatibility
        barrier notify("repair_board", self);
        barrier.zbarrier notify("repair_board", self);

        // Longer wait for game to process the repair
        wait 0.5;

        // Log chunk health after repair attempt
        chunk_str = "";
        for (i = 0; i < barrier.zbarrier.chunk_health.size; i++)
        {
            chunk_str += barrier.zbarrier.chunk_health[i];
            if (i < barrier.zbarrier.chunk_health.size - 1)
                chunk_str += ",";
        }
        log_barrier("    ATTEMPT " + attempts + " AFTER:  [" + chunk_str + "]");

        attempts++;
    }
    
    // Restore original position and angles
    self SetOrigin(original_pos);
    self SetPlayerAngles(original_angles);

    if (barrier_fully_repaired(barrier))
        log_barrier("  REPAIR LOOP COMPLETE: Barrier fully repaired!");
    else
        log_barrier("  REPAIR LOOP COMPLETE: Max attempts reached (" + attempts + "), barrier still damaged");
}

bot_rebuild_barriers()
{
    if(!isDefined(self.bot.barrier_repair_time) || GetTime() > self.bot.barrier_repair_time)
    {
        self.bot.barrier_repair_time = GetTime() + 8000; // Check every 8 seconds (increased for repair time)

        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            return;

        if(!isDefined(level.exterior_goals) || level.exterior_goals.size == 0)
            return;

        closest_barrier = undefined;
        closest_dist = 999999;
        needs_repair_count = 0;

        log_barrier("===== BARRIER CHECK CYCLE [" + getTime() + "] =====");
        log_barrier("Bot position: " + self.origin);
        log_barrier("Total exterior_goals: " + level.exterior_goals.size);

        foreach(barrier in level.exterior_goals)
        {
            if(!isDefined(barrier) || !isDefined(barrier.origin))
                continue;

            if(!isDefined(barrier.zbarrier))
                continue;

            dist = Distance(self.origin, barrier.origin);

            // Only check barriers within reasonable distance
            if(dist < 200)
            {
                log_barrier("\n--- Barrier at distance: " + int(dist) + " ---");
                log_barrier("Barrier origin: " + barrier.origin);

                // Quick chunk_health summary
                if(isDefined(barrier.zbarrier.chunk_health))
                {
                    chunk_str = "";
                    for(i = 0; i < barrier.zbarrier.chunk_health.size; i++)
                    {
                        chunk_str += barrier.zbarrier.chunk_health[i];
                        if (i < barrier.zbarrier.chunk_health.size - 1)
                            chunk_str += ",";
                    }
                    log_barrier("  chunk_health: [" + chunk_str + "]");

                    if(is_barrier_damaged(barrier))
                    {
                        needs_repair_count++;
                        log_barrier("  STATUS: NEEDS REPAIR");
                        if(dist < closest_dist)
                        {
                            closest_barrier = barrier;
                            closest_dist = dist;
                        }
                    }
                    else
                    {
                        log_barrier("  STATUS: FULLY REPAIRED");
                    }
                }
                else
                {
                    log_barrier("  STATUS: No chunk_health - skipping");
                }
            }
        }

        log_barrier("SUMMARY: Total barriers needing repair: " + needs_repair_count);

        if(isDefined(closest_barrier))
        {
            log_barrier("REPAIR TARGET: Closest barrier at distance: " + int(closest_dist));
            repair_barrier_loop(closest_barrier);
        }
        else
        {
            log_barrier("No repair targets found");
        }

        log_barrier("===== END BARRIER CHECK CYCLE =====\n\n");
    }
}