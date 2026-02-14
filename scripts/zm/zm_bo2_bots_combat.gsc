// T6 GSC SOURCE
// Compiler version 0 (prec2)
// Enhanced AI Combat System with Optimizations

#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include scripts\zm\zm_bo2_bots;
#include scripts\zm\zm_bo2_bots_utility;

bot_combat_think(damage, attacker, direction)
{
	self endon("death");
	self endon("disconnect");
	level endon("game_ended");
	
	if(!bot_can_do_combat())
		return;
	
	self allowattack(0);
	self pressads(0);
	
	// Initialize AI enhancement variables
	if(!isDefined(self.bot.entity_cache_time))
		self.bot.entity_cache_time = 0;
	if(!isDefined(self.bot.last_follow_pos))
		self.bot.last_follow_pos = (0,0,0);
	if(!isDefined(self.bot.last_knife_time))
		self.bot.last_knife_time = 0;
	if(!isDefined(self.bot.last_evasion_time))
		self.bot.last_evasion_time = 0;
	
	for(;;)
	{
		if(!bot_can_do_combat())
			return;
			
		if(self atgoal("flee"))
			self cancelgoal("flee");
			
		// ENHANCED: Check if bot is overwhelmed
		self bot_check_overwhelmed();
		
		// ENHANCED: Maintain safe distance
		self bot_maintain_safe_distance();
			
		// ENHANCED: Better flee logic with increased trigger distance (180 units)
		if(Distance(self.origin, self.bot.threat.position) <= 180 || isdefined(damage))
		{
			nodes = getnodesinradiussorted(self.origin, 1024, 256, 512);
			nearest = bot_nearest_node(self.origin);
			
			if(isDefined(nearest) && !self hasgoal("flee"))
			{
				foreach(node in nodes)
				{
					if(!NodeVisible(nearest.origin, node.origin) && FindPath(self.origin, node.origin, undefined, 0, 1))
					{
						self addgoal(node.origin, 24, 4, "flee");
						break;
					}
				}
			}
		}
		
		if(self GetCurrentWeapon() == "none")
			continue;
			
		// Use cached zombie list for better performance
		sight = self bot_best_enemy_enhanced();
		
		if(!isdefined(self.bot.threat.entity))
			continue;
			
		if(threat_dead())
		{
			self bot_combat_dead();
			continue;
		}
		
		// Fire coordination to prevent redundant targeting
		self bot_coordinate_fire();
		
		self bot_combat_main();
		self bot_pickup_powerup();
		
		if(is_true(level.using_bot_revive_logic))
			self bot_revive_teammates();
		
		// Maintain formation with other bots
		self bot_maintain_formation();
		
		// Combat strafe
		self bot_combat_strafe();
		
		// Tactical positioning
		self bot_use_tactical_positioning();
		
		// Trap usage
		self bot_use_trap();
		
		// Smart kiting
		self bot_smart_kiting();
		
		wait 0.05;
	}
}

// ENHANCED: Check if bot is overwhelmed (lowered threshold)
bot_check_overwhelmed()
{
	zombies = self bot_get_cached_zombies();
	nearby_count = 0;
	very_close_count = 0;
	
	foreach(zombie in zombies)
	{
		dist_sq = DistanceSquared(self.origin, zombie.origin);
		if(dist_sq < 62500) // 250^2
			nearby_count++;
		if(dist_sq < 14400) // 120^2
			very_close_count++;
	}
	
	// Trigger panic at 3+ zombies or if 2+ are very close
	if(nearby_count >= 3 || very_close_count >= 2)
	{
		self.bot.panic_mode = true;
		self.bot.panic_time = GetTime() + 2500;
		
		nodes = getnodesinradiussorted(self.origin, 768, 0);
		if(nodes.size > 0)
		{
			escape_node = nodes[nodes.size - 1];
			self AddGoal(escape_node.origin, 50, 5, "panic");
		}
	}
	else if(isDefined(self.bot.panic_mode) && GetTime() > self.bot.panic_time)
	{
		self.bot.panic_mode = undefined;
		self cancelgoal("panic");
	}
}

// Maintain safe distance from zombies
bot_maintain_safe_distance()
{
	if(isDefined(self.bot.last_distance_check) && GetTime() < self.bot.last_distance_check)
		return;
		
	self.bot.last_distance_check = GetTime() + 500;
	
	zombies = self bot_get_cached_zombies();
	if(!isDefined(zombies) || zombies.size == 0)
		return;
		
	closest_zombie = undefined;
	closest_dist_sq = 999999;
	
	foreach(zombie in zombies)
	{
		dist_sq = DistanceSquared(self.origin, zombie.origin);
		if(dist_sq < closest_dist_sq)
		{
			closest_dist_sq = dist_sq;
			closest_zombie = zombie;
		}
	}
	
	// Maintain 200+ unit distance from nearest zombie
	if(isDefined(closest_zombie) && closest_dist_sq < 40000) // 200^2
	{
		escape_dir = VectorNormalize(self.origin - closest_zombie.origin);
		escape_pos = self.origin + (escape_dir * 250);
		
		if(FindPath(self.origin, escape_pos, undefined, 0, 1))
		{
			if(!self hasgoal("spacing") || DistanceSquared(self GetGoal("spacing"), escape_pos) > 10000)
				self AddGoal(escape_pos, 50, 3, "spacing");
		}
	}
	else if(closest_dist_sq >= 40000 && self hasgoal("spacing"))
	{
		self cancelgoal("spacing");
	}
}

// Strafe movement during combat
bot_combat_strafe()
{
	if(!isDefined(self.bot.threat.entity))
		return;
		
	if(isDefined(self.bot.last_strafe_time) && GetTime() < self.bot.last_strafe_time)
		return;
		
	self.bot.last_strafe_time = GetTime() + randomintrange(800, 1500);
	
	enemy = self.bot.threat.entity;
	dist_sq = DistanceSquared(self.origin, enemy.origin);
	
	// Only strafe if enemy is medium-close range (100-400)
	if(dist_sq > 10000 && dist_sq < 160000) // 100^2 and 400^2
	{
		to_enemy = VectorNormalize(enemy.origin - self.origin);
		strafe_dir = (-to_enemy[1], to_enemy[0], 0);
		
		if(randomfloat(1) > 0.5)
			strafe_dir = -strafe_dir;
			
		strafe_pos = self.origin + (strafe_dir * 150);
		
		if(FindPath(self.origin, strafe_pos, undefined, 0, 1))
			self AddGoal(strafe_pos, 50, 2, "strafe");
	}
}

// Cache zombie list for performance
bot_get_cached_zombies()
{
	if(!isDefined(self.bot.entity_cache_time) || GetTime() > self.bot.entity_cache_time)
	{
		self.bot.cached_zombies = getaispeciesarray(level.zombie_team, "all");
		self.bot.entity_cache_time = GetTime() + 500;
	}
	
	return self.bot.cached_zombies;
}

// Enhanced enemy selection with threat scoring
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

// Calculate threat priority score
bot_calculate_threat_score(zombie)
{
	score = 0;
	dist = Distance(self.origin, zombie.origin);
	
	// Distance priority (closer = higher threat)
	score += (1000 - dist) * 2;
	
	// Special zombie types
	if(isDefined(zombie.is_brutus) && zombie.is_brutus)
		score += 500;
	
	// Zombies attacking downed teammates
	players = get_players();
	foreach(player in players)
	{
		if(DistanceSquared(player.origin, zombie.origin) < 10000 && // 100^2
		   player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			score += 300;
	}
	
	// Zombies near human player
	human = get_human_player();
	if(isDefined(human))
	{
		dist_to_human_sq = DistanceSquared(human.origin, zombie.origin);
		if(dist_to_human_sq < 22500) // 150^2
			score += 400;
		else if(dist_to_human_sq < 90000) // 300^2
			score += 200;
	}
	
	return score;
}

// Fire coordination - prevents multiple bots targeting same zombie
bot_coordinate_fire()
{
	if(!isDefined(self.bot.fire_coord_time) || GetTime() > self.bot.fire_coord_time)
	{
		self.bot.fire_coord_time = GetTime() + 1500;
		
		if(!isDefined(self.bot.threat.entity))
			return;
			
		my_target = self.bot.threat.entity;
		redundant_count = 0;
		
		foreach(player in get_players())
		{
			if(player == self || !isDefined(player.bot))
				continue;
				
			if(isDefined(player.bot.threat.entity) && player.bot.threat.entity == my_target)
				redundant_count++;
		}
		
		// If 2+ bots already targeting, find different target
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
					
				contention = bot_get_target_contention(zombie);
				
				if(contention < 2)
				{
					score = bot_calculate_threat_score(zombie);
					score += (2 - contention) * 200;
					
					if(score > best_score)
					{
						best_score = score;
						best_alternate = zombie;
					}
				}
			}
			
			if(isDefined(best_alternate))
			{
				self.bot.threat.entity = best_alternate;
				self.bot.threat.position = best_alternate.origin;
				self.bot.threat.time_first_sight = GetTime();
			}
		}
	}
}

// Check how many bots are targeting a specific zombie
bot_get_target_contention(zombie)
{
	bot_count = 0;
	
	foreach(player in get_players())
	{
		if(!isDefined(player.bot) || player == self)
			continue;
			
		if(isDefined(player.bot.threat.entity) && player.bot.threat.entity == zombie)
			bot_count++;
	}
	
	return bot_count;
}

// Tactical positioning - finds chokepoints
bot_use_tactical_positioning()
{
	if(!isDefined(self.bot.tactical_pos_time) || GetTime() > self.bot.tactical_pos_time)
	{
		self.bot.tactical_pos_time = GetTime() + 3000;
		
		if(isDefined(self.bot.threat.entity) || 
		   self hasgoal("revive") || 
		   self hasgoal("panic") ||
		   self hasgoal("flee"))
			return;
			
		nodes = GetNodesInRadius(self.origin, 450, 0);
		
		if(!isDefined(nodes) || nodes.size == 0)
			return;
			
		best_node = undefined;
		best_score = 40;
		
		foreach(node in nodes)
		{
			score = bot_evaluate_tactical_position(node);
			if(score > best_score)
			{
				best_score = score;
				best_node = node;
			}
		}
		
		if(isDefined(best_node))
		{
			if(!self hasgoal("tactical") || DistanceSquared(self GetGoal("tactical"), best_node.origin) > 10000)
			{
				self cancelgoal("tactical");
				self AddGoal(best_node.origin, 50, 1, "tactical");
			}
		}
	}
}

// Evaluate tactical value of a position
bot_evaluate_tactical_position(node)
{
	if(!isDefined(node) || !isDefined(node.origin))
		return 0;
		
	score = 0;
	
	zombies = getaispeciesarray(level.zombie_team, "all");
	approach_angles = [];
	nearby_zombie_count = 0;
	
	foreach(zombie in zombies)
	{
		if(!isDefined(zombie) || !isalive(zombie))
			continue;
			
		dist_sq = DistanceSquared(node.origin, zombie.origin);
		if(dist_sq < 360000) // 600^2
		{
			nearby_zombie_count++;
			angle_to_zombie = VectorToAngles(zombie.origin - node.origin)[1];
			approach_angles[approach_angles.size] = angle_to_zombie;
		}
	}
	
	if(approach_angles.size > 2)
	{
		angle_spread = bot_calculate_angle_spread(approach_angles);
		
		if(angle_spread < 90)
			score += 120;
		else if(angle_spread < 150)
			score += 60;
	}
	
	human = get_human_player();
	if(isDefined(human))
	{
		dist_to_human_sq = DistanceSquared(node.origin, human.origin);
		
		if(dist_to_human_sq > 40000 && dist_to_human_sq < 160000) // 200-400 units
			score += 80;
		else if(dist_to_human_sq > 22500 && dist_to_human_sq < 250000) // 150-500 units
			score += 40;
		else if(dist_to_human_sq < 10000) // <100 units
			score -= 50;
	}
	
	height_diff = node.origin[2] - self.origin[2];
	if(height_diff > 20 && height_diff < 100)
		score += 30;
	
	dist_from_current_sq = DistanceSquared(node.origin, self.origin);
	if(dist_from_current_sq > 90000) // >300 units
		score -= 20;
	
	if(bot_has_nearby_cover(node))
		score += 50;
	
	return score;
}

// Calculate angle spread to detect funnel points
bot_calculate_angle_spread(angles)
{
	if(!isDefined(angles) || angles.size < 2)
		return 360;
		
	min_angle = 360;
	max_angle = 0;
	
	foreach(angle in angles)
	{
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
	
	if(spread > 180)
		spread = 360 - spread;
		
	return spread;
}

// Check if position has nearby cover
bot_has_nearby_cover(node)
{
	if(!isDefined(node))
		return false;
		
	check_distances = array(50, 80, 120);
	check_angles = array(0, 45, 90, 135, 180, 225, 270, 315);
	
	cover_points = 0;
	
	foreach(dist in check_distances)
	{
		foreach(angle in check_angles)
		{
			rad = angle * 0.01745;
			check_x = node.origin[0] + (cos(rad) * dist);
			check_y = node.origin[1] + (sin(rad) * dist);
			check_pos = (check_x, check_y, node.origin[2]);
			
			if(!SightTracePassed(node.origin + (0, 0, 40), check_pos + (0, 0, 40), false, undefined))
				cover_points++;
		}
	}
	
	return (cover_points > 7);
}

// Helper to get human player
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

// Check if bot should use knife
bot_should_use_knife()
{
	if(!isDefined(self.bot.threat.entity))
		return false;
	
	if(isDefined(self.bot.last_knife_time) && (GetTime() - self.bot.last_knife_time) < 800)
		return false;
	
	enemy = self.bot.threat.entity;
	dist_sq = DistanceSquared(self.origin, enemy.origin);
	
	weapon = self GetCurrentWeapon();
	currentammo = self getweaponammoclip(weapon) + self getweaponammostock(weapon);
	
	// If out of ammo and close enough
	if(!currentammo && dist_sq < 6400) // 80^2
		return true;
	
	current_round = level.round_number;
	
	// Rounds 1-2: Prefer knife for efficiency
	if(current_round <= 2 && dist_sq < 10000) // 100^2
		return true;
		
	// Round 3+: Emergency knife
	if(dist_sq < 4900) // 70^2
		return true;
	
	return false;
}

// Execute knife attack
bot_perform_knife_attack()
{
	if(!isDefined(self.bot.threat.entity))
		return;
	
	enemy = self.bot.threat.entity;
	
	if(isDefined(enemy.origin))
		self lookat(enemy.origin + (0, 0, 40));
	
	wait 0.05;
	
	self MeleeButtonPressed();
	self.bot.last_knife_time = GetTime();
	
	wait 0.4;
}

// Maintain formation to prevent clustering
bot_maintain_formation()
{
	if(!isDefined(self.bot.formation_check_time) || GetTime() < self.bot.formation_check_time)
		return;
		
	self.bot.formation_check_time = GetTime() + 2000;
	
	other_bots = [];
	foreach(player in get_players())
	{
		if(player != self && isDefined(player.bot))
			other_bots[other_bots.size] = player;
	}
	
	if(other_bots.size > 0)
	{
		closest_dist_sq = 999999;
		foreach(bot in other_bots)
		{
			dist_sq = DistanceSquared(self.origin, bot.origin);
			if(dist_sq < closest_dist_sq)
				closest_dist_sq = dist_sq;
		}
		
		if(closest_dist_sq < 22500 && !self hasgoal("spread")) // 150^2
		{
			offset = (randomintrange(-200, 200), randomintrange(-200, 200), 0);
			wander_goal = self GetGoal("wander");
			if(isDefined(wander_goal))
			{
				spread_goal = wander_goal + offset;
				self AddGoal(spread_goal, 100, 1, "spread");
			}
		}
		else if(closest_dist_sq >= 22500 && self hasgoal("spread"))
		{
			self cancelgoal("spread");
		}
	}
}

// Trap activation logic
bot_use_trap()
{
	if(!isDefined(self.bot.trap_check_time) || GetTime() > self.bot.trap_check_time)
	{
		self.bot.trap_check_time = GetTime() + 4000;
		
		if(self.score < 1000 || !flag("power_on"))
			return;
			
		zombies = self bot_get_cached_zombies();
		nearby_zombies = 0;
		
		foreach(zombie in zombies)
		{
			if(DistanceSquared(self.origin, zombie.origin) < 122500) // 350^2
				nearby_zombies++;
		}
		
		if(nearby_zombies < 5)
			return;
			
		trap_triggers = GetEntArray("zombie_trap", "targetname");
		
		closest_trap = undefined;
		closest_dist_sq = 62500; // 250^2
		
		foreach(trap in trap_triggers)
		{
			if(!isDefined(trap) || !isDefined(trap.origin))
				continue;
				
			if(isDefined(trap.bot_trap_cooldown) && GetTime() < trap.bot_trap_cooldown)
				continue;
				
			dist_sq = DistanceSquared(self.origin, trap.origin);
			if(dist_sq < closest_dist_sq)
			{
				closest_trap = trap;
				closest_dist_sq = dist_sq;
			}
		}
		
		if(isDefined(closest_trap))
		{
			trap_cost = 1000;
			if(isDefined(closest_trap.zombie_cost))
				trap_cost = closest_trap.zombie_cost;
				
			if(self.score >= trap_cost)
			{
				self lookat(closest_trap.origin);
				wait 0.2;
				
				self maps\mp\zombies\_zm_score::minus_to_player_score(trap_cost);
				
				if(isDefined(closest_trap.unitrigger_stub) && isDefined(closest_trap.unitrigger_stub.trigger))
					closest_trap.unitrigger_stub.trigger notify("trigger", self);
				else
					closest_trap notify("trigger", self);
				
				closest_trap.bot_trap_cooldown = GetTime() + 25000;
				self.bot.trap_check_time = GetTime() + 10000;
			}
		}
	}
}

// Smart kiting/training logic
bot_smart_kiting()
{
	if(level.round_number < 3)
		return;
		
	if(!isDefined(self.bot.kite_check_time) || GetTime() > self.bot.kite_check_time)
	{
		self.bot.kite_check_time = GetTime() + 1000;
		
		zombies = self bot_get_cached_zombies();
		nearby_zombies = 0;
		zombie_center = (0, 0, 0);
		
		foreach(zombie in zombies)
		{
			dist_sq = DistanceSquared(self.origin, zombie.origin);
			if(dist_sq < 250000) // 500^2
			{
				nearby_zombies++;
				zombie_center += zombie.origin;
			}
		}
		
		if(nearby_zombies >= 5)
		{
			zombie_center = zombie_center / nearby_zombies;
			escape_vector = VectorNormalize(self.origin - zombie_center);
			right_vector = (-escape_vector[1], escape_vector[0], 0);
			
			if(!isDefined(self.bot.kite_direction))
				self.bot.kite_direction = 1;
				
			kite_target = self.origin + (escape_vector * 250) + (right_vector * 180 * self.bot.kite_direction);
			
			if(FindPath(self.origin, kite_target, undefined, 0, 1))
			{
				if(!self hasgoal("kiting") || DistanceSquared(self GetGoal("kiting"), kite_target) > 22500)
					self AddGoal(kite_target, 80, 2, "kiting");
				
				if(randomfloat(1) < 0.15)
					self.bot.kite_direction *= -1;
			}
		}
		else if(nearby_zombies < 3 && self hasgoal("kiting"))
		{
			self cancelgoal("kiting");
		}
	}
}

bot_combat_main()
{
	weapon = self getcurrentweapon();
	currentammo = self getweaponammoclip(weapon) + self getweaponammostock(weapon);
	
	if(self bot_should_use_knife())
	{
		self bot_perform_knife_attack();
		return;
	}
	
	if(!currentammo)
		return;
		
	time = getTime();
	ads = 0;
	
	if(!self bot_should_hip_fire() && self.bot.threat.dot > 0.96)
		ads = 1;
	
	if(ads)
		self pressads(1);
	else
		self pressads(0);
		
	frames = 4;
	
	if(time >= self.bot.threat.time_aim_correct)
	{
		self.bot.threat.time_aim_correct += self.bot.threat.time_aim_interval;
		frac = (time - self.bot.threat.time_first_sight) / 100;
		frac = clamp(frac, 0, 1);
		
		if(!threat_is_player())
			frac = 1;
			
		self.bot.threat.aim_target = self bot_update_aim(frames);
		self.bot.threat.position = self.bot.threat.entity.origin;
		self bot_update_lookat(self.bot.threat.aim_target, frac);
	}
	
	if(self bot_on_target(self.bot.threat.entity.origin, 30))
		self allowattack(1);
	else
		self allowattack(0);
		
	if(is_true(self.stingerlockstarted))
	{
		self allowattack(self.stingerlockfinalized);
		return;
	}
}

bot_combat_dead(damage)
{
	wait 0.1;
	self allowattack(0);
	wait_endon(0.25, "damage");
	self bot_clear_enemy();
}

bot_should_hip_fire()
{
	enemy = self.bot.threat.entity;
	weapon = self getcurrentweapon();
	
	if(weapon == "none")
		return 0;
		
	if(weaponisdualwield(weapon))
		return 1;
		
	class = weaponclass(weapon);
	
	if(isplayer(enemy) && class == "spread")
		return 1;
		
	distsq = distancesquared(self.origin, enemy.origin);
	distcheck = 0;
	
	switch(class)
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
	
	if(isweaponscopeoverlay(weapon))
		distcheck = 500;
		
	return distsq < (distcheck * distcheck);
}

bot_patrol_near_enemy(damage, attacker, direction)
{
	if(isDefined(attacker))
		self bot_lookat_entity(attacker);
		
	if(!isDefined(attacker))
		attacker = self bot_get_closest_enemy(self.origin);
		
	if(!isDefined(attacker))
		return;
		
	node = bot_nearest_node(attacker.origin);
	
	if(!isDefined(node))
	{
		nodes = getnodesinradiussorted(attacker.origin, 1024, 0, 512, "Path", 8);
		if(nodes.size)
			node = nodes[0];
	}
	
	if(isDefined(node))
	{
		if(isDefined(damage))
			self addgoal(node, 24, 4, "enemy_patrol");
		else
			self addgoal(node, 24, 2, "enemy_patrol");
	}
}

bot_lookat_entity(entity)
{
	if(isplayer(entity) && entity getstance() != "prone")
	{
		if(distancesquared(self.origin, entity.origin) < 65536)
		{
			origin = entity getcentroid() + vectorScale((0, 0, 1), 10);
			self lookat(origin);
			return;
		}
	}
	
	offset = target_getoffset(entity);
	
	if(isDefined(offset))
		self lookat(entity.origin + offset);
	else
		self lookat(entity getcentroid());
}

bot_update_lookat(origin, frac)
{
	angles = vectorToAngles(origin - self.origin);
	right = anglesToRight(angles);
	error = bot_get_aim_error() * (1 - frac);
	
	if(cointoss())
		error *= -1;
		
	height = origin[2] - self.bot.threat.entity.origin[2];
	height *= 1 - frac;
	
	if(cointoss())
		height *= -1;
		
	end = origin + (right * error);
	end += (0, 0, height);
	self lookat(end);
}

bot_update_aim(frames)
{
	ent = self.bot.threat.entity;
	prediction = self predictposition(ent, frames);
	
	if(!threat_is_player())
	{
		height = ent getcentroid()[2] - prediction[2];
		headshot_offset = 18;
		return prediction + (0, 0, height + headshot_offset);
	}
	
	height = ent getplayerviewheight();
	torso = prediction + (0, 0, height / 1.6);
	return torso;
}

bot_on_target(aim_target, radius)
{
	angles = self getplayerangles();
	forward = anglesToForward(angles);
	origin = self getplayercamerapos();
	len = distance(aim_target, origin);
	end = origin + (forward * len);
	
	if(distance2dsquared(aim_target, end) < (radius * radius))
		return 1;
		
	return 0;
}

bot_get_aim_error()
{
	return 1;
}

bot_has_lmg()
{
	if(bot_has_weapon_class("mg"))
		return 1;
	return 0;
}

bot_has_weapon_class(class)
{
	if(self isreloading())
		return 0;
		
	weapon = self getcurrentweapon();
	
	if(weapon == "none")
		return 0;
		
	if(weaponclass(weapon) == class)
		return 1;
		
	return 0;
}

bot_can_reload()
{
	weapon = self getcurrentweapon();
	
	if(weapon == "none")
		return 0;
		
	if(!self getweaponammostock(weapon))
		return 0;
		
	if(self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
		return 0;
		
	return 1;
}

bot_best_enemy()
{
	enemies = getaispeciesarray(level.zombie_team, "all");
	enemies = arraysort(enemies, self.origin);
	
	foreach(enemy in enemies)
	{
		if(threat_should_ignore(enemy))
			continue;
			
		if(self botsighttracepassed(enemy))
		{
			self.bot.threat.entity = enemy;
			self.bot.threat.time_first_sight = getTime();
			self.bot.threat.time_recent_sight = getTime();
			self.bot.threat.dot = bot_dot_product(enemy.origin);
			self.bot.threat.position = enemy.origin;
			return 1;
		}
	}
	
	return 0;
}

bot_weapon_ammo_frac()
{
	if(self isreloading() || self isswitchingweapons())
		return 0;
		
	weapon = self getcurrentweapon();
	
	if(weapon == "none")
		return 1;
		
	total = weaponclipsize(weapon);
	
	if(total <= 0)
		return 1;
		
	current = self getweaponammoclip(weapon);
	return current / total;
}

bot_select_weapon()
{
	if(self isthrowinggrenade() || self isswitchingweapons() || self isreloading())
		return;
		
	if(!self isonground())
		return;
		
	ent = self.bot.threat.entity;
	
	if(!isDefined(ent))
		return;
		
	primaries = self getweaponslistprimaries();
	weapon = self getcurrentweapon();
	stock = self getweaponammostock(weapon);
	clip = self getweaponammoclip(weapon);
	
	if(weapon == "none")
		return;
		
	if(weapon == "fhj18_mp" && !target_istarget(ent))
	{
		foreach(primary in primaries)
		{
			if(primary != weapon)
			{
				self switchtoweapon(primary);
				return;
			}
		}
		return;
	}
	
	if(!clip)
	{
		if(stock)
		{
			if(weaponhasattachment(weapon, "fastreload"))
				return;
		}
		
		foreach(primary in primaries)
		{
			if(primary == weapon || primary == "fhj18_mp")
				continue;
				
			if(self getweaponammoclip(primary))
			{
				self switchtoweapon(primary);
				return;
			}
		}
		
		if(self bot_has_lmg())
		{
			foreach(primary in primaries)
			{
				if(primary == weapon || primary == "fhj18_mp")
					continue;
				else
				{
					self switchtoweapon(primary);
					return;
				}
			}
		}
	}
}

bot_can_do_combat()
{
	if(self ismantling() || self isonladder())
		return 0;
	return 1;
}

bot_dot_product(origin)
{
	angles = self getplayerangles();
	forward = anglesToForward(angles);
	delta = origin - self getplayercamerapos();
	delta = vectornormalize(delta);
	dot = vectordot(forward, delta);
	return dot;
}

threat_should_ignore(entity)
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
	if(isDefined(self.bot.threat.entity))
		return 1;
	return 0;
}

threat_dead()
{
	if(self bot_has_enemy())
	{
		ent = self.bot.threat.entity;
		if(!isalive(ent))
			return 1;
		return 0;
	}
	return 0;
}

threat_is_player()
{
	ent = self.bot.threat.entity;
	if(isDefined(ent) && isplayer(ent))
		return 1;
	return 0;
}
