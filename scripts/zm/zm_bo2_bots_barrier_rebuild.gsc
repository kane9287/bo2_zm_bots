#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_laststand;

bot_rebuild_barriers()
{
    // Disabled for now - barrier repair doesn't work reliably with bots
    // The game engine doesn't properly handle UseButtonPressed() from bot entities
    // This would require engine-level support or a custom implementation
    return;
    
    /*
    // Original implementation kept for reference:
    if(!isDefined(self.bot.barrier_repair_time) || GetTime() > self.bot.barrier_repair_time)
    {
        self.bot.barrier_repair_time = GetTime() + 8000;
        
        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            return;
            
        if(!isDefined(level.exterior_goals) || level.exterior_goals.size == 0)
            return;
            
        // Find closest damaged barrier
        closest_barrier = undefined;
        closest_dist = 999999;
        
        foreach(barrier in level.exterior_goals)
        {
            if(!isDefined(barrier) || !isDefined(barrier.origin) || !isDefined(barrier.zbarrier))
                continue;
                
            dist = Distance(self.origin, barrier.origin);
            if(dist < 200 && is_barrier_damaged(barrier))
            {
                if(dist < closest_dist)
                {
                    closest_barrier = barrier;
                    closest_dist = dist;
                }
            }
        }
        
        // Attempt repair
        if(isDefined(closest_barrier))
        {
            self thread repair_barrier(closest_barrier);
        }
    }
    */
}