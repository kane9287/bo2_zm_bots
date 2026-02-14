// T6 GSC SOURCE
// Compiler version 0 (prec2)

#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\zombies\_zm_ai_basic;
#include maps\mp\zombies\_zm;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_turned;
#include maps\mp\zombies\_zm_equipment;
#include maps\mp\zombies\_zm_buildables;
#include maps\mp\zombies\_zm_weap_claymore;
#include maps\mp\zombies\_zm_powerups;
#include maps\mp\zombies\_zm_laststand;

zombie_healthbar(pos, dsquared)
{
	if(distancesquared(pos, self.origin) > dsquared)
		return;

	rate = 1;

	if(isdefined(self.maxhealth))
		rate = self.health / self.maxhealth;

	color = (1 - rate, rate, 0);
	text = "" + int(self.health);
	print3d(self.origin + (0, 0, 0), text, color, 1, 0.5, 1);
}

devgui_zombie_healthbar()
{
	level endon("end_game");
	
	while(true)
	{
		if(getdvarint(#"_id_5B45DCAF") == 1)
		{
			lp = get_players()[0];
			zombies = getaispeciesarray("all", "all");

			if(isdefined(zombies))
			{
				foreach(zombie in zombies)
					zombie zombie_healthbar(lp.origin, 360000);
			}
		}

		wait 0.05;
	}
}

init_zombie_healthbar()
{
	if(!isdefined(level.zombie_healthbar_dvar))
	{
		setdvar("_id_5B45DCAF", 1);
		level.zombie_healthbar_dvar = 1;
	}
	
	level thread devgui_zombie_healthbar();
}

on_player_connect()
{
	level endon("end_game");
	
	for(;;)
	{
		level waittill("connected", player);
		player thread on_player_spawned();
	}
}

on_player_spawned()
{
	self endon("disconnect");
	
	for(;;)
	{
		self waittill("spawned_player");
		wait(1);

		self thread init_player_hud();
		
		if(!isdefined(level.healthbar_initialized))
		{
			level.healthbar_initialized = true;
			level thread init_zombie_healthbar();
		}
	}
}

init_player_hud()
{
	self endon("disconnect");
	level endon("game_ended");

	if(!isDefined(self.hud_initialized))
	{
		// Health Display
		self.hud_health_text = newClientHudElem(self);
		self.hud_health_text.alignX = "left";
		self.hud_health_text.alignY = "bottom";
		self.hud_health_text.horzAlign = "left";
		self.hud_health_text.vertAlign = "bottom";
		self.hud_health_text.x = 50;
		self.hud_health_text.y = -50;
		self.hud_health_text.fontScale = 1.5;
		self.hud_health_text.font = "objective";
		self.hud_health_text.color = (1, 1, 1);
		self.hud_health_text.alpha = 1;

		// Position Display
		self.hud_position_text = newClientHudElem(self);
		self.hud_position_text.alignX = "left";
		self.hud_position_text.alignY = "bottom";
		self.hud_position_text.horzAlign = "left";
		self.hud_position_text.vertAlign = "bottom";
		self.hud_position_text.x = 50;
		self.hud_position_text.y = -80;
		self.hud_position_text.fontScale = 1.2;
		self.hud_position_text.font = "default";
		self.hud_position_text.color = (1, 1, 1);
		self.hud_position_text.alpha = 1;

		self.hud_initialized = true;
		self thread update_player_hud();
	}
}

update_player_hud()
{
	self endon("disconnect");
	level endon("game_ended");

	while(true)
	{
		health_str = "HP: " + self.health;
		if(isDefined(self.hud_health_text))
			self.hud_health_text setText(health_str);

		// Position display commented out to prevent configstring overflow
		// pos_str = "XYZ: " + int(self.origin[0]) + ", " + int(self.origin[1]) + ", " + int(self.origin[2]);
		// if(isDefined(self.hud_position_text))
		//    self.hud_position_text setText(pos_str);

		wait 0.1;
	}
}

init()
{
	level thread on_player_connect();
}

// Custom implementation of NodeVisible function
NodeVisible(origin1, origin2)
{
	// Add small vertical offset to account for ground level
	origin1 = origin1 + (0, 0, 10);
	origin2 = origin2 + (0, 0, 10);
	
	// Check line of sight between points
	return SightTracePassed(origin1, origin2, false, undefined);
}

// Helper function to check if array contains a value (for origins)
array_contains(array, value)
{
	if(!isDefined(array) || !array.size)
		return false;
		
	foreach(item in array)
	{
		// Compare origins with a small tolerance
		if(Distance(item, value) < 10)
			return true;
	}
	
	return false;
}

// Initialize bot on spawn
bot_spawn_init()
{
	if(!isDefined(self.bot))
		self.bot = SpawnStruct();
		
	// Initialize threat tracking
	self.bot.threat = SpawnStruct();
	self.bot.threat.entity = undefined;
	self.bot.threat.position = (0, 0, 0);
	self.bot.threat.time_first_sight = 0;
	self.bot.threat.time_recent_sight = 0;
	self.bot.threat.time_aim_correct = 0;
	self.bot.threat.time_aim_interval = 50;
	self.bot.threat.dot = 0;
	self.bot.threat.aim_target = (0, 0, 0);
	
	// Initialize timing variables
	self.bot.entity_cache_time = 0;
	self.bot.last_follow_pos = (0, 0, 0);
	self.bot.last_knife_time = 0;
	self.bot.last_evasion_time = 0;
	self.bot.revive_check_time = 0;
	self.bot.powerup_check_time = 0;
	self.bot.formation_check_time = 0;
	self.bot.trap_check_time = 0;
	self.bot.kite_check_time = 0;
	self.bot.tactical_pos_time = 0;
	self.bot.fire_coord_time = 0;
	self.bot.last_distance_check = 0;
	self.bot.last_strafe_time = 0;
	
	// Initialize cached data
	self.bot.cached_zombies = [];
	
	// Mark as bot
	self.is_bot = true;
}

// Check if bot is blocking other players
bot_check_player_blocking()
{
	self endon("disconnect");
	self endon("death");
	level endon("end_game");
	
	while(!isDefined(self.bot))
		wait 0.05;
		
	while(true)
	{
		wait 1;
		
		if(!self.is_bot)
			continue;
			
		// Check if bot is blocking human players
		players = get_players();
		
		foreach(player in players)
		{
			if(player == self)
				continue;
				
			// Skip other bots
			if(isDefined(player.is_bot) && player.is_bot)
				continue;
				
			// Check distance to player
			dist_sq = DistanceSquared(self.origin, player.origin);
			
			// If very close to human player (within 60 units)
			if(dist_sq < 3600) // 60^2
			{
				// Move away from player
				direction = VectorNormalize(self.origin - player.origin);
				move_pos = self.origin + (direction * 150);
				
				// Check if position is valid
				if(FindPath(self.origin, move_pos, undefined, 0, 1))
				{
					// Cancel lower priority goals
					if(self hasgoal("wander"))
						self cancelgoal("wander");
					if(self hasgoal("tactical"))
						self cancelgoal("tactical");
						
					// Add movement goal
					self AddGoal(move_pos, 50, 2, "avoid_blocking");
				}
			}
		}
	}
}

// Get nearest navigation node to a given origin
bot_nearest_node(origin)
{
	if(!isDefined(origin))
		return undefined;
		
	nodes = GetNodesInRadius(origin, 256, 0);
	
	if(!isDefined(nodes) || nodes.size == 0)
		return undefined;
		
	closest_node = undefined;
	closest_dist_sq = 999999;
	
	foreach(node in nodes)
	{
		if(!isDefined(node) || !isDefined(node.origin))
			continue;
			
		dist_sq = DistanceSquared(origin, node.origin);
		
		if(dist_sq < closest_dist_sq)
		{
			closest_dist_sq = dist_sq;
			closest_node = node;
		}
	}
	
	return closest_node;
}

// Bot powerup pickup logic
bot_pickup_powerup()
{
	if(!isDefined(self.bot))
		return;
		
	// Check every 1 second
	if(isDefined(self.bot.powerup_check_time) && GetTime() < self.bot.powerup_check_time)
		return;
		
	self.bot.powerup_check_time = GetTime() + 1000;
	
	// Don't pickup during laststand
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return;
		
	// Find active powerups
	powerups = level.active_powerups;
	
	if(!isDefined(powerups) || powerups.size == 0)
		return;
		
	closest_powerup = undefined;
	closest_dist_sq = 160000; // 400^2
	
	foreach(powerup in powerups)
	{
		if(!isDefined(powerup) || !isDefined(powerup.origin))
			continue;
			
		// Skip if powerup is being grabbed
		if(isDefined(powerup.claimed) && powerup.claimed)
			continue;
			
		dist_sq = DistanceSquared(self.origin, powerup.origin);
		
		if(dist_sq < closest_dist_sq)
		{
			// Check if reachable
			if(FindPath(self.origin, powerup.origin, undefined, 0, 1))
			{
				closest_dist_sq = dist_sq;
				closest_powerup = powerup;
			}
		}
	}
	
	// Navigate to powerup
	if(isDefined(closest_powerup))
	{
		// Close enough to pick up
		if(closest_dist_sq < 10000) // 100^2
		{
			if(self hasgoal("powerup"))
				self cancelgoal("powerup");
				
			// Move towards powerup
			self lookat(closest_powerup.origin);
		}
		// Too far, add goal to move there
		else if(!self hasgoal("powerup") || DistanceSquared(self GetGoal("powerup"), closest_powerup.origin) > 2500)
		{
			self AddGoal(closest_powerup.origin, 64, 2, "powerup");
		}
	}
	else if(self hasgoal("powerup"))
	{
		// No powerups nearby, cancel goal
		self cancelgoal("powerup");
	}
}
