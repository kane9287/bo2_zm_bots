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