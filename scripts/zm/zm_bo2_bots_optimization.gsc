#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;

// PRIORITY 1 OPTIMIZATIONS - Global cached weapon tiers (defined once instead of repeatedly)
get_tier1_weapons()
{
	return array("raygun_", "thunder", "wave_gun", "mark2", "tesla", "staff");
}

get_tier2_weapons()
{
	return array("galil", "an94", "hamr", "rpd", "lsat", "dsr50", "scar", "fal");
}

get_tier3_weapons()
{
	return array("mp5k", "pdw57", "mtar", "mp40", "ak74u", "qcw05", "msmc");
}

get_tier4_weapons()
{
	return array("m14", "870mcs", "r870", "olympia", "fnfal", "ksg");
}

// PRIORITY 1: Shoot while downed - NEW FEATURE
bot_combat_laststand()
{
	self endon("death");
	self endon("disconnect");
	self endon("player_revived");
	
	// Wait a moment for laststand to initialize
	wait 0.5;
	
	while(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		// Get closest zombie
		zombies = getaispeciesarray(level.zombie_team, "all");
		if(!isDefined(zombies) || zombies.size == 0)
		{
			wait 0.1;
			continue;
		}
		
		// Find closest visible zombie
		closest_zombie = undefined;
		closest_dist = 99999;
		
		foreach(zombie in zombies)
		{
			if(!isDefined(zombie) || !isalive(zombie))
				continue;
				
			dist = Distance(self.origin, zombie.origin);
			if(dist < closest_dist && dist < 500)
			{
				if(self botsighttracepassed(zombie))
				{
					closest_dist = dist;
					closest_zombie = zombie;
				}
			}
		}
		
		// Shoot at closest zombie
		if(isDefined(closest_zombie))
		{
			// Look at zombie
			self lookat(closest_zombie.origin + (0, 0, 40));
			
			// Allow shooting
			self allowattack(1);
			
			wait 0.1;
		}
		else
		{
			self allowattack(0);
			wait 0.2;
		}
	}
	
	// Clean up when revived or dead
	self allowattack(0);
	self clearlookat();
}

// PRIORITY 2: Enhanced threat calculation with player protection
bot_calculate_threat_score_enhanced(zombie)
{
	if(!isDefined(zombie) || !isalive(zombie))
		return 0;
		
	score = 0;
	dist = Distance(self.origin, zombie.origin);
	
	// Distance priority (closer = higher threat)
	score += (1000 - dist) * 2;
	
	// NEW: Prioritize zombies attacking human players (MUCH higher priority)
	players = get_players();
	foreach(player in players)
	{
		if(!isDefined(player) || !isalive(player))
			continue;
			
		// Prioritize zombies near human players
		if(!isDefined(player.bot) && Distance(player.origin, zombie.origin) < 150)
		{
			score += 800; // VERY high priority for zombies near human players
		}
		
		// Zombies attacking downed teammates (any player)
		if(Distance(player.origin, zombie.origin) < 100 && 
		   player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			score += 500; // High priority for zombies near downed players
		}
	}
		
	// NEW: Prioritize zombies in human player's line of fire
	human_player = get_human_player();
	if(isDefined(human_player))
	{
		player_forward = AnglesToForward(human_player GetPlayerAngles());
		to_zombie = VectorNormalize(zombie.origin - human_player.origin);
		dot = VectorDot(player_forward, to_zombie);
		
		// Zombie is in front of human player (they're looking at it)
		if(dot > 0.8 && Distance(human_player.origin, zombie.origin) < 400)
			score += 400;
	}
	
	// Special zombie types (Brutus, Panzers, etc.)
	if(isDefined(zombie.is_brutus) && zombie.is_brutus)
		score += 600;
	if(isDefined(zombie.is_mechz) && zombie.is_mechz)
		score += 600;
		
	return score;
}

// Helper to get human player
get_human_player()
{
	players = get_players();
	foreach(player in players)
	{
		if(!isDefined(player.bot) && isalive(player))
			return player;
	}
	return undefined;
}

// PRIORITY 2: Improved revive with danger assessment
bot_assess_revive_danger(teammate)
{
	if(!isDefined(teammate))
		return 999;
		
	zombies = getaispeciesarray(level.zombie_team, "all");
	danger = 0;
	
	foreach(zombie in zombies)
	{
		if(!isDefined(zombie) || !isalive(zombie))
			continue;
			
		dist = Distance(zombie.origin, teammate.origin);
		if(dist < 300)
			danger++;
		if(dist < 150)
			danger += 2; // Very close zombies count more
		if(dist < 80)
			danger += 3; // Extremely dangerous
	}
	
	return danger;
}

// Covering fire while reviving
bot_cover_while_reviving(teammate)
{
	self endon("death");
	self endon("disconnect");
	teammate endon("player_revived");
	
	// Provide covering fire for ~0.75 seconds
	for(i = 0; i < 10; i++)
	{
		// Find closest zombie to downed teammate
		zombies = getaispeciesarray(level.zombie_team, "all");
		closest = undefined;
		closest_dist = 99999;
		
		foreach(zombie in zombies)
		{
			if(!isDefined(zombie) || !isalive(zombie))
				continue;
				
			dist = Distance(zombie.origin, teammate.origin);
			if(dist < closest_dist && dist < 400)
			{
				closest_dist = dist;
				closest = zombie;
			}
		}
		
		// Shoot at closest threat
		if(isDefined(closest) && self botsighttracepassed(closest))
		{
			self lookat(closest.origin + (0, 0, 40));
			self allowattack(1);
		}
		
		wait 0.08;
	}
	
	self allowattack(0);
}

// PRIORITY 2: Player support - stay in support range
bot_support_human_player()
{
	if(!isDefined(self.bot.support_check_time) || GetTime() > self.bot.support_check_time)
	{
		self.bot.support_check_time = GetTime() + 3000;
		
		human = get_human_player();
		if(!isDefined(human))
			return;
			
		dist = Distance(self.origin, human.origin);
		
		// Stay within support range (200-400 units)
		if(dist > 500)
		{
			// Too far - move closer to human
			if(!self hasgoal("support"))
				self AddGoal(human.origin, 200, 1, "support");
		}
		else if(dist < 120)
		{
			// Too close - give space
			if(self hasgoal("support"))
				self cancelgoal("support");
		}
		else
		{
			// Good distance - update goal if needed
			if(self hasgoal("support"))
			{
				// Update goal position to follow player
				if(Distance(self GetGoal("support"), human.origin) > 150)
				{
					self cancelgoal("support");
					self AddGoal(human.origin, 200, 1, "support");
				}
			}
		}
		
		// Watch human's back (look in opposite direction)
		if(dist > 120 && dist < 400 && !isDefined(self.bot.threat.entity))
		{
			human_angles = human GetPlayerAngles();
			human_forward = AnglesToForward(human_angles);
			
			// Bot looks backwards relative to human (180 degrees)
			bot_look_pos = human.origin - (human_forward * 250);
			self lookat(bot_look_pos + (0, 0, 50));
		}
	}
}

// PRIORITY 1: Cleanup on death/disconnect
bot_cleanup_on_death()
{
	self waittill_any("death", "disconnect");
	
	// Clear cached zombies
	if(isDefined(self.bot.cached_zombies))
		self.bot.cached_zombies = undefined;
		
	// Clear all goals
	goal_names = array("flee", "revive", "powerup", "boxBuy", "boxGrab", "papBuy", 
	                    "weaponBuy", "doorBuy", "debrisClear", "panic", "spacing", 
	                    "strafe", "kiting", "spread", "support", "tactical", "ammoBuy", "generator");
					   
	foreach(goal in goal_names)
	{
		if(self hasgoal(goal))
			self cancelgoal(goal);
	}
}