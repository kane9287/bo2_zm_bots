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
    level endon("end_game");
    
    // Basic perk management for respawns
    wait 2;  // Wait a bit after spawn
    
    // Can add perk restoration logic here if needed
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