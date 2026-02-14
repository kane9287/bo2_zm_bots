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
    self thread bot_give_starting_perks();
}

// NEW: Give bots Quick Revive and Juggernog at spawn
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
    {
        self thread maps\mp\zombies\_zm_perks::give_perk("specialty_armorvest");
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

    level.box_in_use_by_bot = undefined;
    level.last_bot_box_interaction_time = 0;
    level.pap_in_use_by_bot = undefined;
    level.last_bot_pap_time = 0;
    level.generator_in_use_by_bot = undefined;
    level.last_bot_generator_time = 0;

    if (!isdefined(level.bots))
        level.bots = [];

    bot_amount = GetDvarIntDefault("bo2_zm_bots_count", 2);

    iprintln("^2Spawning " + bot_amount + " bots...");

    for(i=0; i<bot_amount; i++)
    {
        iprintln("^3Spawning bot " + (i+1));
        bot_entity = spawn_bot();
        level.bots[level.bots.size] = bot_entity;
        wait 1;
    }

    if(level.script == "zm_tomb")
    {
        level thread scripts\zm\zm_bo2_bots_origins::init();
    }

    iprintln("^2Bot initialization complete");
}

bot_set_skill()
{
	setdvar( "bot_MinDeathTime", "100" );
	setdvar( "bot_MaxDeathTime", "200" );
	setdvar( "bot_MinFireTime", "50" );
	setdvar( "bot_MaxFireTime", "150" );
	setdvar( "bot_PitchUp", "-5" );
	setdvar( "bot_PitchDown", "10" );
	setdvar( "bot_Fov", "180" );
	setdvar( "bot_MinAdsTime", "1500" );
	setdvar( "bot_MaxAdsTime", "2500" );
	setdvar( "bot_MinCrouchTime", "100" );
	setdvar( "bot_MaxCrouchTime", "400" );
	setdvar( "bot_TargetLeadBias", "1" );
	setdvar( "bot_MinReactionTime", "10" );
	setdvar( "bot_MaxReactionTime", "30" );
	setdvar( "bot_StrafeChance", "1" );
	setdvar( "bot_MinStrafeTime", "2000" );
	setdvar( "bot_MaxStrafeTime", "4000" );
	setdvar( "scr_help_dist", "512" );
	setdvar( "bot_AllowGrenades", "1" );
	setdvar( "bot_MinGrenadeTime", "1500" );
	setdvar( "bot_MaxGrenadeTime", "4000" );
	setdvar( "bot_MeleeDist", "70" );
	setdvar( "bot_YawSpeed", "6" );
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
    if (!isDefined(self.bot.box_purchase_time) || GetTime() > self.bot.box_purchase_time)
    {
        self.bot.box_purchase_time = GetTime() + 1500;

        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            return;

        if(self.score < 950)
            return;

        if(isDefined(level.box_in_use_by_bot) && level.box_in_use_by_bot != self)
        {
            return;
        }

        if(isDefined(level.last_bot_box_interaction_time) && (GetTime() - level.last_bot_box_interaction_time < 10000))
            return;

        if(isDefined(self.bot.last_box_interaction_time) && (GetTime() - self.bot.last_box_interaction_time < 5000))
            return;

        if(!isDefined(self.bot.grab_weapon_time) || GetTime() > self.bot.grab_weapon_time)
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

            if(isDefined(activeBox))
            {
                if(closestOpenBoxDist < 100)
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
                else if (closestOpenBoxDist < 800)
                {
                    if(!self hasgoal("boxGrab"))
                    {
                         self AddGoal(activeBox.origin, 75, 3, "boxGrab");
                    }
                    return;
                }
            }
        }


        if(is_true(self.bot.waiting_for_box_animation))
        {
            if((!isDefined(self.bot.box_payment_time) || (GetTime() - self.bot.box_payment_time > 10000)))
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

        dist = Distance(self.origin, current_box.origin);
        interaction_dist = 100;
        detection_dist = 800;

        if(self.score >= 950 && dist < detection_dist)
        {
            if(FindPath(self.origin, current_box.origin, undefined, 0, 1))
            {
                if(dist > interaction_dist)
                {
                    if(!self hasgoal("boxBuy") || Distance(self GetGoal("boxBuy"), current_box.origin) > 50)
                    {
                        self AddGoal(current_box.origin, 75, 2, "boxBuy");
                    }
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

// Continue with the rest of the file - I'll include the critical functions only due to space
// The full file would include all the other functions unchanged