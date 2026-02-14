// T6 GSC SOURCE
// Compiler version 0 (prec2)

#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\zombies\_zm_powerups;
#include scripts\zm\zm_bo2_bots_combat;
#include scripts\zm\zm_bo2_bots_utility;

// Bot action constants
#define BOT_ACTION_STAND "stand"
#define BOT_ACTION_CROUCH "crouch"
#define BOT_ACTION_PRONE "prone"

// Bot goal priorities
#define BOT_GOAL_PRIORITY_FLEE 4
#define BOT_GOAL_PRIORITY_REVIVE 4
#define BOT_GOAL_PRIORITY_BOX_GRAB 3
#define BOT_GOAL_PRIORITY_BOX_BUY 2
#define BOT_GOAL_PRIORITY_WEAPON 2
#define BOT_GOAL_PRIORITY_PAP 2
#define BOT_GOAL_PRIORITY_POWERUP 2
#define BOT_GOAL_PRIORITY_WANDER 1

init()
{
	iprintln("^3Waiting for initial blackscreen...");
	flag_wait("initial_blackscreen_passed");
	iprintln("^2Blackscreen passed, continuing bot setup...");

	bot_set_skill();
	
	// Initialize bot systems
	if(!isdefined(level.using_bot_weapon_logic))
		level.using_bot_weapon_logic = 1;
	if(!isdefined(level.using_bot_revive_logic))
		level.using_bot_revive_logic = 1;

	// Initialize global tracking variables
	level.box_in_use_by_bot = undefined;
	level.last_bot_box_interaction_time = 0;
	level.pap_in_use_by_bot = undefined;
	level.last_bot_pap_time = 0;
	level.generator_in_use_by_bot = undefined;
	level.last_bot_generator_time = 0;
	level.mystery_box_teddy_locations = [];

	// Cache entity arrays for performance
	level thread cache_entity_arrays();

	// Setup bot tracking array
	if(!isdefined(level.bots))
		level.bots = [];

	bot_amount = GetDvarIntDefault("bo2_zm_bots_count", 8);
	iprintln("^2Spawning " + bot_amount + " bots...");

	for(i=0; i<bot_amount; i++)
	{
		iprintln("^3Spawning bot " + (i+1));
		bot_entity = spawn_bot();
		level.bots[level.bots.size] = bot_entity;
		wait 1;
	}

	// Initialize map specific logic
	if(level.script == "zm_tomb")
	{
		level thread scripts\zm\zm_bo2_bots_origins::init();
	}

	iprintln("^2Bot initialization complete");
}

cache_entity_arrays()
{
	level endon("end_game");
	wait 2; // Wait for game to fully initialize
	
	level.cached_zombie_doors = GetEntArray("zombie_door", "targetname");
	level.cached_zombie_debris = GetEntArray("zombie_debris", "targetname");
	level.cached_perk_machines = GetEntArray("zombie_vending", "targetname");
	
	// Update cache periodically in case new entities spawn
	while(1)
	{
		wait 30;
		level.cached_zombie_doors = GetEntArray("zombie_door", "targetname");
		level.cached_zombie_debris = GetEntArray("zombie_debris", "targetname");
	}
}

bot_set_skill()
{
	setdvar("bot_MinDeathTime", "250");
	setdvar("bot_MaxDeathTime", "500");
	setdvar("bot_MinFireTime", "100");
	setdvar("bot_MaxFireTime", "250");
	setdvar("bot_PitchUp", "-5");
	setdvar("bot_PitchDown", "10");
	setdvar("bot_Fov", "160");
	setdvar("bot_MinAdsTime", "3000");
	setdvar("bot_MaxAdsTime", "5000");
	setdvar("bot_MinCrouchTime", "100");
	setdvar("bot_MaxCrouchTime", "400");
	setdvar("bot_TargetLeadBias", "2");
	setdvar("bot_MinReactionTime", "40");
	setdvar("bot_MaxReactionTime", "70");
	setdvar("bot_StrafeChance", "1");
	setdvar("bot_MinStrafeTime", "3000");
	setdvar("bot_MaxStrafeTime", "6000");
	setdvar("scr_help_dist", "512");
	setdvar("bot_AllowGrenades", "1");
	setdvar("bot_MinGrenadeTime", "1500");
	setdvar("bot_MaxGrenadeTime", "4000");
	setdvar("bot_MeleeDist", "70");
	setdvar("bot_YawSpeed", "4");
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

bot_spawn()
{
	self bot_spawn_init();
	self thread bot_main();
	self thread bot_check_player_blocking();
}

spawn_bot()
{
	bot = addtestclient();
	if(!isDefined(bot))
		return;
	
	bot waittill("spawned_player");
	bot thread maps\mp\zombies\_zm::spawnspectator();
	
	if(isDefined(bot))
	{
		bot.pers["isBot"] = 1;
		bot thread onspawn();
	}
	
	wait 1;
	
	if(isDefined(level.spawnplayer))
		bot [[level.spawnplayer]]();
	
	return bot;
}

bot_spawn_init()
{
	if(level.script == "zm_tomb")
	{
		self SwitchToWeapon("c96_zm");
		self SetSpawnWeapon("c96_zm");
	}
	self SwitchToWeapon("m1911_zm");
	self SetSpawnWeapon("m1911_zm");
	
	time = getTime();
	if(!isDefined(self.bot))
	{
		self.bot = spawnstruct();
		self.bot.threat = spawnstruct();
	}
	
	self.bot.glass_origin = undefined;
	self.bot.ignore_entity = [];
	self.bot.previous_origin = self.origin;
	self.bot.time_ads = 0;
	self.bot.update_c4 = time + randomintrange(1000, 3000);
	self.bot.update_crate = time + randomintrange(1000, 3000);
	self.bot.update_crouch = time + randomintrange(1000, 3000);
	self.bot.update_failsafe = time + randomintrange(1000, 3000);
	self.bot.update_idle_lookat = time + randomintrange(1000, 3000);
	self.bot.update_killstreak = time + randomintrange(1000, 3000);
	self.bot.update_lookat = time + randomintrange(1000, 3000);
	self.bot.update_objective = time + randomintrange(1000, 3000);
	self.bot.update_objective_patrol = time + randomintrange(1000, 3000);
	self.bot.update_patrol = time + randomintrange(1000, 3000);
	self.bot.update_toss = time + randomintrange(1000, 3000);
	self.bot.update_launcher = time + randomintrange(1000, 3000);
	self.bot.update_weapon = time + randomintrange(1000, 3000);
	self.bot.think_interval = 0.1;
	self.bot.fov = -0.9396;
	self.bot.threat.entity = undefined;
	self.bot.threat.position = (0, 0, 0);
	self.bot.threat.time_first_sight = 0;
	self.bot.threat.time_recent_sight = 0;
	self.bot.threat.time_aim_interval = 0;
	self.bot.threat.time_aim_correct = 0;
	self.bot.threat.update_riotshield = 0;
	
	// Initialize time-based check variables
	self.bot.next_perk_check = 0;
	self.bot.next_weapon_check = 0;
	self.bot.next_pap_check = 0;
	self.bot.next_door_check = 0;
	self.bot.next_debris_check = 0;
	self.bot.next_box_check = 0;
}

bot_main()
{
	self endon("death");
	self endon("disconnect");
	level endon("game_ended");

	self thread bot_wakeup_think();
	self thread bot_damage_think();
	self thread bot_reset_flee_goal();
	self thread bot_manage_ammo();
	
	if(level.script == "zm_tomb")
		self thread bot_origins_think();

	for(;;)
	{
		self waittill("wakeup", damage, attacker, direction);
		
		if(self isremotecontrolling())
		{
			continue;
		}
		
		// Check if in laststand first
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			wait_network_frame();
			continue;
		}
		
		time = getTime();
		
		// Combat and movement
		self bot_combat_think(damage, attacker, direction);
		self bot_update_follow_host();
		self bot_update_lookat();
		self bot_teleport_think();
		
		// Revive logic (highest priority)
		if(is_true(level.using_bot_revive_logic))
		{
			self bot_revive_teammates();
		}
		
		// Powerup pickup
		self bot_pickup_powerup();
		
		// Time-based weapon/equipment checks
		if(is_true(level.using_bot_weapon_logic))
		{
			if(time > self.bot.next_perk_check)
			{
				self bot_buy_perks();
				self.bot.next_perk_check = time + 4000;
			}
			
			if(time > self.bot.next_weapon_check)
			{
				self bot_buy_wallbuy();
				self.bot.next_weapon_check = time + 3000;
			}
			
			if(time > self.bot.next_pap_check)
			{
				self bot_pack_gun();
				self.bot.next_pap_check = time + 5000;
			}
			
			if(time > self.bot.next_box_check)
			{
				self bot_buy_box();
				self.bot.next_box_check = time + 3000;
			}
		}
		
		// Door and debris (lower priority)
		if(time > self.bot.next_door_check)
		{
			self bot_buy_door();
			self.bot.next_door_check = time + 5000;
		}
		
		if(time > self.bot.next_debris_check)
		{
			self bot_clear_debris();
			self.bot.next_debris_check = time + 4000;
		}
		
		// Origins specific
		if(level.script == "zm_tomb")
		{
			self thread scripts\zm\zm_bo2_bots_origins::bot_activate_generator();
		}
	}
}

bot_buy_perks()
{
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return;
		
	perks = array("specialty_armorvest", "specialty_quickrevive", "specialty_fastreload", "specialty_rof", "specialty_longersprint", "specialty_deadshot", "specialty_additionalprimaryweapon");
	costs = array(2500, 1500, 3000, 2000, 2000, 1500, 4000);
	
	if(!isDefined(level.cached_perk_machines))
		return;
	
	foreach(machine in level.cached_perk_machines)
	{
		if(!isDefined(machine.script_noteworthy))
			continue;
		
		if(DistanceSquared(machine.origin, self.origin) > 122500) // 350^2
			continue;
			
		for(i = 0; i < perks.size; i++)
		{
			if(machine.script_noteworthy == perks[i])
			{
				if(!self HasPerk(perks[i]) && self.score >= costs[i])
				{
					self maps\mp\zombies\_zm_score::minus_to_player_score(costs[i]);
					self thread maps\mp\zombies\_zm_perks::give_perk(perks[i]);
					return;
				}
			}
		}
	}
}

bot_buy_wallbuy()
{
	self endon("death");
	self endon("disconnect");
	level endon("end_game");
	
	if(self maps\mp\zombies\_zm_weapons::has_weapon_or_upgrade("mp5k_zm") || 
	   self maps\mp\zombies\_zm_weapons::has_weapon_or_upgrade("pdw57_zm") || 
	   self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		self CancelGoal("weaponBuy");
		return;
	}
	
	weapon = self GetCurrentWeapon();
	weaponToBuy = undefined;
	wallbuys = array_randomize(level._spawned_wallbuys);
	
	foreach(wallbuy in wallbuys)
	{
		dist_sq = DistanceSquared(wallbuy.origin, self.origin);
		if(dist_sq < 160000 && // 400^2
		   wallbuy.trigger_stub.cost <= self.score && 
		   bot_best_gun(wallbuy.trigger_stub.zombie_weapon_upgrade, weapon) && 
		   FindPath(self.origin, wallbuy.origin, undefined, 0, 1) && 
		   weapon != wallbuy.trigger_stub.zombie_weapon_upgrade && 
		   !is_offhand_weapon(wallbuy.trigger_stub.zombie_weapon_upgrade))
		{
			if(!isdefined(wallbuy.trigger_stub) || !isdefined(wallbuy.trigger_stub.zombie_weapon_upgrade))
				return;
			weaponToBuy = wallbuy;
			break;
		}
	}
	
	if(!isdefined(weaponToBuy))
		return;
	
	self AddGoal(weaponToBuy.origin, 75, BOT_GOAL_PRIORITY_WEAPON, "weaponBuy");
	
	while(!self AtGoal("weaponBuy") && DistanceSquared(self.origin, weaponToBuy.origin) > 10000)
	{
		wait_network_frame();
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			self cancelgoal("weaponBuy");
			return;
		}
	}
	
	self cancelgoal("weaponBuy");
	self maps\mp\zombies\_zm_score::minus_to_player_score(weaponToBuy.trigger_stub.cost);
	self TakeAllWeapons();
	self GiveWeapon(weaponToBuy.trigger_stub.zombie_weapon_upgrade);
	self SetSpawnWeapon(weaponToBuy.trigger_stub.zombie_weapon_upgrade);
}

bot_best_gun(buyingweapon, currentweapon)
{
	if(level.round_number >= 15)
	{
		priority_weapons = array("galil_zm", "an94_zm", "pdw57_zm", "mp5k_zm");
		foreach(weapon in priority_weapons)
		{
			if(buyingweapon == weapon)
				return true;
		}
	}
	else if(level.round_number >= 8)
	{
		if(buyingweapon == "pdw57_zm" || buyingweapon == "mp5k_zm")
			return true;
	}
	else
	{
		if(buyingweapon == "mp5k_zm")
			return true;
	}

	if(maps\mp\zombies\_zm_weapons::get_weapon_cost(buyingweapon) > maps\mp\zombies\_zm_weapons::get_weapon_cost(currentweapon))
		return true;
		
	return false;
}

bot_buy_box()
{
	time = getTime();
	
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand() || self.score < 950)
		return;

	// Check global usage
	if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot != self)
		return;

	// Global and personal cooldowns
	if(isDefined(level.last_bot_box_interaction_time) && (time - level.last_bot_box_interaction_time < 30000))
		return;

	if(isDefined(self.bot.last_box_interaction_time) && (time - self.bot.last_box_interaction_time < 15000))
		return;

	// Handle grab logic
	if(!isDefined(self.bot.grab_weapon_time) || time > self.bot.grab_weapon_time)
	{
		activeBox = bot_find_open_box();
		if(isDefined(activeBox))
		{
			dist_sq = DistanceSquared(self.origin, activeBox.origin);
			if(dist_sq < 10000) // 100^2
			{
				if(self hasgoal("boxGrab") || self hasgoal("boxBuy"))
				{
					self cancelgoal("boxGrab");
					self cancelgoal("boxBuy");
				}

				self.bot.grab_weapon_time = time + 5000;
				self lookat(activeBox.origin + (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5)));
				wait 0.05;

				if(!isDefined(activeBox) || !isDefined(activeBox._box_open) || !activeBox._box_open ||
				   !isDefined(activeBox.weapon_out) || !activeBox.weapon_out ||
				   self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
					return;

				boxWeapon = activeBox.zbarrier.weapon_string;
				currentWeapon = self GetCurrentWeapon();
				
				if(bot_should_take_weapon(boxWeapon, currentWeapon))
				{
					bot_take_box_weapon(activeBox, boxWeapon, currentWeapon);
				}
				
				self.bot.last_box_interaction_time = time;
				return;
			}
			else if(dist_sq < 250000) // 500^2
			{
				if(!self hasgoal("boxGrab"))
					self AddGoal(activeBox.origin, 75, BOT_GOAL_PRIORITY_BOX_GRAB, "boxGrab");
				return;
			}
		}
	}

	// Buy new box spin logic
	if(is_true(self.bot.waiting_for_box_animation))
	{
		if(!isDefined(self.bot.box_payment_time) || (time - self.bot.box_payment_time > 10000))
		{
			self.bot.waiting_for_box_animation = undefined;
			self.bot.current_box = undefined;
			if(level.box_in_use_by_bot == self)
				level.box_in_use_by_bot = undefined;
		}
		return;
	}

	current_box = bot_get_current_box();
	if(!isDefined(current_box))
		return;

	dist_sq = DistanceSquared(self.origin, current_box.origin);
	
	if(self.score >= 950 && dist_sq < 250000) // 500^2
	{
		if(FindPath(self.origin, current_box.origin, undefined, 0, 1))
		{
			if(dist_sq > 10000) // 100^2
			{
				if(!self hasgoal("boxBuy") || DistanceSquared(self GetGoal("boxBuy"), current_box.origin) > 2500)
					self AddGoal(current_box.origin, 75, BOT_GOAL_PRIORITY_BOX_BUY, "boxBuy");
				return;
			}

			if(self hasgoal("boxBuy"))
				self cancelgoal("boxBuy");

			self lookat(current_box.origin + (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5)));
			wait 0.05;

			if(self.score < 950 || is_true(current_box._box_open) || flag("moving_chest_now") ||
			   (isDefined(current_box.is_locked) && current_box.is_locked) ||
			   (isDefined(current_box.chest_user) && current_box.chest_user != self) ||
			   self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
				return;

			level.box_in_use_by_bot = self;
			current_box.chest_user = self;
			self.bot.current_box = current_box;
			self.bot.waiting_for_box_animation = true;
			self.bot.box_payment_time = time;

			self maps\mp\zombies\_zm_score::minus_to_player_score(950);
			self PlaySound("zmb_cha_ching");

			self.bot.last_box_interaction_time = time;
			level.last_bot_box_interaction_time = time;

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

bot_find_open_box()
{
	activeBox = undefined;
	closestOpenBoxDist = 99999;

	foreach(box in level.chests)
	{
		if(!isDefined(box))
			continue;

		if(isDefined(box._box_open) && box._box_open &&
		   isDefined(box.weapon_out) && box.weapon_out &&
		   isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_model))
		{
			dist = Distance(self.origin, box.origin);
			if(dist < closestOpenBoxDist)
			{
				if(FindPath(self.origin, box.origin, undefined, 0, 1))
				{
					closestOpenBoxDist = dist;
					activeBox = box;
				}
			}
		}
	}
	
	return activeBox;
}

bot_get_current_box()
{
	if(!isDefined(level.chests) || level.chests.size == 0 || !isDefined(level.chest_index) || level.chest_index >= level.chests.size)
		return undefined;

	current_box = level.chests[level.chest_index];
	if(!isDefined(current_box) || !isDefined(current_box.origin))
		return undefined;

	if(is_true(current_box._box_open) ||
	   flag("moving_chest_now") ||
	   (isDefined(current_box.is_locked) && current_box.is_locked) ||
	   (isDefined(current_box.chest_user) && current_box.chest_user != self) ||
	   (isDefined(level.mystery_box_teddy_locations) && array_contains(level.mystery_box_teddy_locations, current_box.origin)))
		return undefined;

	return current_box;
}

bot_take_box_weapon(box, boxWeapon, currentWeapon)
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
	
	if(isDefined(box.chest_user) && box.chest_user == self)
		box.chest_user = undefined;
}

bot_monitor_box_animation(box)
{
	self endon("disconnect");
	self endon("death");
	self endon("box_usage_complete");
	
	started = false;
	for(i = 0; i < 15; i++)
	{
		wait 0.2;
		if(!isDefined(box))
		{
			bot_cleanup_box_usage();
			return;
		}
		
		if(isDefined(box._box_open) && box._box_open)
		{
			started = true;
			break;
		}
	}
	
	if(!started)
	{
		bot_cleanup_box_usage();
		return;
	}
	
	weaponAppeared = false;
	for(i = 0; i < 30; i++)
	{
		wait 0.2;
		if(!isDefined(box) || !isDefined(box._box_open) || !box._box_open)
		{
			bot_cleanup_box_usage();
			return;
		}
		
		if(isDefined(box.weapon_out) && box.weapon_out && 
		   isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_model))
		{
			weaponAppeared = true;
			break;
		}
		
		if(isDefined(box.zbarrier) && isDefined(box.zbarrier.state) && box.zbarrier.state == "teddy_bear")
		{
			if(!array_contains(level.mystery_box_teddy_locations, box.origin))
				level.mystery_box_teddy_locations[level.mystery_box_teddy_locations.size] = box.origin;
			bot_cleanup_box_usage();
			return;
		}
	}
	
	self.bot.waiting_for_box_animation = undefined;
	
	if(!weaponAppeared)
	{
		bot_cleanup_box_usage();
		return;
	}
	
	wait randomfloatrange(0.5, 1.5);
	
	if(!isDefined(box) || !isDefined(box._box_open) || !box._box_open ||
	   !isDefined(box.weapon_out) || !box.weapon_out ||
	   self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		bot_cleanup_box_usage();
		return;
	}
	
	boxWeapon = undefined;
	if(isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_string))
		boxWeapon = box.zbarrier.weapon_string;
	
	currentWeapon = self GetCurrentWeapon();
	shouldTake = bot_should_take_weapon(boxWeapon, currentWeapon);
	
	self lookat(box.origin + (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5)));
	
	if(shouldTake)
	{
		bot_take_box_weapon(box, boxWeapon, currentWeapon);
		
		if(IsSubStr(boxWeapon, "raygun") || IsSubStr(boxWeapon, "thunder"))
		{
			if(randomfloat(1) > 0.5)
			{
				self botaction(BOT_ACTION_STAND);
				wait 0.2;
				self botaction(BOT_ACTION_CROUCH);
				wait 0.2;
				self botaction(BOT_ACTION_STAND);
			}
		}
	}
	
	bot_cleanup_box_usage();
}

bot_cleanup_box_usage()
{
	self.bot.current_box = undefined;
	
	if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot == self)
		level.box_in_use_by_bot = undefined;
	
	self notify("box_usage_complete");
}

bot_pack_gun()
{
	if(level.round_number <= 1 || !bot_should_pack())
		return;
		
	if(isDefined(level.pap_in_use_by_bot) && level.pap_in_use_by_bot != self)
		return;
	
	time = getTime();
	if(isDefined(level.last_bot_pap_time) && time - level.last_bot_pap_time < 40000)
		return;
		
	if(isDefined(self.bot.last_pap_time) && time - self.bot.last_pap_time < 30000)
		return;
	
	if(!isDefined(level.cached_perk_machines))
		return;
	
	closestPap = undefined;
	closestDist_sq = 250000; // 500^2
	
	foreach(pack in level.cached_perk_machines)
	{
		if(pack.script_noteworthy != "specialty_weapupgrade")
			continue;
			
		if(isDefined(pack.is_locked) && pack.is_locked)
			continue;
			
		if(isDefined(pack.pap_user) && pack.pap_user != self)
			continue;
			
		dist_sq = DistanceSquared(self.origin, pack.origin);
		if(dist_sq < closestDist_sq)
		{
			closestPap = pack;
			closestDist_sq = dist_sq;
		}
	}
	
	if(!isDefined(closestPap))
		return;
		
	if(closestDist_sq > 10000) // 100^2
	{
		if(FindPath(self.origin, closestPap.origin, undefined, 0, 1))
		{
			if(!self hasgoal("papBuy") || DistanceSquared(self GetGoal("papBuy"), closestPap.origin) > 2500)
				self AddGoal(closestPap.origin, 50, BOT_GOAL_PRIORITY_PAP, "papBuy");
			return;
		}
	}
	
	if(self hasgoal("papBuy"))
		self cancelgoal("papBuy");
		
	if(self.score < 5000)
		return;
		
	self lookat(closestPap.origin + (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5)));
	wait 0.05;
	
	level.pap_in_use_by_bot = self;
	closestPap.pap_user = self;
	
	self.bot.last_pap_time = time;
	level.last_bot_pap_time = time;
	
	self maps\mp\zombies\_zm_score::minus_to_player_score(5000);
	
	weapon = self GetCurrentWeapon();
	upgrade_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon(weapon);
	
	self PlaySound("zmb_cha_ching");
	
	if(isDefined(closestPap.unitrigger_stub) && isDefined(closestPap.unitrigger_stub.trigger))
		closestPap.unitrigger_stub.trigger notify("trigger", self);
	else if(isDefined(closestPap.use_trigger))
		closestPap.use_trigger notify("trigger", self);
	else
		closestPap notify("trigger", self);
	
	self thread bot_monitor_pap_upgrade(closestPap, weapon, upgrade_name);
}

bot_monitor_pap_upgrade(pap_machine, old_weapon, upgrade_name)
{
	self endon("disconnect");
	self endon("death");
	self endon("pap_complete");
	
	wait randomfloatrange(5, 6);
	
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		bot_cleanup_pap_usage(pap_machine);
		return;
	}
	
	self TakeWeapon(old_weapon);
	self GiveWeapon(upgrade_name);
	self SetSpawnWeapon(upgrade_name);
	self SwitchToWeapon(upgrade_name);
	
	self lookat(pap_machine.origin + (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5)));
	self PlaySound("zmb_weap_pickup");
	
	if(randomfloat(1) > 0.6)
	{
		if(randomfloat(1) > 0.5)
		{
			self botaction(BOT_ACTION_STAND);
			wait 0.2;
			self botaction(BOT_ACTION_CROUCH);
			wait 0.2;
			self botaction(BOT_ACTION_STAND);
		}
	}
	
	bot_cleanup_pap_usage(pap_machine);
}

bot_cleanup_pap_usage(pap_machine)
{
	if(isDefined(level.pap_in_use_by_bot) && level.pap_in_use_by_bot == self)
		level.pap_in_use_by_bot = undefined;
	
	if(isDefined(pap_machine.pap_user) && pap_machine.pap_user == self)
		pap_machine.pap_user = undefined;
		
	self notify("pap_complete");
}

bot_should_pack()
{
	if(maps\mp\zombies\_zm_weapons::can_upgrade_weapon(self GetCurrentWeapon()))
		return 1;
	return 0;
}

bot_buy_door()
{
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return false;
	
	if(!isDefined(level.cached_zombie_doors))
		return false;
	
	closestDoor = undefined;
	closestDist_sq = 90000; // 300^2

	foreach(door in level.cached_zombie_doors)
	{
		if(isDefined(door._door_open) && door._door_open)
			continue;
			
		if(isDefined(door.has_been_opened) && door.has_been_opened)
			continue;

		if(!isDefined(door.zombie_cost))
			door.zombie_cost = 1000;

		if(self.score < door.zombie_cost)
			continue;

		if(isDefined(door.script_noteworthy))
		{
			if(door.script_noteworthy == "electric_door" || door.script_noteworthy == "local_electric_door")
			{
				if(!flag("power_on"))
					continue;
			}
		}

		dist_sq = DistanceSquared(self.origin, door.origin);
		if(dist_sq < closestDist_sq)
		{
			closestDoor = door;
			closestDist_sq = dist_sq;
		}
	}

	if(isDefined(closestDoor))
	{
		if(randomfloat(1) < 0.15)
		{
			wait 0.05;
			return true;
		}

		self lookat(closestDoor.origin + (randomfloatrange(-5,5), randomfloatrange(-5,5), 0));
		wait 0.05;

		self maps\mp\zombies\_zm_score::minus_to_player_score(closestDoor.zombie_cost);
		
		if(isDefined(closestDoor.door_buy))
			closestDoor thread door_buy();
		else
			closestDoor thread maps\mp\zombies\_zm_blockers::door_opened(closestDoor.zombie_cost);
		
		closestDoor._door_open = 1;
		closestDoor.has_been_opened = 1;
		self PlaySound("zmb_cha_ching");
		return true;
	}
	return false;
}

bot_clear_debris()
{
	if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		return false;
	
	if(!isDefined(level.cached_zombie_debris) || level.cached_zombie_debris.size == 0)
		return false;
	
	closestDebris = undefined;
	closestDist_sq = 90000; // 300^2
	
	foreach(pile in level.cached_zombie_debris)
	{
		if(!isDefined(pile) || !isDefined(pile.origin))
			continue;
			
		if(isDefined(pile._door_open) && pile._door_open)
			continue;
		
		if(isDefined(pile.has_been_opened) && pile.has_been_opened)
			continue;
		
		if(!isDefined(pile.zombie_cost))
			pile.zombie_cost = 1000;
		
		if(self.score < pile.zombie_cost)
			continue;
		
		dist_sq = DistanceSquared(self.origin, pile.origin);
		if(dist_sq < closestDist_sq && FindPath(self.origin, pile.origin, undefined, 0, 1))
		{
			closestDebris = pile;
			closestDist_sq = dist_sq;
		}
	}
	
	if(isDefined(closestDebris))
	{
		if(closestDist_sq > 22500) // 150^2
		{
			self AddGoal(closestDebris.origin, 50, 2, "debrisClear");
			return false;
		}

		if(randomfloat(1) < 0.15)
		{
			wait 0.05;
			return true;
		}

		self lookat(closestDebris.origin + (randomfloatrange(-5,5), randomfloatrange(-5,5), 0));
		wait 0.05;
		
		self maps\mp\zombies\_zm_score::minus_to_player_score(closestDebris.zombie_cost);
		junk = getentarray(closestDebris.target, "targetname");
		closestDebris._door_open = 1;
		closestDebris.has_been_opened = 1;
		
		closestDebris notify("trigger", self);
		if(isDefined(closestDebris.trigger))
			closestDebris.trigger notify("trigger", self);
			
		if(isDefined(closestDebris.target))
		{
			targets = GetEntArray(closestDebris.target, "targetname");
			foreach(target in targets)
			{
				if(isDefined(target))
					target notify("trigger", self);
			}
		}
		
		if(isDefined(closestDebris.script_flag))
		{
			tokens = strtok(closestDebris.script_flag, ",");
			for(i = 0; i < tokens.size; i++)
				flag_set(tokens[i]);
		}

		play_sound_at_pos("purchase", closestDebris.origin);
		level notify("junk purchased");

		foreach(chunk in junk)
		{
			chunk connectpaths();
			
			if(isDefined(chunk.script_linkto))
			{
				struct = getstruct(chunk.script_linkto, "script_linkname");
				if(isDefined(struct))
					chunk thread maps\mp\zombies\_zm_blockers::debris_move(struct);
				else
					chunk delete();
				continue;
			}
			chunk delete();
		}

		all_trigs = getentarray(closestDebris.target, "target");
		foreach(trig in all_trigs)
			trig delete();
		
		if(self hasgoal("debrisClear"))
			self cancelgoal("debrisClear");
		
		self maps\mp\zombies\_zm_stats::increment_client_stat("doors_purchased");
		self maps\mp\zombies\_zm_stats::increment_player_stat("doors_purchased");
		
		return true;
	}
	
	if(self hasgoal("debrisClear"))
		self cancelgoal("debrisClear");
	return false;
}

bot_revive_teammates()
{
	if(!maps\mp\zombies\_zm_laststand::player_any_player_in_laststand() || self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
	{
		self cancelgoal("revive");
		return;
	}
	
	if(!self hasgoal("revive"))
	{
		teammate = get_closest_downed_teammate();
		if(!isdefined(teammate))
			return;
		self AddGoal(teammate.origin, 50, BOT_GOAL_PRIORITY_REVIVE, "revive");
	}
	else
	{
		if(self AtGoal("revive") || DistanceSquared(self.origin, self GetGoal("revive")) < 5625) // 75^2
		{
			teammate = get_closest_downed_teammate();
			teammate.revivetrigger disable_trigger();
			wait 0.75;
			teammate.revivetrigger enable_trigger();
			if(!self maps\mp\zombies\_zm_laststand::player_is_in_laststand() && teammate maps\mp\zombies\_zm_laststand::player_is_in_laststand())
				teammate maps\mp\zombies\_zm_laststand::auto_revive(self);
		}
	}
}

get_closest_downed_teammate()
{
	if(!maps\mp\zombies\_zm_laststand::player_any_player_in_laststand())
		return;
		
	downed_players = [];
	foreach(player in get_players())
	{
		if(player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			downed_players[downed_players.size] = player;
	}
	downed_players = arraysort(downed_players, self.origin);
	return downed_players[0];
}

bot_pickup_powerup()
{
	if(maps\mp\zombies\_zm_powerups::get_powerups(self.origin, 1000).size == 0)
	{
		self CancelGoal("powerup");
		return;
	}
	
	powerups = maps\mp\zombies\_zm_powerups::get_powerups(self.origin, 1000);
	foreach(powerup in powerups)
	{
		if(FindPath(self.origin, powerup.origin, undefined, 0, 1))
		{
			self AddGoal(powerup.origin, 25, BOT_GOAL_PRIORITY_POWERUP, "powerup");
			if(self AtGoal("powerup") || DistanceSquared(self.origin, powerup.origin) < 2500) // 50^2
				self CancelGoal("powerup");
			return;
		}
	}
}

bot_teleport_think()
{
	self endon("death");
	self endon("disconnect");
	level endon("end_game");
	
	players = get_players();
	if(players.size == 0)
		return;

	host_player = undefined;
	foreach(player in players)
	{
		if(player != self && !player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
		{
			host_player = player;
			break;
		}
	}
	
	if(!isDefined(host_player))
		return;
		
	if(DistanceSquared(self.origin, host_player.origin) > 2250000 && host_player IsOnGround()) // 1500^2
	{
		self.ignoreme = true;
		self.takedamage = false;
		host_player.ignoreme = true;
		host_player.takedamage = false;
		
		safe_node = GetNearestNode(host_player.origin);
		teleport_succeeded = false;
		
		if(isDefined(safe_node))
		{
			if(NodeVisible(safe_node.origin, host_player.origin))
			{
				self SetOrigin(safe_node.origin);
				self SetPlayerAngles(VectorToAngles(host_player.origin - self.origin));
				teleport_succeeded = true;
			}
		}
		
		if(!teleport_succeeded)
		{
			test_positions = array();
			test_positions[0] = host_player.origin + (50, 0, 0);
			test_positions[1] = host_player.origin + (0, 50, 0);
			test_positions[2] = host_player.origin + (-50, 0, 0);
			test_positions[3] = host_player.origin + (0, -50, 0);
			
			foreach(pos in test_positions)
			{
				if(SightTracePassed(pos, pos + (0, 0, 50), false, undefined) && 
				   !SightTracePassed(pos, pos - (0, 0, 50), false, undefined))
				{
					self SetOrigin(pos);
					self SetPlayerAngles(VectorToAngles(host_player.origin - self.origin));
					teleport_succeeded = true;
					break;
				}
			}
		}
		
		if(!teleport_succeeded)
			self SetOrigin(host_player.origin + (0, 0, 5));
		
		teleport_radius_sq = 10000; // 100^2
		all_players = GetPlayers();
		nearby_players = [];
		
		foreach(player in all_players)
		{
			if(DistanceSquared(player.origin, self.origin) < teleport_radius_sq && player != self)
			{
				player.ignoreme = true;
				player.takedamage = false;
				nearby_players[nearby_players.size] = player;
			}
		}
		
		wait 2.5;
		
		if(isDefined(self))
		{
			self.ignoreme = false;
			self.takedamage = true;
		}
		
		if(isDefined(host_player))
		{
			host_player.ignoreme = false;
			host_player.takedamage = true;
		}
		
		foreach(player in nearby_players)
		{
			if(isDefined(player))
			{
				player.ignoreme = false;
				player.takedamage = true;
			}
		}
	}
}

bot_check_player_blocking()
{
	self endon("death");
	self endon("disconnect");
	level endon("game_ended");
	
	while(1)
	{
		wait 0.15;
		
		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			continue;
			
		foreach(player in get_players())
		{
			if(player == self || !isPlayer(player) || player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
				continue;
				
			distance_sq = DistanceSquared(self.origin, player.origin);
			if(distance_sq < 1600) // 40^2
			{
				dir = VectorNormalize(self.origin - player.origin);
				
				if(!self hasgoal("avoid_player"))
				{
					try_pos = self.origin + (dir * 60);
					
					if(FindPath(self.origin, try_pos, undefined, 0, 1))
					{
						self AddGoal(try_pos, 20, 2, "avoid_player");
						wait 0.5;
						continue;
					}
					
					nearest_node = GetNearestNode(self.origin);
					if(isDefined(nearest_node))
					{
						nodes = GetNodesInRadius(self.origin, 200, 0);
						best_node = undefined;
						best_dist = 0;
						
						if(isDefined(nodes) && nodes.size > 0)
						{
							foreach(node in nodes)
							{
								if(NodeVisible(nearest_node.origin, node.origin))
								{
									node_to_player_dist = Distance(node.origin, player.origin);
									if(node_to_player_dist > best_dist)
									{
										best_node = node;
										best_dist = node_to_player_dist;
									}
								}
							}
							
							if(isDefined(best_node))
							{
								self AddGoal(best_node.origin, 20, 2, "avoid_player");
								wait 0.5;
								continue;
							}
						}
					}
					
					if(self IsOnGround())
					{
						new_pos = self.origin + (dir * 50);
						
						if(!SightTracePassed(new_pos, new_pos + (0, 0, 30), true, self) && 
						   SightTracePassed(new_pos, new_pos - (0, 0, 50), false, self))
						{
							goal_names = array("doorBuy", "weaponBuy", "boxBuy", "papBuy");
							foreach(goal_name in goal_names)
							{
								if(self hasgoal(goal_name))
									self cancelgoal(goal_name);
							}
							self SetOrigin(new_pos);
						}
					}
				}
			}
			else
			{
				if(self hasgoal("avoid_player"))
					self cancelgoal("avoid_player");
			}
		}
	}
}

bot_reset_flee_goal()
{
	self endon("death");
	self endon("disconnect");
	level endon("end_game");
	
	while(1)
	{
		self CancelGoal("flee");
		wait 2;
	}
}

bot_update_follow_host()
{
	self AddGoal(get_players()[0].origin, 100, BOT_GOAL_PRIORITY_WANDER, "wander");
}

bot_update_lookat()
{
	path = 0;
	if(isDefined(self getlookaheaddir()))
		path = 1;
		
	if(!path && getTime() > self.bot.update_idle_lookat)
	{
		origin = bot_get_look_at();
		if(!isDefined(origin))
			return;
		self lookat(origin + vectorScale((0, 0, 1), 16));
		self.bot.update_idle_lookat = getTime() + randomintrange(1500, 3000);
	}
	else if(path && self.bot.update_idle_lookat > 0)
	{
		self clearlookat();
		self.bot.update_idle_lookat = 0;
	}
}

bot_get_look_at()
{
	enemy = bot_get_closest_enemy(self.origin);
	if(isDefined(enemy))
	{
		node = getvisiblenode(self.origin, enemy.origin);
		if(isDefined(node) && distancesquared(self.origin, node.origin) > 1024)
			return node.origin;
	}
	
	spawn = self getgoal("wander");
	if(isDefined(spawn))
		node = getvisiblenode(self.origin, spawn);
		
	if(isDefined(node) && distancesquared(self.origin, node.origin) > 1024)
		return node.origin;
		
	return undefined;
}

bot_get_closest_enemy(origin)
{
	enemies = getaispeciesarray(level.zombie_team, "all");
	enemies = arraysort(enemies, origin);
	if(enemies.size >= 1)
		return enemies[0];
	return undefined;
}

bot_wakeup_think()
{
	self endon("death");
	self endon("disconnect");
	level endon("game_ended");
	
	for(;;)
	{
		wait self.bot.think_interval;
		self notify("wakeup");
	}
}

bot_damage_think()
{
	self notify("bot_damage_think");
	self endon("bot_damage_think");
	self endon("disconnect");
	level endon("game_ended");
	
	for(;;)
	{
		self waittill("damage", damage, attacker, direction, point, mod, unused1, unused2, unused3, unused4, weapon, flags, inflictor);
		self.bot.attacker = attacker;
		self notify("wakeup", damage, attacker, direction);
	}
}

onspawn()
{
	self endon("disconnect");
	level endon("end_game");
	
	self thread bot_cleanup_on_disconnect();
	
	while(1)
	{
		self waittill("spawned_player");
		self thread bot_perks();
		self thread bot_spawn();
	}
}

bot_cleanup_on_disconnect()
{
	self waittill("disconnect");
	
	if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot == self)
		level.box_in_use_by_bot = undefined;
	
	if(isDefined(level.pap_in_use_by_bot) && level.pap_in_use_by_bot == self)
		level.pap_in_use_by_bot = undefined;
	
	if(!isDefined(level.cached_perk_machines))
		return;
		
	foreach(machine in level.cached_perk_machines)
	{
		if(isDefined(machine.pap_user) && machine.pap_user == self)
			machine.pap_user = undefined;
	}
}

bot_perks()
{
	self endon("disconnect");
	self endon("death");
	wait 1;
	
	while(1)
	{
		self SetNormalHealth(250);
		self SetmaxHealth(250);
		self SetPerk("specialty_flakjacket");
		self SetPerk("specialty_rof");
		self SetPerk("specialty_fastreload");
		self waittill("player_revived");
	}
}

bot_should_take_weapon(boxWeapon, currentWeapon)
{
	if(!isDefined(boxWeapon))
		return false;
	
	if(self HasWeapon(boxWeapon))
		return false;
		
	if(IsSubStr(boxWeapon, "raygun") || IsSubStr(boxWeapon, "thunder") || IsSubStr(boxWeapon, "wave") || 
	   IsSubStr(boxWeapon, "mark2") || IsSubStr(boxWeapon, "tesla"))
		return true;
	
	tier1_weapons = array("raygun_", "thunder", "wave_gun", "mark2", "tesla");
	tier2_weapons = array("galil", "an94", "hamr", "rpd", "lsat", "dsr50");
	tier3_weapons = array("mp5k", "pdw57", "mtar", "mp40", "ak74u", "qcw05");
	tier4_weapons = array("m14", "870mcs", "r870", "olympia", "fnfal");
	
	currentIsTier1 = false;
	currentIsTier2 = false;
	currentIsTier3 = false;
	
	foreach(weapon in tier1_weapons)
	{
		if(IsSubStr(currentWeapon, weapon))
		{
			currentIsTier1 = true;
			break;
		}
	}
	
	if(!currentIsTier1)
	{
		foreach(weapon in tier2_weapons)
		{
			if(IsSubStr(currentWeapon, weapon))
			{
				currentIsTier2 = true;
				break;
			}
		}
	}
	
	if(!currentIsTier1 && !currentIsTier2)
	{
		foreach(weapon in tier3_weapons)
		{
			if(IsSubStr(currentWeapon, weapon))
			{
				currentIsTier3 = true;
				break;
			}
		}
	}
	
	if(IsSubStr(boxWeapon, "sniper") || IsSubStr(boxWeapon, "launcher") || IsSubStr(boxWeapon, "knife") || 
	   (IsSubStr(boxWeapon, "ballistic") && !IsSubStr(boxWeapon, "ballistic_knife")))
		return (randomfloat(1) < 0.15);
	
	boxIsTier2 = false;
	boxIsTier3 = false;
	boxIsTier4 = false;
	
	foreach(weapon in tier2_weapons)
	{
		if(IsSubStr(boxWeapon, weapon))
		{
			boxIsTier2 = true;
			break;
		}
	}
	
	if(!boxIsTier2)
	{
		foreach(weapon in tier3_weapons)
		{
			if(IsSubStr(boxWeapon, weapon))
			{
				boxIsTier3 = true;
				break;
			}
		}
	}
	
	if(!boxIsTier2 && !boxIsTier3)
	{
		foreach(weapon in tier4_weapons)
		{
			if(IsSubStr(boxWeapon, weapon))
			{
				boxIsTier4 = true;
				break;
			}
		}
	}
	
	if(currentIsTier1)
	{
		foreach(weapon in tier1_weapons)
		{
			if(IsSubStr(boxWeapon, weapon) && !IsSubStr(currentWeapon, weapon))
				return (randomfloat(1) < 0.7);
		}
		return false;
	}
	
	if(currentIsTier2)
	{
		if(boxIsTier2)
			return (randomfloat(1) < 0.5);
		else if(boxIsTier3 || boxIsTier4)
			return (randomfloat(1) < 0.1);
		return (randomfloat(1) < 0.2);
	}
	
	if(currentIsTier3)
	{
		if(boxIsTier2)
			return true;
		else if(boxIsTier3)
			return (randomfloat(1) < 0.6);
		else if(boxIsTier4)
			return (randomfloat(1) < 0.15);
	}
	
	if(level.round_number <= 5)
		return true;
	else if(level.round_number <= 15)
	{
		if(boxIsTier2 || boxIsTier3)
			return true;
		else
			return (randomfloat(1) < 0.5);
	}
	else
	{
		if(boxIsTier2)
			return true;
		else if(boxIsTier3)
			return (randomfloat(1) < 0.7);
		else
			return (randomfloat(1) < 0.3);
	}
	
	return (randomfloat(1) < 0.5);
}

GetDvarIntDefault(dvarName, defaultValue)
{
	if(GetDvar(dvarName) == "")
		return defaultValue;
	return GetDvarInt(dvarName);
}

bot_manage_ammo()
{
	self endon("disconnect");
	self endon("death");
	level endon("game_ended");

	wait 1;

	infinite_ammo_enabled = GetDvarIntDefault("bo2_zm_bots_infinite_ammo", 0);

	if(infinite_ammo_enabled == 1)
		self thread bot_give_max_ammo_loop();
	else
		self thread bot_buy_ammo_loop();
}

bot_give_max_ammo_loop()
{
	self endon("disconnect");
	self endon("death");
	level endon("game_ended");

	while(true)
	{
		primary_weapons = self GetWeaponsListPrimaries();
		foreach(weapon in primary_weapons)
		{
			if(!IsSubStr(weapon, "raygun") && !IsSubStr(weapon, "thunder") &&
			   !IsSubStr(weapon, "wave") && !IsSubStr(weapon, "mark2") &&
			   !IsSubStr(weapon, "tesla") && !IsSubStr(weapon, "staff"))
			{
				self GiveMaxAmmo(weapon);
			}
		}
		wait 1;
	}
}

bot_buy_ammo_loop()
{
	self endon("disconnect");
	self endon("death");
	level endon("game_ended");

	while(true)
	{
		wait randomfloatrange(3.0, 5.0);

		if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand() ||
		   self hasgoal("revive") || self hasgoal("boxBuy") ||
		   self hasgoal("papBuy") || self hasgoal("doorBuy") ||
		   self hasgoal("debrisClear") || self hasgoal("generator"))
			continue;

		currentWeapon = self GetCurrentWeapon();
		if(!IsDefined(currentWeapon) || currentWeapon == "none")
			continue;

		if(IsSubStr(currentWeapon, "knife") || IsSubStr(currentWeapon, "grenade") || IsSubStr(currentWeapon, "equip") ||
		   IsSubStr(currentWeapon, "raygun") || IsSubStr(currentWeapon, "thunder") || IsSubStr(currentWeapon, "wave") ||
		   IsSubStr(currentWeapon, "mark2") || IsSubStr(currentWeapon, "tesla") || IsSubStr(currentWeapon, "staff"))
			continue;

		stockAmmo = self GetWeaponAmmoStock(currentWeapon);
		maxStockAmmo = WeaponMaxAmmo(currentWeapon);

		if(IsDefined(maxStockAmmo) && maxStockAmmo > 0 && (stockAmmo < (maxStockAmmo * 0.20)))
		{
			wallbuy = find_wallbuy_for_weapon(currentWeapon);

			if(IsDefined(wallbuy))
			{
				ammo_cost = int(wallbuy.trigger_stub.cost / 2);

				if(self.score >= ammo_cost)
				{
					dist_sq = DistanceSquared(self.origin, wallbuy.origin);
					interaction_dist_sq = 10000; // 100^2

					if(dist_sq < interaction_dist_sq)
					{
						self maps\mp\zombies\_zm_score::minus_to_player_score(ammo_cost);
						self GiveMaxAmmo(currentWeapon);
						self PlaySound("zmb_cha_ching");
						wait 2.0;
					}
					else if(dist_sq < 400000) // 632^2
					{
						if(!self hasgoal("ammoBuy") || DistanceSquared(self GetGoal("ammoBuy"), wallbuy.origin) > 10000)
						{
							if(FindPath(self.origin, wallbuy.origin, undefined, 0, 1))
								self AddGoal(wallbuy.origin, 75, 1, "ammoBuy");
						}
					}
				}
			}
		}
		else
		{
			if(self hasgoal("ammoBuy"))
				self cancelgoal("ammoBuy");
		}
	}
}

find_wallbuy_for_weapon(weapon_name)
{
	if(!IsDefined(level._spawned_wallbuys))
		return undefined;

	closest_wallbuy = undefined;
	closest_dist_sq = 99999999;

	foreach(wallbuy in level._spawned_wallbuys)
	{
		if(!IsDefined(wallbuy) || !IsDefined(wallbuy.trigger_stub) || !IsDefined(wallbuy.trigger_stub.zombie_weapon_upgrade) || !IsDefined(wallbuy.origin))
			continue;

		base_match = (wallbuy.trigger_stub.zombie_weapon_upgrade == weapon_name);
		upgraded_name = maps\mp\zombies\_zm_weapons::get_upgrade_weapon(wallbuy.trigger_stub.zombie_weapon_upgrade);
		upgrade_match = (IsDefined(upgraded_name) && upgraded_name == weapon_name);

		if(base_match || upgrade_match)
		{
			dist_sq = DistanceSquared(self.origin, wallbuy.origin);
			if(dist_sq < closest_dist_sq)
			{
				closest_dist_sq = dist_sq;
				closest_wallbuy = wallbuy;
			}
		}
	}
	return closest_wallbuy;
}

bot_origins_think()
{
	if(level.script == "zm_tomb")
		self thread scripts\zm\zm_bo2_bots_origins::bot_activate_generator();
}

bot_update_failsafe()
{
	time = getTime();
	if((time - self.spawntime) < 7500)
		return;
		
	if(time < self.bot.update_failsafe)
		return;
		
	if(!self atgoal() && distance2dsquared(self.bot.previous_origin, self.origin) < 256)
	{
		nodes = getnodesinradius(self.origin, 512, 0);
		nodes = array_randomize(nodes);
		nearest = bot_nearest_node(self.origin);
		failsafe = 0;
		
		if(isDefined(nearest))
		{
			i = 0;
			while(i < nodes.size)
			{
				if(!bot_failsafe_node_valid(nearest, nodes[i]))
				{
					i++;
					continue;
				}
				else
				{
					self botsetfailsafenode(nodes[i]);
					wait 0.5;
					self.bot.update_idle_lookat = 0;
					self bot_update_lookat();
					self cancelgoal("enemy_patrol");
					self wait_endon(4, "goal");
					self botsetfailsafenode();
					self bot_update_lookat();
					failsafe = 1;
					break;
				}
				i++;
			}
		}
		else if(!failsafe && nodes.size)
		{
			node = random(nodes);
			self botsetfailsafenode(node);
			wait 0.5;
			self.bot.update_idle_lookat = 0;
			self bot_update_lookat();
			self cancelgoal("enemy_patrol");
			self wait_endon(4, "goal");
			self botsetfailsafenode();
			self bot_update_lookat();
		}
	}
	self.bot.update_failsafe = getTime() + 3500;
	self.bot.previous_origin = self.origin;
}

bot_failsafe_node_valid(nearest, node)
{
	if(isDefined(node.script_noteworthy))
		return 0;
		
	if((node.origin[2] - self.origin[2]) > 18)
		return 0;
		
	if(nearest == node)
		return 0;
		
	if(!nodesvisible(nearest, node))
		return 0;
		
	if(isDefined(level.spawn_all) && level.spawn_all.size > 0)
		spawns = arraysort(level.spawn_all, node.origin);
	else if(isDefined(level.spawnpoints) && level.spawnpoints.size > 0)
		spawns = arraysort(level.spawnpoints, node.origin);
	else if(isDefined(level.spawn_start) && level.spawn_start.size > 0)
	{
		spawns = arraycombine(level.spawn_start["allies"], level.spawn_start["axis"], 1, 0);
		spawns = arraysort(spawns, node.origin);
	}
	else
		return 0;
		
	goal = bot_nearest_node(spawns[0].origin);
	if(isDefined(goal) && findpath(node.origin, goal.origin, undefined, 0, 1))
		return 1;
		
	return 0;
}

bot_nearest_node(origin)
{
	node = getnearestnode(origin);
	if(isDefined(node))
		return node;
		
	nodes = getnodesinradiussorted(origin, 256, 0, 256);
	if(nodes.size)
		return nodes[0];
		
	return undefined;
}
