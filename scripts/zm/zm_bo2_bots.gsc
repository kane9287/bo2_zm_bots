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

bot_spawn()
{
    self bot_spawn_init();
    self thread bot_main();
    self thread bot_check_player_blocking();
    self thread bot_give_starting_perks(); // NEW: Give starting perks
}

// NEW: Give bots Quick Revive and Juggernog at spawn
bot_give_starting_perks()
{
    self endon("disconnect");
    self endon("death");
    
    // Wait for bot to be fully initialized and spawned
    wait 2;
    
    // Give Quick Revive (specialty_quickrevive)
    if(!self HasPerk("specialty_quickrevive"))
    {
        self thread maps\mp\zombies\_zm_perks::give_perk("specialty_quickrevive");
        iprintln("^2Bot given Quick Revive");
        wait 0.5;
    }
    
    // Give Juggernog (specialty_armorvest)
    if(!self HasPerk("specialty_armorvest"))
    {
        self thread maps\mp\zombies\_zm_perks::give_perk("specialty_armorvest");
        iprintln("^2Bot given Juggernog");
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

    bot_amount = GetDvarIntDefault("bo2_zm_bots_count", 2);
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

bot_buy_box()
{
    // Only try to access the box on a timed interval (REDUCED FROM 3000 to 1500)
    if (!isDefined(self.bot.box_purchase_time) || GetTime() > self.bot.box_purchase_time)
    {
        self.bot.box_purchase_time = GetTime() + 1500; // Try every 1.5 seconds instead of 3

        // Don't try if we're in last stand
        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            return;

        // Don't try if we can't afford it (use 950 cost)
        if(self.score < 950)
            return;

        // Check global box usage tracker to prevent multiple bots using box simultaneously
        if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot != self)
        {
            // Another bot is using the box, wait your turn
            return;
        }

        // REDUCED global cooldown from 30 sec to 10 sec
        if(isDefined(level.last_bot_box_interaction_time) && (GetTime() - level.last_bot_box_interaction_time < 10000))
            return;

        // REDUCED personal cooldown from 15 sec to 5 sec
        if(isDefined(self.bot.last_box_interaction_time) && (GetTime() - self.bot.last_box_interaction_time < 5000))
            return;

        // --- Start: Logic to grab from an already open box (Kept from original) ---
        if(!isDefined(self.bot.grab_weapon_time) || GetTime() > self.bot.grab_weapon_time)
        {
            activeBox = undefined;
            closestOpenBoxDist = 99999;

            // Find the closest open box with a weapon ready to grab
            foreach(box in level.chests)
            {
                if(!isDefined(box))
                    continue;

                // Check if the box is open with a weapon ready
                if(isDefined(box._box_open) && box._box_open &&
                   isDefined(box.weapon_out) && box.weapon_out &&
                   isDefined(box.zbarrier) && isDefined(box.zbarrier.weapon_model))
                {
                    dist = Distance(self.origin, box.origin);
                    if(dist < closestOpenBoxDist)
                    {
                        // Check if path exists before considering it
                        if(FindPath(self.origin, box.origin, undefined, 0, 1))
                        {
                            closestOpenBoxDist = dist;
                            activeBox = box;
                        }
                    }
                }
            }

            // If we found an open box with a weapon
            if(isDefined(activeBox))
            {
                // If close enough, grab it
                if(closestOpenBoxDist < 100) // Interaction distance
                {
                    // Cancel any existing goal
                    if(self hasgoal("boxGrab") || self hasgoal("boxBuy"))
                    {
                        self cancelgoal("boxGrab");
                        self cancelgoal("boxBuy");
                    }

                    // Mark that we're trying to grab the weapon
                    self.bot.grab_weapon_time = GetTime() + 5000; // Cooldown before trying to grab again

                    // Look at the box
                    aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
                    self lookat(activeBox.origin + aim_offset);
                    wait randomfloatrange(0.3, 0.8); // Simulate reaction

                    // Re-validate box state
                    if(!isDefined(activeBox) || !isDefined(activeBox._box_open) || !activeBox._box_open ||
                       !isDefined(activeBox.weapon_out) || !activeBox.weapon_out ||
                       self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
                    {
                        return; // State changed, abort grab
                    }

                    // --- Weapon Decision Logic ---
                    currentWeapon = self GetCurrentWeapon();
                    boxWeapon = activeBox.zbarrier.weapon_string;
                    shouldTake = bot_should_take_weapon(boxWeapon, currentWeapon);
                    // --- End Weapon Decision Logic ---

                    if(shouldTake)
                    {
                        // Use the reliable direct give method from monitor function
                        if(isDefined(boxWeapon) && !self HasWeapon(boxWeapon))
                        {
                            primaries = self GetWeaponsListPrimaries();
                            if(primaries.size >= 2)
                            {
                                dropWeapon = currentWeapon; // Default to dropping current
                                // Find a non-wonder weapon to drop if possible
                                foreach(weapon in primaries)
                                {
                                    if(weapon != currentWeapon && !IsSubStr(weapon, "raygun") && !IsSubStr(weapon, "thunder") && !IsSubStr(weapon, "wave") && !IsSubStr(weapon, "tesla") && !IsSubStr(weapon, "staff"))
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
                            activeBox.weapon_out = 0; // Mark as taken
                            activeBox notify("weapon_grabbed");
                            self PlaySound("zmb_weap_pickup");
                        }
                        else // Fallback trigger if direct give fails or weapon unknown
                        {
                             if(isDefined(activeBox.unitrigger_stub) && isDefined(activeBox.unitrigger_stub.trigger))
                                activeBox.unitrigger_stub.trigger notify("trigger", self);
                             else
                                activeBox notify("trigger", self);
                        }
                    }
                    else
                    {
                        // Bot decided not to take, add longer cooldown
                        self.bot.grab_weapon_time = GetTime() + 7000;
                    }

                    // Set last interaction time
                    self.bot.last_box_interaction_time = GetTime();
                    if(isDefined(activeBox.chest_user) && activeBox.chest_user == self)
                        activeBox.chest_user = undefined;

                    return; // Finished grab attempt
                }
                // If not close enough, move towards it (INCREASED range from 500 to 800)
                else if (closestOpenBoxDist < 800)
                {
                    if(!self hasgoal("boxGrab")) // Only set goal if not already moving
                    {
                         self AddGoal(activeBox.origin, 75, 3, "boxGrab"); // High priority grab goal
                    }
                    return; // Wait until closer
                }
            }
        }
        // --- End: Logic to grab from an already open box ---


        // --- Start: Logic to buy a new box spin (Based on user request) ---

        // Check if we already paid and are waiting for the animation
        if(is_true(self.bot.waiting_for_box_animation))
        {
            // Add a timeout check in case monitor thread fails
            if((!isDefined(self.bot.box_payment_time) || (GetTime() - self.bot.box_payment_time > 10000))) // 10 second timeout
            {
                self.bot.waiting_for_box_animation = undefined;
                self.bot.current_box = undefined;
                if(level.box_in_use_by_bot == self)
                    level.box_in_use_by_bot = undefined;
            }
            else
            {
                return; // Still waiting, do nothing
            }
        }

        // Make sure boxes exist and index is valid
        if(!isDefined(level.chests) || level.chests.size == 0 || !isDefined(level.chest_index) || level.chest_index >= level.chests.size)
            return;

        // Get the currently active box based on index
        current_box = level.chests[level.chest_index];
        if(!isDefined(current_box) || !isDefined(current_box.origin))
            return;

        // Check if box is available (not open, not moving, not locked, not teddy'd)
        if(is_true(current_box._box_open) ||
           flag("moving_chest_now") ||
           (isDefined(current_box.is_locked) && current_box.is_locked) ||
           (isDefined(current_box.chest_user) && current_box.chest_user != self) ||
           (isDefined(level.mystery_box_teddy_locations) && array_contains(level.mystery_box_teddy_locations, current_box.origin))) // Avoid teddy locations
        {
            return; // Box is not available
        }

        dist = Distance(self.origin, current_box.origin);
        interaction_dist = 100; // Distance to interact
        detection_dist = 800; // INCREASED from 500 to 800

        // Only try to use box if we have enough points and it's reasonably close
        if(self.score >= 950 && dist < detection_dist)
        {
            // Check if a path exists
            if(FindPath(self.origin, current_box.origin, undefined, 0, 1))
            {
                // Move to box if not already close enough
                if(dist > interaction_dist)
                {
                    // Only set goal if not already pathing to this box
                    if(!self hasgoal("boxBuy") || Distance(self GetGoal("boxBuy"), current_box.origin) > 50)
                    {
                        self AddGoal(current_box.origin, 75, 2, "boxBuy"); // Normal priority buy goal
                    }
                    return; // Wait until closer
                }

                // --- Use the box when close enough ---
                if(self hasgoal("boxBuy")) // Cancel movement goal upon arrival
                    self cancelgoal("boxBuy");

                // Look at the box
                aim_offset = (randomfloatrange(-5,5), randomfloatrange(-5,5), randomfloatrange(-5,5));
                self lookat(current_box.origin + aim_offset);
                wait randomfloatrange(0.5, 1.0); // Simulate reaction

                // Final check before spending points
                if(self.score < 950 ||
                   is_true(current_box._box_open) ||
                   flag("moving_chest_now") ||
                   (isDefined(current_box.is_locked) && current_box.is_locked) ||
                   (isDefined(current_box.chest_user) && current_box.chest_user != self) ||
                   self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
                {
                    return; // Conditions changed, abort
                }

                // Set global usage flag
                level.box_in_use_by_bot = self;
                current_box.chest_user = self; // Mark user on the box

                // Store state for monitoring
                self.bot.current_box = current_box;
                self.bot.waiting_for_box_animation = true;
                self.bot.box_payment_time = GetTime();

                // Deduct points
                self maps\mp\zombies\_zm_score::minus_to_player_score(950);
                self PlaySound("zmb_cha_ching");

                // Set cooldown times
                self.bot.last_box_interaction_time = GetTime();
                level.last_bot_box_interaction_time = GetTime();

                // Trigger the box using multiple methods for reliability
                if(isDefined(current_box.unitrigger_stub) && isDefined(current_box.unitrigger_stub.trigger))
                    current_box.unitrigger_stub.trigger notify("trigger", self);
                else if(isDefined(current_box.use_trigger))
                     current_box.use_trigger notify("trigger", self);
                else
                    current_box notify("trigger", self); // Generic trigger

                // Start the monitor thread (handles waiting and weapon grabbing/decision)
                self thread bot_monitor_box_animation(current_box);

                return; // Monitor thread will handle the rest
            }
        }

        // Clean up any remaining box goal if we decided not to proceed
        if(self hasgoal("boxBuy") || self hasgoal("boxGrab"))
        {
            self cancelgoal("boxBuy");
            self cancelgoal("boxGrab");
        }
        // --- End: Logic to buy a new box spin ---
    }
}