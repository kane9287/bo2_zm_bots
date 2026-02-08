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

bot_spawn()
{
    self bot_spawn_init();
    self thread bot_main();
    self thread bot_check_player_blocking();
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
	if ( !isDefined( self.bot ) )
	{
		self.bot = spawnstruct();
		self.bot.threat = spawnstruct();
	}
	self.bot.glass_origin = undefined;
	self.bot.ignore_entity = [];
	self.bot.previous_origin = self.origin;
	self.bot.time_ads = 0;
	self.bot.update_c4 = time + randomintrange( 1000, 3000 );
	self.bot.update_crate = time + randomintrange( 1000, 3000 );
	self.bot.update_crouch = time + randomintrange( 1000, 3000 );
	self.bot.update_failsafe = time + randomintrange( 1000, 3000 );
	self.bot.update_idle_lookat = time + randomintrange( 1000, 3000 );
	self.bot.update_killstreak = time + randomintrange( 1000, 3000 );
	self.bot.update_lookat = time + randomintrange( 1000, 3000 );
	self.bot.update_objective = time + randomintrange( 1000, 3000 );
	self.bot.update_objective_patrol = time + randomintrange( 1000, 3000 );
	self.bot.update_patrol = time + randomintrange( 1000, 3000 );
	self.bot.update_toss = time + randomintrange( 1000, 3000 );
	self.bot.update_launcher = time + randomintrange( 1000, 3000 );
	self.bot.update_weapon = time + randomintrange( 1000, 3000 );
	self.bot.think_interval = 0.1;
	self.bot.fov = -0.9396;
	self.bot.threat.entity = undefined;
	self.bot.threat.position = ( 0, 0, 0 );
	self.bot.threat.time_first_sight = 0;
	self.bot.threat.time_recent_sight = 0;
	self.bot.threat.time_aim_interval = 0;
	self.bot.threat.time_aim_correct = 0;
	self.bot.threat.update_riotshield = 0;
}

bot_main()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );

	self thread bot_wakeup_think();
	self thread bot_damage_think();
	self thread bot_reset_flee_goal();

	for ( ;; )
	{
		self waittill( "wakeup", damage, attacker, direction );
		if( self isremotecontrolling())
		{
			continue;
		}
		else
		{
			self bot_combat_think( damage, attacker, direction );
			self bot_update_follow_host();
			self bot_update_lookat();
			if(is_true(level.using_bot_revive_logic))
			{
				self bot_revive_teammates();
			}
			self bot_pickup_powerup();
		}	
	}
}

bot_wakeup_think()
{
	self endon( "death" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	for ( ;; )
	{
		wait self.bot.think_interval;
		self notify( "wakeup" );
	}
}

bot_damage_think()
{
	self notify( "bot_damage_think" );
	self endon( "bot_damage_think" );
	self endon( "disconnect" );
	level endon( "game_ended" );
	for ( ;; )
	{
		self waittill( "damage", damage, attacker, direction, point, mod, unused1, unused2, unused3, unused4, weapon, flags, inflictor );
		self.bot.attacker = attacker;
		self notify( "wakeup", damage, attacker, direction );
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
	self AddGoal(get_players()[0].origin, 100, 1, "wander");
}

bot_update_lookat()
{
	path = 0;
	if ( isDefined( self getlookaheaddir() ) )
	{
		path = 1;
	}
	if ( !path && getTime() > self.bot.update_idle_lookat )
	{
		origin = bot_get_look_at();
		if ( !isDefined( origin ) )
		{
			return;
		}
		self lookat( origin + vectorScale( ( 0, 0, 1 ), 16 ) );
		self.bot.update_idle_lookat = getTime() + randomintrange( 1500, 3000 );
	}
	else if ( path && self.bot.update_idle_lookat > 0 )
	{
		self clearlookat();
		self.bot.update_idle_lookat = 0;
	}
}

bot_get_look_at()
{
	enemy = bot_get_closest_enemy( self.origin );
	if ( isDefined( enemy ) )
	{
		node = getvisiblenode( self.origin, enemy.origin );
		if ( isDefined( node ) && distancesquared( self.origin, node.origin ) > 1024 )
		{
			return node.origin;
		}
	}
	spawn = self getgoal( "wander" );
	if ( isDefined( spawn ) )
	{
		node = getvisiblenode( self.origin, spawn );
	}
	if ( isDefined( node ) && distancesquared( self.origin, node.origin ) > 1024 )
	{
		return node.origin;
	}
	return undefined;
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
            if(distance_sq < 1600)
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

array_combine(array1, array2)
{
    if (!isDefined(array1))
        array1 = [];
    if (!isDefined(array2))
        array2 = [];

    foreach (item in array2)
    {
        array1[array1.size] = item;
    }

    return array1;
}

init()
{
    bot_set_skill();
    
    iprintln("^3Waiting for initial blackscreen...");
    flag_wait("initial_blackscreen_passed");
    iprintln("^2Blackscreen passed, continuing bot setup...");

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

    // Initialize bot count tracker - CRITICAL for spawn limiting
    if (!isdefined(level.bot_count))
        level.bot_count = 0;
    
    // Maximum bots allowed
    level.max_bot_count = 3;

    // Get desired bot count from dvar, default and cap at 3
    bot_amount = GetDvarIntDefault("bo2_zm_bots_count", 3);
    if(bot_amount > level.max_bot_count)
        bot_amount = level.max_bot_count;

    iprintln("^2Spawning " + bot_amount + " bots...");

    // Spawn initial bots
    for(i=0; i<bot_amount; i++)
    {
        iprintln("^3Spawning bot " + (i+1));
        level thread spawn_bot();
        wait 1;
    }

    // Initialize map specific logic
    if(level.script == "zm_tomb")
    {
        level thread scripts\zm\zm_bo2_bots_origins::init();
    }

    iprintln("^2Bot initialization complete - " + level.bot_count + " bots active");
}

spawn_bot()
{
    // Check if we've hit the maximum bot count
    if(isDefined(level.max_bot_count) && level.bot_count >= level.max_bot_count)
    {
        iprintln("^1Maximum bot count reached (" + level.max_bot_count + "), not spawning more bots");
        return;
    }

    iprintln("^3Adding test client...");
    bot = addtestclient();
    if(!isDefined(bot))
    {
        iprintln("^1Failed to add test client!");
        return;
    }
    
    // Increment bot count immediately after successful addtestclient
    level.bot_count++;
    iprintln("^3Bot count: " + level.bot_count + "/" + level.max_bot_count);
    
    iprintln("^3Waiting for bot to spawn...");
    bot waittill("spawned_player");
    iprintln("^2Bot spawned, configuring...");
    
    bot thread maps\mp\zombies\_zm::spawnspectator();
    if(isDefined(bot))
    {
        bot.pers["isBot"] = 1;
        bot.spawned_via_init = true;  // Flag to prevent respawn loop
        bot thread onspawn();
        bot thread bot_monitor_disconnect();  // Monitor for disconnects to update count
    }
    
    wait 1;
    iprintln("^3Spawning bot as player...");
    
    if(isDefined(level.spawnplayer))
        bot [[level.spawnplayer]]();
    else
        iprintln("^1ERROR: level.spawnplayer not defined!");
}

bot_monitor_disconnect()
{
    self endon("disconnect");
    level endon("end_game");
    
    self waittill("disconnect");
    
    // Decrement bot count when bot disconnects
    if(isDefined(level.bot_count) && level.bot_count > 0)
    {
        level.bot_count--;
        iprintln("^3Bot disconnected. Bot count: " + level.bot_count + "/" + level.max_bot_count);
    }
}

onspawn()
{
    self endon("disconnect");
    level endon("end_game");
    
    // Clean up box usage if this bot disconnects
    self thread bot_cleanup_on_disconnect();
    
    while(1)
    {
        self waittill("spawned_player");
        
        // Only run bot_spawn logic on respawns after death, not on initial spawn
        if(isDefined(self.spawned_via_init) && self.spawned_via_init)
        {
            // First spawn from init - just clear the flag
            self.spawned_via_init = false;
        }
        else
        {
            // This is a respawn after death - reinitialize bot behavior
            self thread bot_spawn();
        }
        
        self thread bot_perks();
    }
}

bot_cleanup_on_disconnect()
{
    self endon("disconnect");
    level endon("end_game");
    
    self waittill("disconnect");
    
    // Clear any global flags this bot was using
    if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot == self)
        level.box_in_use_by_bot = undefined;
    
    if(isDefined(level.pap_in_use_by_bot) && level.pap_in_use_by_bot == self)
        level.pap_in_use_by_bot = undefined;
    
    if(isDefined(level.generator_in_use_by_bot) && level.generator_in_use_by_bot == self)
        level.generator_in_use_by_bot = undefined;
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

bot_set_skill()
{
    setdvar( "bot_MinDeathTime", "250" );
    setdvar( "bot_MaxDeathTime", "500" );
    setdvar( "bot_MinFireTime", "100" );
    setdvar( "bot_MaxFireTime", "250" );
    setdvar( "bot_PitchUp", "-5" );
    setdvar( "bot_PitchDown", "10" );
    setdvar( "bot_Fov", "160" );
    setdvar( "bot_MinAdsTime", "3000" );
    setdvar( "bot_MaxAdsTime", "5000" );
    setdvar( "bot_MinCrouchTime", "100" );
    setdvar( "bot_MaxCrouchTime", "400" );
    setdvar( "bot_TargetLeadBias", "2" );
    setdvar( "bot_MinReactionTime", "40" );
    setdvar( "bot_MaxReactionTime", "70" );
    setdvar( "bot_StrafeChance", "1" );
    setdvar( "bot_MinStrafeTime", "3000" );
    setdvar( "bot_MaxStrafeTime", "6000" );
    setdvar( "scr_help_dist", "512" );
    setdvar( "bot_AllowGrenades", "1" );
    setdvar( "bot_MinGrenadeTime", "1500" );
    setdvar( "bot_MaxGrenadeTime", "4000" );
    setdvar( "bot_MeleeDist", "70" );
    setdvar( "bot_YawSpeed", "4" );
    setdvar( "bot_SprintDistance", "256" );
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

bot_nearest_node( origin )
{
	node = getnearestnode( origin );
	if ( isDefined( node ) )
	{
		return node;
	}
	nodes = getnodesinradiussorted( origin, 256, 0, 256 );
	if ( nodes.size )
	{
		return nodes[ 0 ];
	}
	return undefined;
}

bot_get_closest_enemy( origin )
{
	enemies = getaispeciesarray( level.zombie_team, "all" );
	enemies = arraysort( enemies, origin );
	if ( enemies.size >= 1 )
	{
		return enemies[ 0 ];
	}
	return undefined;
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
		teammate = self get_closest_downed_teammate();
		if(!isdefined(teammate))
			return;
		self AddGoal(teammate.origin, 50, 3, "revive");
	}
	else
	{
		if(self AtGoal("revive") || Distance(self.origin, self GetGoal("revive")) < 75)
		{
			teammate = self get_closest_downed_teammate();
			teammate.revivetrigger disable_trigger();
			wait 0.75;
			teammate.revivetrigger enable_trigger();
			if(!self maps\mp\zombies\_zm_laststand::player_is_in_laststand() && teammate maps\mp\zombies\_zm_laststand::player_is_in_laststand())
			{
				teammate maps\mp\zombies\_zm_laststand::auto_revive( self );
			}
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
			self AddGoal(powerup.origin, 25, 2, "powerup");
			if(self AtGoal("powerup") || Distance(self.origin, powerup.origin) < 50)
			{
				self CancelGoal("powerup");
			}
			return;
		}
	}
}

// Helper function to get Dvar value with a default
GetDvarIntDefault(dvarName, defaultValue)
{
    if(GetDvar(dvarName) == "")
        return defaultValue;
    return GetDvarInt(dvarName);
}