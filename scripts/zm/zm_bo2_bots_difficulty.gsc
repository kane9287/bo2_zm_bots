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
	
	// IMPROVED Base values - Much better starting skill
	// Old values: 40-70ms reaction, 100-250ms fire
	// New values: Faster reactions, quicker shooting
	base_min_reaction = 25;  // Was 40 - Now 37.5% faster
	base_max_reaction = 45;  // Was 70 - Now 35% faster
	base_min_fire = 60;      // Was 100 - Now 40% faster
	base_max_fire = 150;     // Was 250 - Now 40% faster
	
	// Adjusted values (faster reactions at higher rounds)
	adjusted_min_reaction = int(base_min_reaction / difficulty_multiplier);
	adjusted_max_reaction = int(base_max_reaction / difficulty_multiplier);
	adjusted_min_fire = int(base_min_fire / difficulty_multiplier);
	adjusted_max_fire = int(base_max_fire / difficulty_multiplier);
	
	// Don't go too low (but lower than before for max skill)
	adjusted_min_reaction = max(adjusted_min_reaction, 15);  // Was 20
	adjusted_max_reaction = max(adjusted_max_reaction, 25);  // Was 35
	adjusted_min_fire = max(adjusted_min_fire, 35);          // Was 50
	adjusted_max_fire = max(adjusted_max_fire, 100);         // Was 150
	
	// Apply changes - concatenate with empty string to convert to string
	setdvar("bot_MinReactionTime", "" + adjusted_min_reaction);
	setdvar("bot_MaxReactionTime", "" + adjusted_max_reaction);
	setdvar("bot_MinFireTime", "" + adjusted_min_fire);
	setdvar("bot_MaxFireTime", "" + adjusted_max_fire);
	
	// IMPROVED Yaw speed for better tracking
	base_yaw = 6.0;  // Was 4.0 - Now 50% faster turning
	adjusted_yaw = base_yaw * difficulty_multiplier;
	adjusted_yaw = min(adjusted_yaw, 10.0); // Cap at 10 (was 8)
	setdvar("bot_YawSpeed", "" + adjusted_yaw);
	
	// Debug output
	if(GetDvarInt("bo2_zm_bots_debug") == 1)
	{
		iprintln("^3Bot Difficulty Adjusted for Round " + level.round_number);
		iprintln("^2Reaction: " + adjusted_min_reaction + "-" + adjusted_max_reaction + "ms");
		iprintln("^2Fire Time: " + adjusted_min_fire + "-" + adjusted_max_fire + "ms");
		iprintln("^2Yaw Speed: " + adjusted_yaw);
	}
}
