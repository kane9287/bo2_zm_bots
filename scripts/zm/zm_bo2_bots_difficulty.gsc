// zm_bo2_bots_difficulty.gsc
// Dynamic difficulty scaling for bots
#include common_scripts\utility;
#include maps\mp\_utility;

init()
{
	level thread monitor_round_changes();
}

monitor_round_changes()
{
	level endon("end_game");
	
	// Wait for game to start
	flag_wait("initial_blackscreen_passed");
	wait 5;
	
	previous_round = level.round_number;
	
	while(true)
	{
		wait 1;
		
		// Check if round changed
		if(level.round_number != previous_round)
		{
			previous_round = level.round_number;
			bot_adjust_difficulty_by_round();
		}
	}
}

bot_adjust_difficulty_by_round()
{
	// Scale reaction time and accuracy based on round
	// Cap at round 30 for maximum difficulty
	difficulty_multiplier = min(level.round_number / 30.0, 1.5);
	
	// Base values (round 1)
	base_min_reaction = 40;
	base_max_reaction = 70;
	base_min_fire = 100;
	base_max_fire = 250;
	
	// Adjusted values (faster reactions at higher rounds)
	adjusted_min_reaction = int(base_min_reaction / difficulty_multiplier);
	adjusted_max_reaction = int(base_max_reaction / difficulty_multiplier);
	adjusted_min_fire = int(base_min_fire / difficulty_multiplier);
	adjusted_max_fire = int(base_max_fire / difficulty_multiplier);
	
	// Don't go too low
	adjusted_min_reaction = max(adjusted_min_reaction, 20);
	adjusted_max_reaction = max(adjusted_max_reaction, 35);
	adjusted_min_fire = max(adjusted_min_fire, 50);
	adjusted_max_fire = max(adjusted_max_fire, 150);
	
	// Apply changes
	setdvar("bot_MinReactionTime", string(adjusted_min_reaction));
	setdvar("bot_MaxReactionTime", string(adjusted_max_reaction));
	setdvar("bot_MinFireTime", string(adjusted_min_fire));
	setdvar("bot_MaxFireTime", string(adjusted_max_fire));
	
	// Adjust yaw speed for better tracking at higher rounds
	base_yaw = 4.0;
	adjusted_yaw = base_yaw * difficulty_multiplier;
	adjusted_yaw = min(adjusted_yaw, 8.0); // Cap at 8
	setdvar("bot_YawSpeed", string(adjusted_yaw));
	
	// Debug output
	if(GetDvarInt("bo2_zm_bots_debug") == 1)
	{
		iprintln("^3Bot Difficulty Adjusted for Round " + level.round_number);
		iprintln("^2Reaction: " + adjusted_min_reaction + "-" + adjusted_max_reaction + "ms");
		iprintln("^2Fire Time: " + adjusted_min_fire + "-" + adjusted_max_fire + "ms");
	}
}