// zm_bo2_bots_unstuck.gsc
// Safe wall-stuck prevention system
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;

init()
{
	// Initialize unstuck system for all bots
	level thread monitor_bots_for_stuck();
}

monitor_bots_for_stuck()
{
	level endon("end_game");
	
	// Wait for game to start
	flag_wait("initial_blackscreen_passed");
	wait 5;
	
	while(true)
	{
		wait 2; // Check every 2 seconds (low performance impact)
		
		// Safety check
		if(!isDefined(level.bots) || level.bots.size == 0)
			continue;
		
		foreach(bot in level.bots)
		{
			// Safety checks
			if(!isDefined(bot) || !isAlive(bot))
				continue;
				
			if(!isDefined(bot.bot))
				continue;
				
			// Don't check if in last stand or already being handled
			if(isDefined(bot.is_being_unstuck) && bot.is_being_unstuck)
				continue;
				
			if(bot maps\mp\zombies\_zm_laststand::player_is_in_laststand())
				continue;
			
			bot thread check_if_stuck();
		}
	}
}

check_if_stuck()
{
	self endon("death");
	self endon("disconnect");
	
	// Initialize tracking if needed
	if(!isDefined(self.bot.stuck_check_time))
		self.bot.stuck_check_time = 0;
		
	// Only check every 3 seconds per bot
	if(GetTime() < self.bot.stuck_check_time)
		return;
		
	self.bot.stuck_check_time = GetTime() + 3000;
	
	// Initialize position history
	if(!isDefined(self.bot.position_history))
		self.bot.position_history = [];
	
	// Store current position
	current_pos = self.origin;
	self.bot.position_history[self.bot.position_history.size] = current_pos;
	
	// Keep only last 3 positions
	if(self.bot.position_history.size > 3)
	{
		// Shift array - remove oldest
		new_history = [];
		for(i = 1; i < self.bot.position_history.size; i++)
		{
			new_history[new_history.size] = self.bot.position_history[i];
		}
		self.bot.position_history = new_history;
	}
	
	// Need at least 3 positions to determine if stuck
	if(self.bot.position_history.size < 3)
		return;
	
	// Check if bot hasn't moved much in last 6 seconds
	total_movement = 0;
	for(i = 1; i < self.bot.position_history.size; i++)
	{
		dist = Distance(self.bot.position_history[i], self.bot.position_history[i-1]);
		total_movement += dist;
	}
	
	// If moved less than 100 units in 6 seconds, probably stuck
	if(total_movement < 100)
	{
		// Additional validation - check if bot has active goals
		has_goals = self hasgoal("wander") || self hasgoal("revive") || 
		            self hasgoal("flee") || self hasgoal("powerup");
		
		// Only unstuck if bot should be moving but isn't
		if(has_goals)
		{
			self thread attempt_unstuck();
		}
	}
}

attempt_unstuck()
{
	self endon("death");
	self endon("disconnect");
	
	// Prevent multiple unstuck attempts at once
	if(isDefined(self.is_being_unstuck) && self.is_being_unstuck)
		return;
		
	self.is_being_unstuck = true;
	
	// Method 1: Try to find a nearby valid node
	success = self try_node_based_unstuck();
	
	if(!success)
	{
		// Method 2: Try to teleport to host player
		success = self try_teleport_to_player();
	}
	
	// Clear position history on successful unstuck
	if(success)
	{
		self.bot.position_history = [];
	}
	
	wait 1;
	self.is_being_unstuck = undefined;
}

try_node_based_unstuck()
{
	// Find nearby navigation nodes
	nodes = getnodesinradiussorted(self.origin, 300, 0);
	
	if(!isDefined(nodes) || nodes.size == 0)
		return false;
	
	// Try each node until we find a valid one
	foreach(node in nodes)
	{
		if(!isDefined(node) || !isDefined(node.origin))
			continue;
		
		// Validate the node position is safe
		if(is_position_safe(node.origin))
		{
			// Additional check - make sure we're on the ground
			ground_pos = get_ground_position(node.origin);
			
			if(isDefined(ground_pos))
			{
				// Safe to teleport
				self SetOrigin(ground_pos);
				self SetPlayerAngles((0, 0, 0)); // Reset angles
				
				// Clear any stuck goals
				self cancelgoal("flee");
				self cancelgoal("avoid_player");
				
				return true;
			}
		}
	}
	
	return false;
}

try_teleport_to_player()
{
	// Find a valid human player to teleport near
	players = get_players();
	
	if(!isDefined(players) || players.size == 0)
		return false;
	
	valid_player = undefined;
	
	foreach(player in players)
	{
		// Safety checks
		if(!isDefined(player) || player == self)
			continue;
			
		if(player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			continue;
			
		if(!player IsOnGround())
			continue;
			
		valid_player = player;
		break;
	}
	
	if(!isDefined(valid_player))
		return false;
	
	// Try to find a safe position near the player
	nearby_nodes = getnodesinradiussorted(valid_player.origin, 200, 0);
	
	if(!isDefined(nearby_nodes) || nearby_nodes.size == 0)
		return false;
	
	// Find the safest node
	foreach(node in nearby_nodes)
	{
		if(!isDefined(node) || !isDefined(node.origin))
			continue;
		
		// Check if position is safe and visible to player
		if(is_position_safe(node.origin))
		{
			// Make sure it's not too close to player
			dist = Distance(node.origin, valid_player.origin);
			
			if(dist > 100 && dist < 200)
			{
				ground_pos = get_ground_position(node.origin);
				
				if(isDefined(ground_pos))
				{
					// Teleport safely
					self SetOrigin(ground_pos);
					self SetPlayerAngles(VectorToAngles(valid_player.origin - ground_pos));
					
					// Clear stuck goals
					self cancelgoal("flee");
					self cancelgoal("avoid_player");
					
					return true;
				}
			}
		}
	}
	
	return false;
}

is_position_safe(position)
{
	if(!isDefined(position))
		return false;
	
	// Check if position is in a valid playspace
	// Trace from position up and down to ensure it's not in a wall
	
	// Check ceiling (50 units up)
	ceiling_trace = BulletTrace(position, position + (0, 0, 50), false, undefined);
	if(!isDefined(ceiling_trace))
		return false;
	
	// Should hit something above (ceiling/sky)
	if(ceiling_trace["fraction"] >= 1.0)
		return false; // No ceiling found (might be out of bounds)
	
	// Check floor (100 units down)
	floor_trace = BulletTrace(position, position + (0, 0, -100), false, undefined);
	if(!isDefined(floor_trace))
		return false;
	
	// Should hit floor within 100 units
	if(floor_trace["fraction"] >= 1.0)
		return false; // No floor found (void)
	
	// Check if position is inside a solid (trace in all directions)
	directions = [];
	directions[0] = (50, 0, 0);
	directions[1] = (-50, 0, 0);
	directions[2] = (0, 50, 0);
	directions[3] = (0, -50, 0);
	
	open_directions = 0;
	
	foreach(dir in directions)
	{
		trace = BulletTrace(position, position + dir, false, undefined);
		
		if(isDefined(trace) && trace["fraction"] > 0.5)
		{
			open_directions++;
		}
	}
	
	// Need at least 2 open directions (not completely enclosed)
	if(open_directions < 2)
		return false;
	
	return true;
}

get_ground_position(position)
{
	if(!isDefined(position))
		return undefined;
	
	// Trace down to find ground
	trace = BulletTrace(position + (0, 0, 10), position + (0, 0, -200), false, undefined);
	
	if(!isDefined(trace))
		return undefined;
	
	if(trace["fraction"] >= 1.0)
		return undefined; // No ground found
	
	// Return position slightly above ground
	ground_pos = trace["position"] + (0, 0, 5);
	
	return ground_pos;
}