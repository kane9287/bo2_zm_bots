#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include scripts\zm\zm_bo2_bots;
#include scripts\zm\zm_bo2_bots_utility;
#include scripts\zm\zm_bo2_bots_optimization;

// PRIORITY 3: Squad Fire Coordination - Avoid redundant targeting
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
					score = bot_calculate_threat_score_enhanced(zombie);
					
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

// Check how many bots are targeting a specific zombie
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

// PRIORITY 3: Tactical Positioning System
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

// Calculate angle spread to detect funnel points
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

// Check if position has nearby cover
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

// Integration helper - Use enhanced threat scoring in combat
bot_best_enemy_with_coordination()
{
	enemies = getaispeciesarray(level.zombie_team, "all");
	
	if(!isDefined(enemies) || enemies.size == 0)
		return 0;
		
	best_enemy = undefined;
	best_score = -1;
	
	foreach(enemy in enemies)
	{
		if(!isDefined(enemy) || !isalive(enemy))
			continue;
			
		if(!self botsighttracepassed(enemy))
			continue;
			
		// Calculate enhanced threat score with player protection
		score = bot_calculate_threat_score_enhanced(enemy);
		
		// Reduce score for targets already being engaged
		contention = bot_get_target_contention(enemy);
		score -= (contention * 150);
		
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

// Helper function from original bot code
bot_dot_product(origin)
{
	angles = self getplayerangles();
	forward = anglesToForward(angles);
	delta = origin - self getplayercamerapos();
	delta = vectornormalize(delta);
	dot = vectordot(forward, delta);
	return dot;
}