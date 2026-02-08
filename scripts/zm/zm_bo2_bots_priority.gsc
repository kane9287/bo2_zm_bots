// zm_bo2_bots_priority.gsc
// Priority system for perks and powerups - gives human players first dibs
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_powerups;

init()
{
	// Initialize priority tracking
	if(!isDefined(level.perk_machine_queue))
		level.perk_machine_queue = [];
		
	if(!isDefined(level.powerup_spawn_times))
		level.powerup_spawn_times = [];
		
	level thread monitor_powerup_spawns();
}

// Monitor when powerups spawn to give players priority window
monitor_powerup_spawns()
{
	level endon("end_game");
	
	flag_wait("initial_blackscreen_passed");
	wait 2;
	
	while(true)
	{
		level waittill("powerup_dropped", powerup);
		
		if(!isDefined(powerup) || !isDefined(powerup.origin))
			continue;
		
		// Store spawn time for this powerup location
		powerup_data = spawnstruct();
		powerup_data.origin = powerup.origin;
		powerup_data.spawn_time = GetTime();
		powerup_data.powerup = powerup;
		
		level.powerup_spawn_times[level.powerup_spawn_times.size] = powerup_data;
		
		// Clean up old entries (over 30 seconds old)
		level thread cleanup_old_powerup_entries();
	}
}

cleanup_old_powerup_entries()
{
	if(!isDefined(level.powerup_spawn_times) || level.powerup_spawn_times.size == 0)
		return;
		
	current_time = GetTime();
	new_array = [];
	
	foreach(entry in level.powerup_spawn_times)
	{
		// Keep entries less than 30 seconds old
		if(isDefined(entry) && isDefined(entry.spawn_time))
		{
			if((current_time - entry.spawn_time) < 30000)
			{
				new_array[new_array.size] = entry;
			}
		}
	}
	
	level.powerup_spawn_times = new_array;
}

// Check if bot should wait before picking up powerup
bot_should_wait_for_powerup(powerup_origin)
{
	if(!isDefined(powerup_origin))
		return false;
	
	if(!isDefined(level.powerup_spawn_times) || level.powerup_spawn_times.size == 0)
		return false;
	
	// Find matching powerup entry
	foreach(entry in level.powerup_spawn_times)
	{
		if(!isDefined(entry) || !isDefined(entry.origin))
			continue;
			
		// Check if this is the same powerup (within 50 units)
		if(Distance(entry.origin, powerup_origin) < 50)
		{
			// Calculate time since spawn
			time_since_spawn = GetTime() - entry.spawn_time;
			
			// Give players 3 second priority window (adjustable)
			player_priority_window = 3000;
			
			// Check if any human players are nearby
			players = get_players();
			human_nearby = false;
			
			foreach(player in players)
			{
				// Skip bots
				if(!isDefined(player) || isDefined(player.bot))
					continue;
					
				// Check if human player is close to powerup
				if(Distance(player.origin, powerup_origin) < 500)
				{
					human_nearby = true;
					break;
				}
			}
			
			// If within priority window and human is nearby, wait
			if(time_since_spawn < player_priority_window && human_nearby)
			{
				return true; // Bot should wait
			}
			
			return false; // Priority window expired or no humans nearby
		}
	}
	
	return false; // Powerup not in tracking system, safe to pick up
}

// Check if bot should use a perk machine
bot_can_use_perk_machine(machine_origin, perk_type)
{
	if(!isDefined(machine_origin) || !isDefined(perk_type))
		return true; // Default to allowing
	
	// Initialize queue if needed
	if(!isDefined(level.perk_machine_queue))
		level.perk_machine_queue = [];
	
	// Check if a human player is already at this machine
	players = get_players();
	
	foreach(player in players)
	{
		// Skip bots and invalid players
		if(!isDefined(player) || isDefined(player.bot))
			continue;
			
		// Check if human is very close to the machine (within 100 units)
		if(Distance(player.origin, machine_origin) < 100)
		{
			return false; // Human has priority
		}
	}
	
	// Check queue for this machine
	queue_key = get_perk_queue_key(machine_origin);
	
	if(!isDefined(level.perk_machine_queue[queue_key]))
	{
		// No queue, safe to use
		return true;
	}
	
	queue_entry = level.perk_machine_queue[queue_key];
	
	// Check if queue entry is stale (over 10 seconds old)
	if(isDefined(queue_entry.time) && (GetTime() - queue_entry.time) > 10000)
	{
		// Clear stale entry
		level.perk_machine_queue[queue_key] = undefined;
		return true;
	}
	
	// Check if the queued entity is this bot
	if(isDefined(queue_entry.entity) && queue_entry.entity == self)
	{
		return true; // This bot has the slot
	}
	
	// Check if queued entity is still valid
	if(!isDefined(queue_entry.entity) || !isAlive(queue_entry.entity))
	{
		// Clear invalid entry
		level.perk_machine_queue[queue_key] = undefined;
		return true;
	}
	
	return false; // Someone else is using this machine
}

// Reserve a perk machine for bot use
bot_reserve_perk_machine(machine_origin)
{
	if(!isDefined(machine_origin))
		return false;
	
	queue_key = get_perk_queue_key(machine_origin);
	
	// Only reserve if not already reserved by someone else
	if(isDefined(level.perk_machine_queue[queue_key]))
	{
		entry = level.perk_machine_queue[queue_key];
		
		// If reserved by this bot or stale entry, can reserve
		if(isDefined(entry.entity) && entry.entity != self)
		{
			// Check if stale
			if(isDefined(entry.time) && (GetTime() - entry.time) < 10000)
			{
				return false; // Recently reserved by someone else
			}
		}
	}
	
	// Create reservation
	reservation = spawnstruct();
	reservation.entity = self;
	reservation.time = GetTime();
	reservation.origin = machine_origin;
	
	level.perk_machine_queue[queue_key] = reservation;
	
	return true;
}

// Release perk machine reservation
bot_release_perk_machine(machine_origin)
{
	if(!isDefined(machine_origin))
		return;
	
	queue_key = get_perk_queue_key(machine_origin);
	
	if(isDefined(level.perk_machine_queue[queue_key]))
	{
		entry = level.perk_machine_queue[queue_key];
		
		// Only release if this bot owns it
		if(isDefined(entry.entity) && entry.entity == self)
		{
			level.perk_machine_queue[queue_key] = undefined;
		}
	}
}

// Generate unique key for perk machine location
get_perk_queue_key(origin)
{
	if(!isDefined(origin))
		return "invalid";
	
	// Round to nearest 10 to handle slight position variations
	x = int(origin[0] / 10) * 10;
	y = int(origin[1] / 10) * 10;
	z = int(origin[2] / 10) * 10;
	
	key = x + "_" + y + "_" + z;
	
	return key;
}

// Get number of human players in game
get_human_player_count()
{
	players = get_players();
	count = 0;
	
	foreach(player in players)
	{
		// Count only non-bot players
		if(isDefined(player) && !isDefined(player.bot))
		{
			count++;
		}
	}
	
	return count;
}

// Check if powerup is high priority that bots should avoid
is_high_priority_powerup(powerup)
{
	if(!isDefined(powerup) || !isDefined(powerup.powerup_name))
		return false;
	
	// These powerups should always be left for human players if nearby
	high_priority = array(
		"bonus_points_player",  // Personal points
		"free_perk",            // Free perk
		"fire_sale"            // Fire sale
	);
	
	foreach(priority_type in high_priority)
	{
		if(powerup.powerup_name == priority_type)
		{
			return true;
		}
	}
	
	return false;
}