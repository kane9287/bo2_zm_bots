// T6 GSC SOURCE
// Compiler version 0 (prec2)
// Enhanced AI Bot System with Performance Optimizations
// TranZit Bus Awareness Added

#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\zombies\_zm_powerups;
#include maps\mp\zombies\_zm_perks;
#include scripts\zm\zm_bo2_bots_combat;
#include scripts\zm\zm_bo2_bots_utility;

// Bot action constants
#define BOT_ACTION_STAND "stand"
#define BOT_ACTION_CROUCH "crouch"
#define BOT_ACTION_PRONE "prone"

// Goal priority constants
#define BOT_GOAL_PRIORITY_LOW 1
#define BOT_GOAL_PRIORITY_NORMAL 2
#define BOT_GOAL_PRIORITY_HIGH 3
#define BOT_GOAL_PRIORITY_CRITICAL 4
#define BOT_GOAL_PRIORITY_EMERGENCY 5

bot_spawn()
{
	self bot_spawn_init();
	self thread bot_main();
	self thread bot_check_player_blocking();
	self thread bot_give_starting_perks();
	
	// TranZit bus awareness
	if(level.script == "zm_transit")
		self thread bot_bus_navigation();
}

// Give bots Quick Revive and Juggernog at spawn
bot_give_starting_perks()
{
	self endon("disconnect");
	self endon("death");
	
	wait 2;
	
	if(!self HasPerk("specialty_quickrevive"))
	{
		self thread maps\mp\zombies\_zm_perks::give_perk("specialty_quickrevive");
		wait 0.5;
	}
	
	if(!self HasPerk("specialty_armorvest"))
		self thread maps\mp\zombies\_zm_perks::give_perk("specialty_armorvest");
}

array_combine(array1, array2)
{
	if(!isDefined(array1))
		array1 = [];
	if(!isDefined(array2))
		array2 = [];

	foreach(item in array2)
		array1[array1.size] = item;

	return array1;
}

init()
{
	bot_set_skill();

	flag_wait("initial_blackscreen_passed");

	if(!isdefined(level.using_bot_weapon_logic))
		level.using_bot_weapon_logic = 1;
	if(!isdefined(level.using_bot_revive_logic))
		level.using_bot_revive_logic = 1;

	// Initialize box and PAP usage variables
	level.box_in_use_by_bot = undefined;
	level.last_bot_box_interaction_time = 0;
	level.pap_in_use_by_bot = undefined;
	level.last_bot_pap_time = 0;
	level.generator_in_use_by_bot = undefined;
	level.last_bot_generator_time = 0;

	if(!isdefined(level.bots))
		level.bots = [];

	bot_amount = GetDvarIntDefault("bo2_zm_bots_count", 2);

	for(i=0; i<bot_amount; i++)
	{
		bot_entity = spawn_bot();
		level.bots[level.bots.size] = bot_entity;
		wait 1;
	}

	// Initialize map specific logic
	if(level.script == "zm_tomb")
		level thread scripts\zm\zm_bo2_bots_origins::init();
}

bot_set_skill()
{
	// Veteran-level settings for maximum combat effectiveness
	setdvar("bot_MinDeathTime", "100");
	setdvar("bot_MaxDeathTime", "200");
	setdvar("bot_MinFireTime", "50");
	setdvar("bot_MaxFireTime", "150");
	setdvar("bot_PitchUp", "-5");
	setdvar("bot_PitchDown", "10");
	setdvar("bot_Fov", "180");
	setdvar("bot_MinAdsTime", "1500");
	setdvar("bot_MaxAdsTime", "2500");
	setdvar("bot_MinCrouchTime", "100");
	setdvar("bot_MaxCrouchTime", "400");
	setdvar("bot_TargetLeadBias", "1");
	setdvar("bot_MinReactionTime", "10");
	setdvar("bot_MaxReactionTime", "30");
	setdvar("bot_StrafeChance", "1");
	setdvar("bot_MinStrafeTime", "2000");
	setdvar("bot_MaxStrafeTime", "4000");
	setdvar("scr_help_dist", "512");
	setdvar("bot_AllowGrenades", "1");
	setdvar("bot_MinGrenadeTime", "1500");
	setdvar("bot_MaxGrenadeTime", "4000");
	setdvar("bot_MeleeDist", "70");
	setdvar("bot_YawSpeed", "6");
	setdvar("bot_SprintDistance", "256");
}

botaction(stance)
{
	switch(stance)
	{
		case BOT_ACTION_STAND:
			self allowstand(true);
			self allowcrouch(false);
			self allowprone(false);
			break;
		
		case BOT_ACTION_CROUCH:
			self allowstand(false);
			self allowcrouch(true);
			self allowprone(false);
			break;
			
		case BOT_ACTION_PRONE:
			self allowstand(false);
			self allowcrouch(false);
			self allowprone(true);
			break;
			
		default:
			self allowstand(true);
			self allowcrouch(true);
			self allowprone(true);
			break;
	}
}

bot_get_closest_enemy(origin)
{
	enemies = getaispeciesarray(level.zombie_team, "all");
	enemies = arraysort(enemies, origin);
	
	if(enemies.size >= 1)
		return enemies[0];
		
	return undefined;
}

// TranZit bus navigation
bot_bus_navigation()
{
	self endon("disconnect");
	level endon("end_game");
	
	// Wait for bot initialization
	while(!isDefined(self.bot))
		wait 0.05;
	
	// Initialize bus awareness
	self.bot.bus_nearby = false;
	self.bot.bus_location = undefined;
	
	while(true)
	{
		wait 10;
		
		if(!self.is_bot)
			continue;
		
		// Check if bus exists and is nearby
		bus = get_closest_bus();
		
		if(!isDefined(bus))
		{
			self.bot.bus_nearby = false;
			self.bot.bus_location = undefined;
			continue;
		}
		
		distance_to_bus = distance(self.origin, bus.origin);
		
		// If bus is close, set awareness flags
		if(distance_to_bus < 500)
		{
			self.bot.bus_nearby = true;
			self.bot.bus_location = bus.origin;
		}
		else
		{
			self.bot.bus_nearby = false;
			self.bot.bus_location = undefined;
		}
	}
}

get_closest_bus()
{
	// Find the bus entity
	buses = getEntArray("transit_bus", "targetname");
	
	if(!isDefined(buses) || buses.size == 0)
		return undefined;
	
	return buses[0];
}

bot_buy_box()
{
	// Try every 1.5 seconds (reduced from 3s)
	if(!isDefined(self.bot.box_purchase_time) || GetTime() > self.bot.box_purchase_time)
	{
		self.bot.box_purchase_time = GetTime() + 1500;

		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			return;

		if(self.score < 950)
			return;

		if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot != self)
			return;

		// Reduced global cooldown from 30s to 10s
		if(isDefined(level.last_bot_box_interaction_time) && (GetTime() - level.last_bot_box_interaction_time < 10000))
			return;

		// Reduced personal cooldown from 15s to 5s
		if(isDefined(self.bot.last_box_interaction_time) && (GetTime() - self.bot.last_box_interaction_time < 5000))
			return;

		// Logic to grab from an already open box
		if(!isDefined(self.bot.grab_weapon_time) || GetTime() > self.bot.grab_weapon_time)
		{
			activeBox = undefined;
			closestOpenBoxDistSq = 999999;

			foreach(box in level.chests)
			{
				if(!isDefined(box))
					continue;

				if(isDefined(box._box_open) && box._box_open &&
				   isDefined(box.weapon_out) && box.weapon_out &&
				   isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_model))
				{
					dist_sq = DistanceSquared(self.origin, box.origin);
					if(dist_sq < closestOpenBoxDistSq)
					{
						if(FindPath(self.origin, box.origin, undefined, 0, 1))
						{
							closestOpenBoxDistSq = dist_sq;
							activeBox = box;
						}
					}
				}
			}

			if(isDefined(activeBox))
			{
				if(closestOpenBoxDistSq < 10000) // 100^2
				{
					if(self hasgoal("boxGrab") || self hasgoal("boxBuy"))
					{
						self cancelgoal("boxGrab");
						self cancelgoal("boxBuy");
					}

					self.bot.grab_weapon_time = GetTime() + 5000;

					aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
					self lookat(activeBox.origin + aim_offset);
					wait randomfloatrange(0.3, 0.8);

					if(!isDefined(activeBox) || !isDefined(activeBox._box_open) || !activeBox._box_open ||
					   !isDefined(activeBox.weapon_out) || !activeBox.weapon_out ||
					   self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
					{
						return;
					}

					currentWeapon = self GetCurrentWeapon();
					boxWeapon = activeBox.zbarrier.weapon_string;
					shouldTake = bot_should_take_weapon(boxWeapon, currentWeapon);

					if(shouldTake)
					{
						if(isDefined(boxWeapon) && !self HasWeapon(boxWeapon))
						{
							primaries = self GetWeaponsListPrimaries();
							if(primaries.size >= 2)
							{
								dropWeapon = currentWeapon;
								foreach(weapon in primaries)
								{
									if(weapon != currentWeapon && !IsSubStr(weapon, "raygun") && !IsSubStr(weapon, "thunder") && 
									   !IsSubStr(weapon, "wave") && !IsSubStr(weapon, "tesla") && !IsSubStr(weapon, "staff"))
									{
										dropWeapon = weapon;
										break;
									}
								}
								self TakeWeapon(dropWeapon);
							}
							self GiveWeapon(boxWeapon);
							self SwitchToWeapon(boxWeapon);
							self SetSpawnWeapon(boxWeapon);
							activeBox.weapon_out = 0;
							activeBox notify("weapon_grabbed");
							self PlaySound("zmb_weap_pickup");
						}
						else
						{
							if(isDefined(activeBox.unitrigger_stub) && isDefined(activeBox.unitrigger_stub.trigger))
								activeBox.unitrigger_stub.trigger notify("trigger", self);
							else
								activeBox notify("trigger", self);
						}
					}
					else
					{
						self.bot.grab_weapon_time = GetTime() + 7000;
					}

					self.bot.last_box_interaction_time = GetTime();
					if(isDefined(activeBox.chest_user) && activeBox.chest_user == self)
						activeBox.chest_user = undefined;

					return;
				}
				else if(closestOpenBoxDistSq < 640000) // 800^2 (increased from 500)
				{
					if(!self hasgoal("boxGrab"))
						self AddGoal(activeBox.origin, 75, BOT_GOAL_PRIORITY_HIGH, "boxGrab");
					return;
				}
			}
		}

		// Logic to buy a new box spin
		if(is_true(self.bot.waiting_for_box_animation))
		{
			if((!isDefined(self.bot.box_payment_time) || (GetTime() - self.bot.payment_time > 10000)))
			{
				self.bot.waiting_for_box_animation = undefined;
				self.bot.current_box = undefined;
				if(level.box_in_use_by_bot == self)
					level.box_in_use_by_bot = undefined;
			}
			else
			{
				return;
			}
		}

		if(!isDefined(level.chests) || level.chests.size == 0 || !isDefined(level.chest_index) || level.chest_index >= level.chests.size)
			return;

		current_box = level.chests[level.chest_index];
		if(!isDefined(current_box) || !isDefined(current_box.origin))
			return;

		if(is_true(current_box._box_open) ||
		   flag("moving_chest_now") ||
		   (isDefined(current_box.is_locked) && current_box.is_locked) ||
		   (isDefined(current_box.chest_user) && current_box.chest_user != self) ||
		   (isDefined(level.mystery_box_teddy_locations) && array_contains(level.mystery_box_teddy_locations, current_box.origin)))
		{
			return;
		}

		dist_sq = DistanceSquared(self.origin, current_box.origin);
		interaction_dist_sq = 10000; // 100^2
		detection_dist_sq = 640000; // 800^2 (increased from 500)

		if(self.score >= 950 && dist_sq < detection_dist_sq)
		{
			if(FindPath(self.origin, current_box.origin, undefined, 0, 1))
			{
				if(dist_sq > interaction_dist_sq)
				{
					if(!self hasgoal("boxBuy") || DistanceSquared(self GetGoal("boxBuy"), current_box.origin) > 2500)
						self AddGoal(current_box.origin, 75, BOT_GOAL_PRIORITY_NORMAL, "boxBuy");
					return;
				}

				if(self hasgoal("boxBuy"))
					self cancelgoal("boxBuy");

				aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
				self lookat(current_box.origin + aim_offset);
				wait randomfloatrange(0.5, 1.0);

				if(self.score < 950 ||
				   is_true(current_box._box_open) ||
				   flag("moving_chest_now") ||
				   (isDefined(current_box.is_locked) && current_box.is_locked) ||
				   (isDefined(current_box.chest_user) && current_box.chest_user != self) ||
				   self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
				{
					return;
				}

				level.box_in_use_by_bot = self;
				current_box.chest_user = self;

				self.bot.current_box = current_box;
				self.bot.waiting_for_box_animation = true;
				self.bot.box_payment_time = GetTime();

				self maps\mp\zombies\_zm_score::minus_to_player_score(950);
				self PlaySound("zmb_cha_ching");

				self.bot.last_box_interaction_time = GetTime();
				level.last_bot_box_interaction_time = GetTime();

				if(isDefined(current_box.unitrigger_stub) && isDefined(current_box.unitrigger_stub.trigger))
					current_box.unitrigger_stub.trigger notify("trigger", self);
				else if(isDefined(current_box.use_trigger))
					current_box.use_trigger notify("trigger", self);
				else
					current_box notify("trigger", self);

				self thread bot_monitor_box_animation(current_box);

				return;
			}
		}

		if(self hasgoal("boxBuy") || self hasgoal("boxGrab"))
		{
			self cancelgoal("boxBuy");
			self cancelgoal("boxGrab");
		}
	}
}

// Monitor box animation and weapon decision
bot_monitor_box_animation(box)
{
	self endon("disconnect");
	self endon("death");
	level endon("game_ended");
	
	wait 0.5;
	
	// Wait for weapon to appear or timeout after 8 seconds
	start_time = GetTime();
	while(GetTime() - start_time < 8000)
	{
		if(!isDefined(box) || !isDefined(box._box_open) || !box._box_open)
			break;
			
		if(isDefined(box.weapon_out) && box.weapon_out && isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_string))
			break;
			
		wait 0.1;
	}
	
	// Clean up state
	self.bot.waiting_for_box_animation = undefined;
	if(level.box_in_use_by_bot == self)
		level.box_in_use_by_bot = undefined;
	
	// Weapon should now be visible, try to grab it
	if(isDefined(box) && isDefined(box.weapon_out) && box.weapon_out && isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_string))
	{
		boxWeapon = box.zbarrier.weapon_string;
		currentWeapon = self GetCurrentWeapon();
		shouldTake = bot_should_take_weapon(boxWeapon, currentWeapon);
		
		if(shouldTake)
		{
			self lookat(box.origin);
			wait 0.2;
			
			if(isDefined(boxWeapon) && !self HasWeapon(boxWeapon))
			{
				primaries = self GetWeaponsListPrimaries();
				if(primaries.size >= 2)
				{
					dropWeapon = currentWeapon;
					foreach(weapon in primaries)
					{
						if(weapon != currentWeapon && !IsSubStr(weapon, "raygun") && !IsSubStr(weapon, "thunder") && 
						   !IsSubStr(weapon, "wave") && !IsSubStr(weapon, "tesla") && !IsSubStr(weapon, "staff"))
						{
							dropWeapon = weapon;
							break;
						}
					}
					self TakeWeapon(dropWeapon);
				}
				self GiveWeapon(boxWeapon);
				self SwitchToWeapon(boxWeapon);
				self SetSpawnWeapon(boxWeapon);
				box.weapon_out = 0;
				box notify("weapon_grabbed");
				self PlaySound("zmb_weap_pickup");
			}
			else
			{
				if(isDefined(box.unitrigger_stub) && isDefined(box.unitrigger_stub.trigger))
					box.unitrigger_stub.trigger notify("trigger", self);
				else
					box notify("trigger", self);
			}
		}
	}
	
	if(isDefined(box.chest_user) && box.chest_user == self)
		box.chest_user = undefined;
}

// Weapon decision logic
bot_should_take_weapon(boxWeapon, currentWeapon)
{
	if(!isDefined(boxWeapon))
		return false;
		
	if(self HasWeapon(boxWeapon))
		return false;
		
	// Wonder weapons - always take
	if(IsSubStr(boxWeapon, "raygun") || IsSubStr(boxWeapon, "thunder") || 
	   IsSubStr(boxWeapon, "wave") || IsSubStr(boxWeapon, "tesla") || IsSubStr(boxWeapon, "staff"))
		return true;
		
	// Check if upgraded
	is_upgraded = IsSubStr(boxWeapon, "_upgraded");
	
	// If current weapon is starting pistol, take anything
	if(IsSubStr(currentWeapon, "m1911") || IsSubStr(currentWeapon, "pistol"))
		return true;
		
	// Prefer upgraded weapons
	if(is_upgraded)
		return true;
		
	// Check weapon class priority
	box_class = WeaponClass(boxWeapon);
	current_class = WeaponClass(currentWeapon);
	
	// Prefer assault rifles and LMGs
	if((box_class == "rifle" || box_class == "mg") && (current_class == "smg" || current_class == "pistol"))
		return true;
		
	return false;
}

bot_main()
{
	self endon("disconnect");
	self endon("death");
	level endon("game_ended");
	
	// Initialize check times
	self.bot.last_perk_check = 0;
	self.bot.last_weapon_check = 0;
	self.bot.last_pap_check = 0;
	self.bot.last_door_check = 0;
	self.bot.last_debris_check = 0;
	
	// Entity caches
	self.bot.cached_doors = [];
	self.bot.cached_debris = [];
	self.bot.cached_perks = [];
	self.bot.cache_refresh_time = 0;
	
	for(;;)
	{
		// Refresh entity caches every 30 seconds
		if(GetTime() > self.bot.cache_refresh_time)
		{
			self bot_refresh_entity_caches();
			self.bot.cache_refresh_time = GetTime() + 30000;
		}
		
		// Perk buying (check every 5 seconds)
		if(GetTime() > self.bot.last_perk_check)
		{
			self.bot.last_perk_check = GetTime() + 5000;
			self bot_buy_perks();
		}
		
		// Weapon management (check every 3 seconds)
		if(GetTime() > self.bot.last_weapon_check)
		{
			self.bot.last_weapon_check = GetTime() + 3000;
			
			if(is_true(level.using_bot_weapon_logic))
			{
				self bot_buy_weapon();
				self bot_buy_ammo();
				self bot_buy_box();
			}
		}
		
		// PAP check (every 4 seconds)
		if(GetTime() > self.bot.last_pap_check)
		{
			self.bot.last_pap_check = GetTime() + 4000;
			self bot_use_pap();
		}
		
		// Door/debris clearing (every 2 seconds)
		if(GetTime() > self.bot.last_door_check)
		{
			self.bot.last_door_check = GetTime() + 2000;
			self bot_open_nearest_door();
		}
		
		if(GetTime() > self.bot.last_debris_check)
		{
			self.bot.last_debris_check = GetTime() + 2000;
			self bot_clear_nearest_debris();
		}
		
		// Continuous tasks
		self bot_wander();
		
		wait 0.1;
	}
}

// Refresh entity caches
bot_refresh_entity_caches()
{
	self.bot.cached_doors = GetEntArray("zombie_door", "targetname");
	self.bot.cached_debris = GetEntArray("zombie_debris", "targetname");
	
	// Cache perk machines
	self.bot.cached_perks = [];
	if(isDefined(level._custom_perks))
	{
		foreach(perk, v in level._custom_perks)
		{
			if(isDefined(level._custom_perks[perk].machine))
				self.bot.cached_perks[self.bot.cached_perks.size] = level._custom_perks[perk].machine;
		}
	}
}

bot_buy_perks()
{
	if(!flag("power_on"))
		return;
		
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return;
		
	// Priority order for perks
	perk_priority = array("specialty_quickrevive", "specialty_armorvest", "specialty_fastreload", "specialty_rof");
	
	foreach(perk in perk_priority)
	{
		if(!self HasPerk(perk))
		{
			self bot_buy_specific_perk(perk);
			break;
		}
	}
}

bot_buy_specific_perk(perk_name)
{
	if(!isDefined(level._custom_perks) || !isDefined(level._custom_perks[perk_name]))
		return;
		
	machine = level._custom_perks[perk_name].machine;
	
	if(!isDefined(machine) || !isDefined(machine.origin))
		return;
		
	cost = level._custom_perks[perk_name].cost;
	
	if(self.score < cost)
		return;
		
	dist_sq = DistanceSquared(self.origin, machine.origin);
	
	if(dist_sq > 640000) // 800^2
		return;
		
	if(dist_sq > 10000) // 100^2
	{
		if(!self hasgoal("perk"))
			self AddGoal(machine.origin, 75, BOT_GOAL_PRIORITY_NORMAL, "perk");
	}
	else
	{
		if(self hasgoal("perk"))
			self cancelgoal("perk");
			
		self lookat(machine.origin);
		wait 0.5;
		
		self thread maps\mp\zombies\_zm_perks::give_perk(perk_name);
	}
}

bot_buy_weapon()
{
	// Implementation placeholder
}

bot_buy_ammo()
{
	// Implementation placeholder
}

bot_use_pap()
{
	// Implementation placeholder
}

bot_open_nearest_door()
{
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return;
		
	closest_door = undefined;
	closest_dist_sq = 999999;
	
	foreach(door in self.bot.cached_doors)
	{
		if(!isDefined(door) || !isDefined(door.origin))
			continue;
			
		dist_sq = DistanceSquared(self.origin, door.origin);
		
		if(dist_sq < closest_dist_sq && dist_sq < 90000) // 300^2
		{
			closest_dist_sq = dist_sq;
			closest_door = door;
		}
	}
	
	if(isDefined(closest_door))
	{
		cost = 1000;
		if(isDefined(closest_door.zombie_cost))
			cost = closest_door.zombie_cost;
			
		if(self.score >= cost)
		{
			if(closest_dist_sq > 10000) // 100^2
			{
				if(!self hasgoal("door"))
					self AddGoal(closest_door.origin, 50, BOT_GOAL_PRIORITY_LOW, "door");
			}
			else
			{
				if(self hasgoal("door"))
					self cancelgoal("door");
					
				self lookat(closest_door.origin);
				wait 0.2;
				
				if(isDefined(closest_door.unitrigger_stub) && isDefined(closest_door.unitrigger_stub.trigger))
					closest_door.unitrigger_stub.trigger notify("trigger", self);
				else
					closest_door notify("trigger", self);
			}
		}
	}
}

bot_clear_nearest_debris()
{
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return;
		
	closest_debris = undefined;
	closest_dist_sq = 999999;
	
	foreach(debris in self.bot.cached_debris)
	{
		if(!isDefined(debris) || !isDefined(debris.origin))
			continue;
			
		dist_sq = DistanceSquared(self.origin, debris.origin);
		
		if(dist_sq < closest_dist_sq && dist_sq < 90000) // 300^2
		{
			closest_dist_sq = dist_sq;
			closest_debris = debris;
		}
	}
	
	if(isDefined(closest_debris))
	{
		cost = 1000;
		if(isDefined(closest_debris.zombie_cost))
			cost = closest_debris.zombie_cost;
			
		if(self.score >= cost)
		{
			if(closest_dist_sq > 10000) // 100^2
			{
				if(!self hasgoal("debris"))
					self AddGoal(closest_debris.origin, 50, BOT_GOAL_PRIORITY_LOW, "debris");
			}
			else
			{
				if(self hasgoal("debris"))
					self cancelgoal("debris");
					
				self lookat(closest_debris.origin);
				wait 0.2;
				
				if(isDefined(closest_debris.unitrigger_stub) && isDefined(closest_debris.unitrigger_stub.trigger))
					closest_debris.unitrigger_stub.trigger notify("trigger", self);
				else
					closest_debris notify("trigger", self);
			}
		}
	}
}

bot_wander()
{
	if(self hasgoal("wander"))
		return;
		
	nodes = GetNodesInRadius(self.origin, 512, 0);
	
	if(nodes.size > 0)
	{
		random_node = nodes[randomint(nodes.size)];
		self AddGoal(random_node.origin, 128, BOT_GOAL_PRIORITY_LOW, "wander");
	}
}
