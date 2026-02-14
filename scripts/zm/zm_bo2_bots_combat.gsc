#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include scripts\zm\zm_bo2_bots;
#include scripts\zm\zm_bo2_bots_utility;

bot_combat_think( damage, attacker, direction )
{
	self allowattack( 0 );
	self pressads( 0 );
	
	// Initialize AI enhancement variables
	if(!isDefined(self.bot.entity_cache_time))
		self.bot.entity_cache_time = 0;
	if(!isDefined(self.bot.last_follow_pos))
		self.bot.last_follow_pos = (0,0,0);
	if(!isDefined(self.bot.last_knife_time))
		self.bot.last_knife_time = 0;
	if(!isDefined(self.bot.last_evasion_time))
		self.bot.last_evasion_time = 0;
	
	for ( ;; )
	{
		if ( !bot_can_do_combat() )
		{
			return;
		}
		if(self atgoal("flee"))
			self cancelgoal("flee");
			
		// ENHANCED: Check if bot is overwhelmed and needs to panic
		self bot_check_overwhelmed();
		
		// ENHANCED: Continuous evasive movement (all rounds)
		self bot_maintain_safe_distance();
		
		// ENHANCED: Better flee logic with increased trigger distance
		if(Distance(self.origin, self.bot.threat.position) <= 180 || isdefined(damage))
		{
			nodes = getnodesinradiussorted( self.origin, 1024, 256, 512 );
			nearest = bot_nearest_node(self.origin);
			if ( isDefined( nearest ) && !self hasgoal( "flee" ) )
			{
				foreach ( node in nodes )
				{
					if ( !NodeVisible( nearest.origin, node.origin ) && FindPath(self.origin, node.origin, undefined, 0, 1) )
					{
						self addgoal( node.origin, 24, 4, "flee" );
						break;
					}
				}
			}
		}
		if(self GetCurrentWeapon() == "none")
			continue; // FIXED: Changed from return to continue
			
		// Use cached zombie list for better performance
		sight = self bot_best_enemy_enhanced();
		if(!isdefined(self.bot.threat.entity))
			continue; // FIXED: Changed from return to continue
		if ( threat_dead() )
		{
			self bot_combat_dead();
			continue; // FIXED: Changed from return to continue
		}
		
		// MERGED: Fire coordination to prevent redundant targeting
		self bot_coordinate_fire();
		
		//ADD OTHER COMBAT TASKS HERE.
		self bot_combat_main();
		self bot_pickup_powerup();

		// Initialize door coordination and mystery box tracking variables if not defined
		if(!isDefined(level.door_being_opened))
			level.door_being_opened = false;
			
		if(!isDefined(level.mystery_box_teddy_locations))
			level.mystery_box_teddy_locations = [];
			
		// Safe door opening - prevents multiple bots from trying to open the same door
		self bot_safely_interact_with_doors();
			
		// Mystery box safety check - prevents using teddy bear boxes
		self bot_safely_use_mystery_box();
		
		if(is_true(level.using_bot_revive_logic))
		{
			self bot_revive_teammates();
		}
		
		// Maintain formation with other bots
		self bot_maintain_formation();
		
		// NEW: Strafe while in combat
		self bot_combat_strafe();
		
		// MERGED: Use tactical positioning when not in immediate danger
		self bot_use_tactical_positioning();
		
		wait 0.05; // OPTIMIZED: Changed from 0.02 to 0.05 for better performance
	}
}

// ENHANCED: Check if bot is overwhelmed by zombies (lowered threshold)
bot_check_overwhelmed()
{
	// Count nearby zombies using cached list
	zombies = self bot_get_cached_zombies();
	nearby_count = 0;
	very_close_count = 0;
	
	foreach(zombie in zombies)
	{
		dist = Distance(self.origin, zombie.origin);
		if(dist < 250)
			nearby_count++;
		if(dist < 120)
			very_close_count++;
	}
	
	// ENHANCED: Trigger panic at 3+ zombies (was 5+) or if 2+ are very close
	if(nearby_count >= 3 || very_close_count >= 2)
	{
		self.bot.panic_mode = true;
		self.bot.panic_time = GetTime() + 2500;
		
		// Find furthest node with better range
		nodes = getnodesinradiussorted(self.origin, 768, 0);
		if(nodes.size > 0)
		{
			// Take farthest node
			escape_node = nodes[nodes.size - 1];
			self AddGoal(escape_node.origin, 50, 5, "panic"); // Highest priority
		}
	}
	else if(isDefined(self.bot.panic_mode) && GetTime() > self.bot.panic_time)
	{
		self.bot.panic_mode = undefined;
		self cancelgoal("panic");
	}
}

// NEW: Maintain safe distance from zombies at all times
bot_maintain_safe_distance()
{
	// Check periodically
	if(isDefined(self.bot.last_distance_check) && GetTime() < self.bot.last_distance_check)
		return;
		
	self.bot.last_distance_check = GetTime() + 500; // Check every 0.5 seconds
	
	zombies = self bot_get_cached_zombies();
	if(!isDefined(zombies) || zombies.size == 0)
		return;
		
	// Find closest zombie
	closest_zombie = undefined;
	closest_dist = 99999;
	
	foreach(zombie in zombies)
	{
		dist = Distance(self.origin, zombie.origin);
		if(dist < closest_dist)
		{
			closest_dist = dist;
			closest_zombie = zombie;
		}
	}
	
	// ENHANCED: Maintain 200+ unit distance from nearest zombie
	if(isDefined(closest_zombie) && closest_dist < 200)
	{
		// Calculate direction away from zombie
		escape_dir = VectorNormalize(self.origin - closest_zombie.origin);
		
		// Move away
		escape_pos = self.origin + (escape_dir * 250);
		
		// Validate path
		if(FindPath(self.origin, escape_pos, undefined, 0, 1))
		{
			if(!self hasgoal("spacing") || Distance(self GetGoal("spacing"), escape_pos) > 100)
			{
				self AddGoal(escape_pos, 50, 3, "spacing"); // High priority
			}
		}
	}
	else if(closest_dist >= 200 && self hasgoal("spacing"))
	{
		self cancelgoal("spacing");
	}
}

// NEW: Strafe movement during combat
bot_combat_strafe()
{
	if(!isDefined(self.bot.threat.entity))
		return;
		
	// Only strafe periodically
	if(isDefined(self.bot.last_strafe_time) && GetTime() < self.bot.last_strafe_time)
		return;
		
	self.bot.last_strafe_time = GetTime() + randomintrange(800, 1500);
	
	enemy = self.bot.threat.entity;
	dist = Distance(self.origin, enemy.origin);
	
	// Only strafe if enemy is medium-close range
	if(dist > 100 && dist < 400)
	{
		// Get direction to enemy
		to_enemy = VectorNormalize(enemy.origin - self.origin);
		
		// Get perpendicular direction (left or right)
		strafe_dir = (-to_enemy[1], to_enemy[0], 0);
		
		// Randomly choose left or right
		if(randomfloat(1) > 0.5)
			strafe_dir = -strafe_dir;
			
		// Calculate strafe position
		strafe_pos = self.origin + (strafe_dir * 150);
		
		// Validate path exists
		if(FindPath(self.origin, strafe_pos, undefined, 0, 1))
		{
			self AddGoal(strafe_pos, 50, 2, "strafe");
		}
	}
}

// NEW: Cache zombie list for performance
bot_get_cached_zombies()
{
	if(!isDefined(self.bot.entity_cache_time) || GetTime() > self.bot.entity_cache_time)
	{
		// Update cache every 0.5 seconds instead of every frame
		self.bot.cached_zombies = getaispeciesarray(level.zombie_team, "all");
		self.bot.entity_cache_time = GetTime() + 500;
	}
	
	return self.bot.cached_zombies;
}

// NEW: Enhanced enemy selection with threat scoring
bot_best_enemy_enhanced()
{
	enemies = self bot_get_cached_zombies();
	
	if(!isDefined(enemies) || enemies.size == 0)
		return 0;
		
	best_enemy = undefined;
	best_score = -1;
	
	foreach(enemy in enemies)
	{
		if(threat_should_ignore(enemy))
			continue;
			
		if(!self botsighttracepassed(enemy))
			continue;
			
		// Calculate threat score
		score = bot_calculate_threat_score(enemy);
		
		if(score > best_score)
		{
			best_score = score;
			best_enemy = enemy;
		}
	}
	
	if(isDefined(best_enemy))
	{
		self.bot.threat.entity = best_enemy;
		self.bot.threat.time_first_sight = GetTime();
		self.bot.threat.time_recent_sight = GetTime();
		self.bot.threat.dot = bot_dot_product(best_enemy.origin);
		self.bot.threat.position = best_enemy.origin;
		return 1;
	}
	
	return 0;
}

// NEW: Calculate threat priority score
bot_calculate_threat_score(zombie)
{
	score = 0;
	dist = Distance(self.origin, zombie.origin);
	
	// Distance priority (closer = higher threat)
	score += (1000 - dist) * 2;
	
	// Special zombie types (if your mod has them)
	if(isDefined(zombie.is_brutus) && zombie.is_brutus)
		score += 500;
	
	// Zombies attacking downed teammates
	players = get_players();
	foreach(player in players)
	{
		if(Distance(player.origin, zombie.origin) < 100 && 
		   player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			score += 300;
	}
	
	// MERGED: Zombies near human player (higher priority)
	human = get_human_player();
	if(isDefined(human))
	{
		dist_to_human = Distance(human.origin, zombie.origin);
		if(dist_to_human < 150)
			score += 400; // High priority to protect human
		else if(dist_to_human < 300)
			score += 200;
	}
	
	return score;
}

// MERGED: Fire coordination - prevents multiple bots targeting same zombie
bot_coordinate_fire()
{
	if(!isDefined(self.bot.fire_coord_time) || GetTime() > self.bot.fire_coord_time)
	{
		self.bot.fire_coord_time = GetTime() + 1500;
		
		// Check if other bots are targeting the same enemy
		if(!isDefined(self.bot.threat.entity))
			return;
			
		my_target = self.bot.threat.entity;
		redundant_count = 0;
		
		// Count how many other bots are shooting this zombie
		foreach(player in get_players())
		{
			if(player == self || !isDefined(player.bot))
				continue;
				
			if(isDefined(player.bot.threat.entity) && 
			   player.bot.threat.entity == my_target)
				redundant_count++;
		}
		
		// If 2+ bots already targeting this zombie, find different target
		if(redundant_count >= 2)
		{
			zombies = getaispeciesarray(level.zombie_team, "all");
			best_alternate = undefined;
			best_score = -1;
			
			foreach(zombie in zombies)
			{
				if(zombie == my_target)
					continue;
					
				if(!self botsighttracepassed(zombie))
					continue;
					
				// Check if less contested
				contention = bot_get_target_contention(zombie);
				
				if(contention < 2)
				{
					// Calculate threat score
					score = bot_calculate_threat_score(zombie);
					
					// Prefer less contested targets
					score += (2 - contention) * 200;
					
					if(score > best_score)
					{
						best_score = score;
						best_alternate = zombie;
					}
				}
			}
			
			// Switch to alternate target if found
			if(isDefined(best_alternate))
			{
				self.bot.threat.entity = best_alternate;
				self.bot.threat.position = best_alternate.origin;
				self.bot.threat.time_first_sight = GetTime();
			}
		}
	}
}

// MERGED: Check how many bots are targeting a specific zombie
bot_get_target_contention(zombie)
{
	bot_count = 0;
	
	foreach(player in get_players())
	{
		if(!isDefined(player.bot) || player == self)
			continue;
			
		if(isDefined(player.bot.threat.entity) && 
		   player.bot.threat.entity == zombie)
			bot_count++;
	}
	
	return bot_count;
}

// MERGED: Tactical positioning - finds chokepoints and cover
bot_use_tactical_positioning()
{
	if(!isDefined(self.bot.tactical_pos_time) || GetTime() > self.bot.tactical_pos_time)
	{
		self.bot.tactical_pos_time = GetTime() + 3000; // Check every 3 seconds
		
		// Skip if in combat or doing important tasks
		if(isDefined(self.bot.threat.entity) || 
		   self hasgoal("revive") || 
		   self hasgoal("panic") ||
		   self hasgoal("flee"))
			return;
			
		// Find advantageous positions (corners, doorways, chokepoints)
		nodes = GetNodesInRadius(self.origin, 450, 0);
		
		if(!isDefined(nodes) || nodes.size == 0)
			return;
			
		best_node = undefined;
		best_score = 40; // Minimum threshold
		
		foreach(node in nodes)
		{
			score = bot_evaluate_tactical_position(node);
			if(score > best_score)
			{
				best_score = score;
				best_node = node;
			}
		}
		
		// Move to tactical position if found
		if(isDefined(best_node))
		{
			if(!self hasgoal("tactical") || Distance(self GetGoal("tactical"), best_node.origin) > 100)
			{
				self cancelgoal("tactical");
				self AddGoal(best_node.origin, 50, 1, "tactical"); // Low priority
			}
		}
	}
}

// MERGED: Evaluate tactical value of a position
bot_evaluate_tactical_position(node)
{
	if(!isDefined(node) || !isDefined(node.origin))
		return 0;
		
	score = 0;
	
	// Check zombie approach angles (look for funnel points)
	zombies = getaispeciesarray(level.zombie_team, "all");
	approach_angles = [];
	nearby_zombie_count = 0;
	
	foreach(zombie in zombies)
	{
		if(!isDefined(zombie) || !isalive(zombie))
			continue;
			
		dist = Distance(node.origin, zombie.origin);
		if(dist < 600)
		{
			nearby_zombie_count++;
			angle_to_zombie = VectorToAngles(zombie.origin - node.origin)[1];
			approach_angles[approach_angles.size] = angle_to_zombie;
		}
	}
	
	// Prefer positions where zombies come from limited angles (chokepoints)
	if(approach_angles.size > 2)
	{
		angle_spread = bot_calculate_angle_spread(approach_angles);
		
		// Narrow angle spread = good funnel point
		if(angle_spread < 90)
			score += 120; // Excellent chokepoint
		else if(angle_spread < 150)
			score += 60; // Good funnel
	}
	
	// Near human player (within support range but not too close)
	human = get_human_player();
	if(isDefined(human))
	{
		dist_to_human = Distance(node.origin, human.origin);
		
		// Optimal support distance: 200-400 units
		if(dist_to_human > 200 && dist_to_human < 400)
			score += 80;
		else if(dist_to_human > 150 && dist_to_human < 500)
			score += 40;
		else if(dist_to_human < 100)
			score -= 50; // Too close to player
	}
	
	// Prefer elevated positions slightly
	height_diff = node.origin[2] - self.origin[2];
	if(height_diff > 20 && height_diff < 100)
		score += 30;
	
	// Distance from current position (don't move too far)
	dist_from_current = Distance(node.origin, self.origin);
	if(dist_from_current > 300)
		score -= 20; // Prefer closer positions
	
	// Check if position has cover nearby (corners)
	if(bot_has_nearby_cover(node))
		score += 50;
	
	return score;
}

// MERGED: Calculate angle spread to detect funnel points
bot_calculate_angle_spread(angles)
{
	if(!isDefined(angles) || angles.size < 2)
		return 360;
		
	min_angle = 360;
	max_angle = 0;
	
	foreach(angle in angles)
	{
		// Normalize angle to 0-360
		while(angle < 0)
			angle += 360;
		while(angle >= 360)
			angle -= 360;
			
		if(angle < min_angle)
			min_angle = angle;
		if(angle > max_angle)
			max_angle = angle;
	}
	
	spread = max_angle - min_angle;
	
	// Handle wrap-around case (e.g., angles 350 and 10)
	if(spread > 180)
		spread = 360 - spread;
		
	return spread;
}

// MERGED: Check if position has nearby cover
bot_has_nearby_cover(node)
{
	if(!isDefined(node))
		return false;
		
	// Check for walls/geometry nearby by doing traces
	check_distances = array(50, 80, 120);
	check_angles = array(0, 45, 90, 135, 180, 225, 270, 315);
	
	cover_points = 0;
	
	foreach(dist in check_distances)
	{
		foreach(angle in check_angles)
		{
			// Calculate check position
			rad = angle * 0.01745; // Convert to radians
			check_x = node.origin[0] + (cos(rad) * dist);
			check_y = node.origin[1] + (sin(rad) * dist);
			check_pos = (check_x, check_y, node.origin[2]);
			
			// Trace to see if blocked
			if(!SightTracePassed(node.origin + (0, 0, 40), check_pos + (0, 0, 40), false, undefined))
			{
				cover_points++;
			}
		}
	}
	
	// If at least 30% of traces hit geometry, consider it has cover
	return (cover_points > 7);
}

// MERGED: Helper to get human player
get_human_player()
{
	players = get_players();
	foreach(player in players)
	{
		if(!isDefined(player.bot))
			return player;
	}
	return undefined;
}

// NEW: Check if bot should use knife instead of shooting
bot_should_use_knife()
{
	// Check if we have an enemy
	if(!isDefined(self.bot.threat.entity))
		return false;
	
	// Check cooldown to prevent spamming knife
	if(isDefined(self.bot.last_knife_time) && (GetTime() - self.bot.last_knife_time) < 800)
		return false;
	
	enemy = self.bot.threat.entity;
	dist = Distance(self.origin, enemy.origin);
	
	// Check if we're out of ammo
	weapon = self GetCurrentWeapon();
	currentammo = self getweaponammoclip(weapon) + self getweaponammostock(weapon);
	
	// If out of ammo and close enough, use knife
	if(!currentammo && dist < 80)
		return true;
	
	// Round-based knife logic for efficiency
	current_round = level.round_number;
	
	// Rounds 1-2: Prefer knife for efficiency and point building
	if(current_round <= 2)
	{
		// Knife if enemy is close (within melee range)
		if(dist < 100)
			return true;
	}
	// Round 3+: Only knife when very close (emergency situations)
	else
	{
		// Emergency knife when zombie is extremely close
		if(dist < 70)
			return true;
	}
	
	return false;
}

// NEW: Execute knife attack
bot_perform_knife_attack()
{
	if(!isDefined(self.bot.threat.entity))
		return;
	
	enemy = self.bot.threat.entity;
	
	// Look at enemy 
	if(isDefined(enemy.origin))
	{
		self lookat(enemy.origin + (0, 0, 40));
	}
	
	// Wait for aim
	wait 0.05;
	
	// Use melee button press
	self MeleeButtonPressed();
	
	// Update last knife time
	self.bot.last_knife_time = GetTime();
	
	// Short cooldown
	wait 0.4;
}

// NEW: Maintain formation to prevent clustering
bot_maintain_formation()
{
	// Only check every few seconds
	if(!isDefined(self.bot.formation_check_time) || GetTime() < self.bot.formation_check_time)
		return;
		
	self.bot.formation_check_time = GetTime() + 2000;
	
	// Get other bots
	other_bots = [];
	foreach(player in get_players())
	{
		if(player != self && isDefined(player.bot))
			other_bots[other_bots.size] = player;
	}
	
	// Check distance to nearest bot
	if(other_bots.size > 0)
	{
		closest_dist = 999999;
		foreach(bot in other_bots)
		{
			dist = Distance(self.origin, bot.origin);
			if(dist < closest_dist)
				closest_dist = dist;
		}
		
		// If too close (within 150 units), add spread
		if(closest_dist < 150 && !self hasgoal("spread"))
		{
			// Add random offset to wander goal
			offset = (randomintrange(-200, 200), randomintrange(-200, 200), 0);
			wander_goal = self GetGoal("wander");
			if(isDefined(wander_goal))
			{
				spread_goal = wander_goal + offset;
				self AddGoal(spread_goal, 100, 1, "spread");
			}
		}
		else if(closest_dist >= 150 && self hasgoal("spread"))
		{
			self cancelgoal("spread");
		}
	}
}

// Prevents multiple bots from trying to open the same door at once
bot_safely_interact_with_doors()
{
	// Don't try to open doors if another bot is already doing it
	if(is_true(level.door_being_opened))
		return;

	// Check if we're near a door
	door_triggers = getEntArray("zombie_door", "targetname");
	door_triggers = array_combine(door_triggers, getEntArray("zombie_debris", "targetname"));
	door_triggers = array_combine(door_triggers, getEntArray("zombie_airlock_buy", "targetname"));
	
	closest_dist = 999999;
	closest_door = undefined;
	
	foreach(door in door_triggers)
	{
		if(!isDefined(door))
			continue;
			
		dist = Distance(self.origin, door.origin);
		if(dist < closest_dist && dist < 80)
		{
			closest_dist = dist;
			closest_door = door;
		}
	}
	
	// If we're near a door, try to open it safely
	if(isDefined(closest_door))
	{
		// Set global flag to prevent other bots from trying at the same time
		level.door_being_opened = true;
		
		// Try to open the door
		self UseButtonPressed();
		
		// Wait a bit for door to process
		wait 0.5;
		
		// Reset flag so other bots can try later
		level.door_being_opened = false;
	}
}

// Prevents bots from using mystery boxes that have teddy bears
bot_safely_use_mystery_box()
{
	// Find closest mystery box
	box_triggers = getEntArray("treasure_chest_use", "targetname");
	
	closest_dist = 999999;
	closest_box = undefined;
	
	foreach(box in box_triggers)
	{
		if(!isDefined(box))
			continue;
			
		dist = Distance(self.origin, box.origin);
		if(dist < closest_dist && dist < 80)
		{
			closest_dist = dist;
			closest_box = box;
		}
	}
	
	// If we found a box and we're close to it
	if(isDefined(closest_box))
	{
		// Check if this box has a teddy bear
		box_location = closest_box.origin;
		if(array_contains(level.mystery_box_teddy_locations, box_location))
		{
			// Don't use this box, it has a teddy bear
			return;
		}
		
		// Watch for teddy bear notifications
		self thread watch_for_box_teddy(closest_box);
		
		// Use the box
		self UseButtonPressed();
	}
}

// Monitor box for teddy bear
watch_for_box_teddy(box)
{
	self endon("disconnect");
	
	// Wait for the teddy bear notification or other game events
	level waittill_any("weapon_fly_away_start", "teddy_bear", "box_moving");
	
	// When teddy bear appears, add this box location to the list of teddy locations
	if(!array_contains(level.mystery_box_teddy_locations, box.origin))
	{
		level.mystery_box_teddy_locations[level.mystery_box_teddy_locations.size] = box.origin;
	}
}

// Check if an array contains a specific value (origin)
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

// Helper function to combine arrays
array_combine(array1, array2)
{
	if(!isDefined(array1))
		return array2;
	
	if(!isDefined(array2))
		return array1;
		
	combined = [];
	foreach(item in array1)
	{
		combined[combined.size] = item;
	}
	
	foreach(item in array2)
	{
		combined[combined.size] = item;
	}
	
	return combined;
}

bot_combat_main()
{
	weapon = self getcurrentweapon();
	currentammo = self getweaponammoclip( weapon ) + self getweaponammostock( weapon );
	
	// NEW: Check if should use knife
	if(self bot_should_use_knife())
	{
		self bot_perform_knife_attack();
		return; // Skip shooting logic
	}
	
	// NEW: If out of ammo but not close enough for knife, return
	if(!currentammo)
	{
		return;
	}
	
	time = getTime();
	ads = 0;
	if ( !self bot_should_hip_fire() && self.bot.threat.dot > 0.96 )
	{
		ads = 1;
	}
	if ( ads )
	{
		self pressads( 1 );
	}
	else
	{
		self pressads( 0 );
	}
	frames = 4;
	if ( time >= self.bot.threat.time_aim_correct )
	{
		self.bot.threat.time_aim_correct += self.bot.threat.time_aim_interval;
		frac = ( time - self.bot.threat.time_first_sight ) / 100;
		frac = clamp( frac, 0, 1 );
		if ( !threat_is_player() )
		{
			frac = 1;
		}
		self.bot.threat.aim_target = self bot_update_aim( frames );
		self.bot.threat.position = self.bot.threat.entity.origin;
		self bot_update_lookat( self.bot.threat.aim_target, frac );
	}
	if ( self bot_on_target( self.bot.threat.entity.origin, 30 ) )
	{
		self allowattack( 1 );
	}
	else
	{
		self allowattack( 0 );
	}
	if ( is_true( self.stingerlockstarted ) )
	{
		self allowattack( self.stingerlockfinalized );
		return;
	}
}

bot_combat_dead( damage )
{
	wait 0.1;
	self allowattack( 0 );
	wait_endon( 0.25, "damage" );
	self bot_clear_enemy();
}

bot_should_hip_fire()
{
	enemy = self.bot.threat.entity;
	weapon = self getcurrentweapon();
	if ( weapon == "none" )
	{
		return 0;
	}
	if ( weaponisdualwield( weapon ) )
	{
		return 1;
	}
	class = weaponclass( weapon );
	if ( isplayer( enemy ) && class == "spread" )
	{
		return 1;
	}
	distsq = distancesquared( self.origin, enemy.origin );
	distcheck = 0;
	switch( class )
	{
		case "mg":
			distcheck = 250;
			break;
		case "smg":
			distcheck = 350;
			break;
		case "spread":
			distcheck = 400;
			break;
		case "pistol":
			distcheck = 200;
			break;
		case "rocketlauncher":
			distcheck = 0;
			break;
		case "rifle":
		default:
			distcheck = 300;
			break;
	}
	if ( isweaponscopeoverlay( weapon ) )
	{
		distcheck = 500;
	}
	return distsq < ( distcheck * distcheck );
}

bot_patrol_near_enemy( damage, attacker, direction )
{
	if ( isDefined( attacker ) )
	{
		self bot_lookat_entity( attacker );
	}
	if ( !isDefined( attacker ) )
	{
		attacker = self bot_get_closest_enemy( self.origin );
	}
	if ( !isDefined( attacker ) )
	{
		return;
	}
	node = bot_nearest_node( attacker.origin );
	if ( !isDefined( node ) )
	{
		nodes = getnodesinradiussorted( attacker.origin, 1024, 0, 512, "Path", 8 );
		if ( nodes.size )
		{
			node = nodes[ 0 ];
		}
	}
	if ( isDefined( node ) )
	{
		if ( isDefined( damage ) )
		{
			self addgoal( node, 24, 4, "enemy_patrol" );
			return;
		}
		else
		{
			self addgoal( node, 24, 2, "enemy_patrol" );
		}
	}
}

bot_lookat_entity( entity )
{
	if ( isplayer( entity ) && entity getstance() != "prone" )
	{
		if ( distancesquared( self.origin, entity.origin ) < 65536 )
		{
			origin = entity getcentroid() + vectorScale( ( 0, 0, 1 ), 10 );
			self lookat( origin );
			return;
		}
	}
	offset = target_getoffset( entity );
	if ( isDefined( offset ) )
	{
		self lookat( entity.origin + offset );
	}
	else
	{
		self lookat( entity getcentroid() );
	}
}

bot_update_lookat( origin, frac )
{
	angles = vectorToAngles( origin - self.origin );
	right = anglesToRight( angles );
	error = bot_get_aim_error() * ( 1 - frac );
	if ( cointoss() )
	{
		error *= -1;
	}
	height = origin[ 2 ] - self.bot.threat.entity.origin[ 2 ];
	height *= 1 - frac;
	if ( cointoss() )
	{
		height *= -1;
	}
	end = origin + ( right * error );
	end += ( 0, 0, height );
	red = 1 - frac;
	green = frac;
	self lookat( end );
}

bot_update_aim( frames )
{
	ent = self.bot.threat.entity;
	prediction = self predictposition( ent, frames );
	if ( !threat_is_player() )
	{
		height = ent getcentroid()[ 2 ] - prediction[ 2 ];
		
		// NEW: Aim for headshots - higher offset
		headshot_offset = 18;
		
		return prediction + ( 0, 0, height + headshot_offset );
	}
	height = ent getplayerviewheight();
	torso = prediction + ( 0, 0, height / 1.6 );
	return torso;
}

bot_on_target( aim_target, radius )
{
	angles = self getplayerangles();
	forward = anglesToForward( angles );
	origin = self getplayercamerapos();
	len = distance( aim_target, origin );
	end = origin + ( forward * len );
	if ( distance2dsquared( aim_target, end ) < ( radius * radius ) )
	{
		return 1;
	}
	return 0;
}

bot_get_aim_error()
{
	return 1;
}

bot_has_lmg()
{
	if ( bot_has_weapon_class( "mg" ) )
	{
		return 1;
	}
	return 0;
}

bot_has_weapon_class( class )
{
	if ( self isreloading() )
	{
		return 0;
	}
	weapon = self getcurrentweapon();
	if ( weapon == "none" )
	{
		return 0;
	}
	if ( weaponclass( weapon ) == class )
	{
		return 1;
	}
	return 0;
}

bot_can_reload()
{
	weapon = self getcurrentweapon();
	if ( weapon == "none" )
	{
		return 0;
	}
	if ( !self getweaponammostock( weapon ) )
	{
		return 0;
	}
	if ( self isreloading() || self isswitchingweapons() || self isthrowinggrenade() )
	{
		return 0;
	}
	return 1;
}

bot_best_enemy()
{
	enemies = getaispeciesarray( level.zombie_team, "all" );
	enemies = arraysort( enemies, self.origin );
	i = 0;
	while ( i < enemies.size )
	{
		if ( threat_should_ignore( enemies[ i ] ) )
		{
			i++;
			continue;
		}
		if ( self botsighttracepassed( enemies[ i ] ) )
		{
			self.bot.threat.entity = enemies[ i ];
			self.bot.threat.time_first_sight = getTime();
			self.bot.threat.time_recent_sight = getTime();
			self.bot.threat.dot = bot_dot_product( enemies[ i ].origin );
			self.bot.threat.position = enemies[ i ].origin;
			return 1;
		}
		i++;
	}
	return 0;
}

bot_weapon_ammo_frac()
{
	if ( self isreloading() || self isswitchingweapons() )
	{
		return 0;
	}
	weapon = self getcurrentweapon();
	if ( weapon == "none" )
	{
		return 1;
	}
	total = weaponclipsize( weapon );
	if ( total <= 0 )
	{
		return 1;
	}
	current = self getweaponammoclip( weapon );
	return current / total;
}

bot_select_weapon()
{
	if ( self isthrowinggrenade() || self isswitchingweapons() || self isreloading() )
	{
		return;
	}
	if ( !self isonground() )
	{
		return;
	}
	ent = self.bot.threat.entity;
	if ( !isDefined( ent ) )
	{
		return;
	}
	primaries = self getweaponslistprimaries();
	weapon = self getcurrentweapon();
	stock = self getweaponammostock( weapon );
	clip = self getweaponammoclip( weapon );
	if ( weapon == "none" )
	{
		return;
	}
	if ( weapon == "fhj18_mp" && !target_istarget( ent ) )
	{
		foreach ( primary in primaries )
		{
			if ( primary != weapon )
			{
				self switchtoweapon( primary );
				return;
			}
		}
		return;
	}
	if ( !clip )
	{
		if ( stock )
		{
			if ( weaponhasattachment( weapon, "fastreload" ) )
			{
				return;
			}
		}
		i = 0;
		while ( i < primaries.size )
		{
			if ( primaries[ i ] == weapon || primaries[ i ] == "fhj18_mp" )
			{
				i++;
				continue;
			}
			if ( self getweaponammoclip( primaries[ i ] ) )
			{
				self switchtoweapon( primaries[ i ] );
				return;
			}
			i++;
		}
		if ( self bot_has_lmg() )
		{
			i = 0;
			while ( i < primaries.size )
			{
				if ( primaries[ i ] == weapon || primaries[ i ] == "fhj18_mp" )
				{
					i++;
					continue;
				}
				else
				{
					self switchtoweapon( primaries[ i ] );
					return;
				}
				i++;
			}
		}
	}
}

bot_can_do_combat()
{
	if ( self ismantling() || self isonladder() )
	{
		return 0;
	}
	return 1;
}

bot_dot_product( origin )
{
	angles = self getplayerangles();
	forward = anglesToForward( angles );
	delta = origin - self getplayercamerapos();
	delta = vectornormalize( delta );
	dot = vectordot( forward, delta );
	return dot;
}

threat_should_ignore( entity )
{
	return 0;
}

bot_clear_enemy()
{
	self clearlookat();
	self.bot.threat.entity = undefined;
}

bot_has_enemy()
{
	if ( isDefined( self.bot.threat.entity ) )
	{
		return 1;
	}
	return 0;
}

threat_dead()
{
	if ( self bot_has_enemy() )
	{
		ent = self.bot.threat.entity;
		if ( !isalive( ent ) )
		{
			return 1;
		}
		return 0;
	}
	return 0;
}

threat_is_player()
{
	ent = self.bot.threat.entity;
	if ( isDefined( ent ) && isplayer( ent ) )
	{
		return 1;
	}
	return 0;
}

// NEW: Trap activation logic
bot_use_trap()
{
	if(!isDefined(self.bot.trap_check_time) || GetTime() > self.bot.trap_check_time)
	{
		self.bot.trap_check_time = GetTime() + 4000; // Check every 4 seconds
		
		// Skip if broke or power is off
		if(self.score < 1000 || !flag("power_on"))
			return;
			
		// Only use traps if zombies are nearby
		zombies = self bot_get_cached_zombies();
		nearby_zombies = 0;
		
		foreach(zombie in zombies)
		{
			if(Distance(self.origin, zombie.origin) < 350)
				nearby_zombies++;
		}
		
		// Need at least 5 zombies nearby to justify trap cost
		if(nearby_zombies < 5)
			return;
			
		// Find trap triggers (generic detection)
		trap_triggers = GetEntArray("zombie_trap", "targetname");
		
		closest_trap = undefined;
		closest_dist = 250;
		
		foreach(trap in trap_triggers)
		{
			if(!isDefined(trap) || !isDefined(trap.origin))
				continue;
				
			// Skip if trap is on cooldown
			if(isDefined(trap.bot_trap_cooldown) && GetTime() < trap.bot_trap_cooldown)
				continue;
				
			dist = Distance(self.origin, trap.origin);
			if(dist < closest_dist)
			{
				closest_trap = trap;
				closest_dist = dist;
			}
		}
		
		if(isDefined(closest_trap))
		{
			// Get cost
			trap_cost = 1000;
			if(isDefined(closest_trap.zombie_cost))
				trap_cost = closest_trap.zombie_cost;
				
			if(self.score >= trap_cost)
			{
				self lookat(closest_trap.origin);
				wait 0.2;
				
				self maps\mp\zombies\_zm_score::minus_to_player_score(trap_cost);
				
				// Trigger trap
				if(isDefined(closest_trap.unitrigger_stub) && isDefined(closest_trap.unitrigger_stub.trigger))
					closest_trap.unitrigger_stub.trigger notify("trigger", self);
				else
					closest_trap notify("trigger", self);
				
				// Set cooldown (25 seconds)
				closest_trap.bot_trap_cooldown = GetTime() + 25000;
				
				self.bot.trap_check_time = GetTime() + 10000; // Personal cooldown
			}
		}
	}
}

// ENHANCED: Smart kiting/training logic (now works at all rounds)
bot_smart_kiting()
{
	// CHANGED: Lowered round requirement from 8 to 3 for earlier kiting
	if(level.round_number < 3)
		return;
		
	if(!isDefined(self.bot.kite_check_time) || GetTime() > self.bot.kite_check_time)
	{
		self.bot.kite_check_time = GetTime() + 1000; // Check more frequently
		
		zombies = self bot_get_cached_zombies();
		nearby_zombies = 0;
		zombie_center = (0, 0, 0);
		
		// Find zombie swarm center point
		foreach(zombie in zombies)
		{
			dist = Distance(self.origin, zombie.origin);
			if(dist < 500)
			{
				nearby_zombies++;
				zombie_center += zombie.origin;
			}
		}
		
		// CHANGED: Lowered threshold from 7+ to 5+ zombies
		if(nearby_zombies >= 5)
		{
			zombie_center = zombie_center / nearby_zombies;
			
			// Direction away from zombie horde
			escape_vector = VectorNormalize(self.origin - zombie_center);
			
			// Perpendicular vector for circular motion
			right_vector = (-escape_vector[1], escape_vector[0], 0);
			
			// Initialize kite direction
			if(!isDefined(self.bot.kite_direction))
				self.bot.kite_direction = 1;
				
			// Calculate circular kiting position
			kite_target = self.origin + (escape_vector * 250) + (right_vector * 180 * self.bot.kite_direction);
			
			// Validate path
			if(FindPath(self.origin, kite_target, undefined, 0, 1))
			{
				if(!self hasgoal("kiting") || Distance(self GetGoal("kiting"), kite_target) > 150)
				{
					self AddGoal(kite_target, 80, 2, "kiting");
				}
				
				// Randomly switch kiting direction
				if(randomfloat(1) < 0.15)
					self.bot.kite_direction *= -1;
			}
		}
		else if(nearby_zombies < 3 && self hasgoal("kiting"))
		{
			// Stop kiting when horde is small
			self cancelgoal("kiting");
		}
	}
}