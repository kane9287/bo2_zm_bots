// T6 GSC SOURCE
// Compiler version 0 (prec2)
// Barrier Rebuild System for Bots - Native Helper Version
// Requires t6-gsc-helper plugin with barrier rebuild support

#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_score;

init()
{
	level.barrier_rebuild_enabled = true;
	
	// Configuration
	level.bot_repair_check_interval = 5000; // Check every 5 seconds
	level.bot_repair_safe_distance = 200; // Min distance from zombies (squared: 40000)
	level.bot_repair_search_radius = 300; // Max distance to look for barriers
	level.bot_repair_points_per_board = 10; // Points awarded per board
}

// Main barrier repair logic for bots
bot_rebuild_barriers()
{
	if(!isDefined(self.bot.barrier_repair_time) || GetTime() > self.bot.barrier_repair_time)
	{
		self.bot.barrier_repair_time = GetTime() + level.bot_repair_check_interval;
		
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			return;
		
		if(!isDefined(level.exterior_goals) || level.exterior_goals.size == 0)
			return;
		
		// Find closest damaged barrier
		closest_barrier = self find_closest_damaged_barrier();
		
		if(isDefined(closest_barrier))
		{
			// Check if it's safe to repair (no zombies too close)
			if(self can_safely_repair_barrier(closest_barrier))
			{
				// Attempt native repair
				self thread repair_barrier_native(closest_barrier);
			}
		}
	}
}

// Find the closest damaged barrier
find_closest_damaged_barrier()
{
	closest_barrier = undefined;
	closest_dist_sq = 999999;
	search_radius_sq = level.bot_repair_search_radius * level.bot_repair_search_radius; // 90000
	
	foreach(barrier in level.exterior_goals)
	{
		if(!isDefined(barrier) || !isDefined(barrier.origin))
			continue;
			
		if(!isDefined(barrier.zbarrier) || !isDefined(barrier.zbarrier.chunk_health))
			continue;
			
		dist_sq = DistanceSquared(self.origin, barrier.origin);
		
		// Only consider barriers within search radius
		if(dist_sq > search_radius_sq)
			continue;
			
		// Check if barrier is damaged
		if(is_barrier_damaged(barrier))
		{
			if(dist_sq < closest_dist_sq)
			{
				closest_dist_sq = dist_sq;
				closest_barrier = barrier;
			}
		}
	}
	
	return closest_barrier;
}

// Check if barrier needs repair
is_barrier_damaged(barrier)
{
	if(!isDefined(barrier) || !isDefined(barrier.zbarrier) || !isDefined(barrier.zbarrier.chunk_health))
		return false;
		
	max_health = 0;
	for(i = 0; i < barrier.zbarrier.chunk_health.size; i++)
	{
		if(barrier.zbarrier.chunk_health[i] > max_health)
			max_health = barrier.zbarrier.chunk_health[i];
	}
	
	// If max_health is 0, no boards exist
	if(max_health == 0)
		return false;
		
	// Check if any chunk is damaged
	for(i = 0; i < barrier.zbarrier.chunk_health.size; i++)
	{
		if(barrier.zbarrier.chunk_health[i] < max_health)
			return true;
	}
	
	return false;
}

// Check if it's safe to repair (no zombies nearby)
can_safely_repair_barrier(barrier)
{
	if(!isDefined(barrier) || !isDefined(barrier.origin))
		return false;
		
	// Use native helper for fast zombie proximity check
	safe = self is_safe_to_repair(barrier.origin, level.bot_repair_safe_distance);
	
	return safe;
}

// Repair barrier using native helper
repair_barrier_native(barrier)
{
	self endon("disconnect");
	self endon("death");
	level endon("game_ended");
	
	if(!isDefined(barrier) || !isDefined(barrier.origin))
		return;
		
	// Navigate to barrier
	dist_sq = DistanceSquared(self.origin, barrier.origin);
	
	if(dist_sq > 10000) // 100^2
	{
		// Move closer if not in range
		if(!self hasgoal("barrier_repair"))
			self AddGoal(barrier.origin, 75, 3, "barrier_repair");
			
		// Wait to get closer
		wait 0.5;
		return;
	}
		
	// We're close enough, cancel movement goal
	if(self hasgoal("barrier_repair"))
		self cancelgoal("barrier_repair");
		
	// Look at barrier
	self lookat(barrier.origin);
	wait 0.2;
		
	// Get barrier entity number (need to find this)
	barrier_entnum = barrier GetEntityNumber();
	
	if(!isDefined(barrier_entnum))
		return;
		
	// Get max health for repair target
	max_health = 0;
	for(i = 0; i < barrier.zbarrier.chunk_health.size; i++)
	{
		if(barrier.zbarrier.chunk_health[i] > max_health)
			max_health = barrier.zbarrier.chunk_health[i];
	}
	
	if(max_health == 0)
		return;
		
	// Call native repair function
	// This bypasses the "use button held" requirement
	success = self repair_barrier_chunk_direct(barrier_entnum, max_health);
	
	if(success)
	{
		// Award points to bot
		boards_repaired = 0;
		for(i = 0; i < barrier.zbarrier.chunk_health.size; i++)
		{
			if(barrier.zbarrier.chunk_health[i] < max_health)
				boards_repaired++;
		}
		
		if(boards_repaired > 0)
		{
			points = boards_repaired * level.bot_repair_points_per_board;
			self award_repair_points(points);
			
			// Play repair sound
			self PlaySound("zmb_repair_boards");
		}
	}
}

// Fallback: Get entity number for barriers
// Note: This might not work for all barrier types
GetEntityNumber()
{
	if(!isDefined(self))
		return undefined;
		
	// Barriers in BO2 are entities, try to get their entity number
	if(isDefined(self.targetname) && self.targetname == "exterior_goal")
	{
		// Try to find entity number through entity array
		// This is a workaround until we can properly identify it
		return 0; // Placeholder
	}
	
	return undefined;
}
