#include maps\mp\zombies\_zm_utility;
#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_score;
#include maps\mp\zombies\_zm_laststand;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_blockers;
#include maps\mp\zombies\_zm_powerups;
#include scripts\zm\zm_bo2_bots_combat;
#include scripts\zm\zm_bo2_bots_utility; // Added include for utility functions


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
    // level.player_starting_points = 550 * 400;
    bot_set_skill();

    // Add debug
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

    // Setup bot tracking array
    if (!isdefined(level.bots))
        level.bots = [];

    bot_amount = GetDvarIntDefault("bo2_zm_bots_count", 2); // CHANGED: Default from 4 to 2 bots
    // if(bot_amount > (4-get_players().size))
    //     bot_amount = 4 - get_players().size;

    iprintln("^2Spawning " + bot_amount + " bots...");

    for(i=0; i<bot_amount; i++)
    {
        iprintln("^3Spawning bot " + (i+1));
        // Track spawned bot entities
        bot_entity = spawn_bot();
        level.bots[level.bots.size] = bot_entity;
        wait 1; // Add a brief pause between bot spawns
    }

    // Initialize map specific logic
    if(level.script == "zm_tomb")
    {
        level thread scripts\zm\zm_bo2_bots_origins::init();
    }

    iprintln("^2Bot initialization complete");
}

bot_set_skill()
{
	// MP Veteran-level settings for maximum combat effectiveness
	setdvar( "bot_MinDeathTime", "100" );      // Reduced from 250
	setdvar( "bot_MaxDeathTime", "200" );      // Reduced from 500
	setdvar( "bot_MinFireTime", "50" );        // Reduced from 100
	setdvar( "bot_MaxFireTime", "150" );       // Reduced from 250
	setdvar( "bot_PitchUp", "-5" );
	setdvar( "bot_PitchDown", "10" );
	setdvar( "bot_Fov", "180" );               // Increased from 160
	setdvar( "bot_MinAdsTime", "1500" );       // Reduced from 3000
	setdvar( "bot_MaxAdsTime", "2500" );       // Reduced from 5000
	setdvar( "bot_MinCrouchTime", "100" );
	setdvar( "bot_MaxCrouchTime", "400" );
	setdvar( "bot_TargetLeadBias", "1" );      // Reduced from 2
	setdvar( "bot_MinReactionTime", "10" );    // Reduced from 40
	setdvar( "bot_MaxReactionTime", "30" );    // Reduced from 70
	setdvar( "bot_StrafeChance", "1" );
	setdvar( "bot_MinStrafeTime", "2000" );    // Reduced from 3000
	setdvar( "bot_MaxStrafeTime", "4000" );    // Reduced from 6000
	setdvar( "scr_help_dist", "512" );
	setdvar( "bot_AllowGrenades", "1" );
	setdvar( "bot_MinGrenadeTime", "1500" );
	setdvar( "bot_MaxGrenadeTime", "4000" );
	setdvar( "bot_MeleeDist", "70" );
	setdvar( "bot_YawSpeed", "6" );            // Increased from 4
	setdvar( "bot_SprintDistance", "256" );
}

// New function to handle bot stance actions
botaction(stance)
{
    // Handle different stance actions for the bot
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
            // Reset to allow all stances
            self allowstand(true);
            self allowcrouch(true);
            self allowprone(true);
            break;
    }
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