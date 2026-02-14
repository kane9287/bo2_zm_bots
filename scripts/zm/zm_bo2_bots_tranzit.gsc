// scripts/zm/zm_bo2_bots_tranzit.gsc
// Bot integration for TranZit Revamped "Warmer Days" by DevUltimateman
// Adds bot support for custom TranZit features and point farming

#include maps\mp\gametypes\_hud_util;
#include maps\mp\gametypes\_hud_message;
#include maps\mp\zombies\_zm_stats;
#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\zombies\_zm_utility;
#include maps\mp\zombies\_zm_weapons;
#include maps\mp\zombies\_zm_buildables;

init()
{
    // Only run on TranZit
    if ( getDvar( "mapname" ) != "zm_transit" )
        return;
    
    level thread on_player_spawned();
    level thread setup_tranzit_features();
}

setup_tranzit_features()
{
    level endon( "end_game" );
    
    // Wait for game to fully load
    flag_wait( "initial_blackscreen_passed" );
    wait 5;
    
    // Initialize TranZit-specific bot behavior
    level.bot_tranzit_bank_enabled = true;
    level.bot_tranzit_power_priority = true;
    level.bot_tranzit_bus_aware = true;
    
    // Bot banking configuration
    level.bot_auto_bank_threshold = 50000; // Auto-deposit above 50k
    level.bot_min_points_keep = 20000; // Keep 20k for perks/weapons
    
    level thread monitor_bot_banking();
}

on_player_spawned()
{
    level endon( "end_game" );
    
    while ( true )
    {
        level waittill( "connected", player );
        
        if ( !isDefined( player.is_bot ) || !player.is_bot )
            continue;
        
        player thread bot_tranzit_behavior();
        player thread bot_bank_manager();
        player thread bot_power_station_handler();
        player thread bot_bus_navigation();
    }
}

bot_tranzit_behavior()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    
    // Wait for bot to fully spawn
    while ( !isDefined( self.bot ) || !isDefined( self.bot.initialized ) )
        wait 0.05;
    
    // TranZit-specific bot priorities
    self.bot.tranzit_power_activated = false;
    self.bot.last_bank_check = 0;
    self.bot.prefer_pap_weapons = true;
    
    // Custom weapon preferences for TranZit
    self.bot.preferred_weapons = [];
    self.bot.preferred_weapons[ 0 ] = "ray_gun_zm";
    self.bot.preferred_weapons[ 1 ] = "hamr_zm";
    self.bot.preferred_weapons[ 2 ] = "an94_zm";
    self.bot.preferred_weapons[ 3 ] = "dsr50_zm";
    self.bot.preferred_weapons[ 4 ] = "tar21_zm";
    
    // Enable aggressive point farming
    self.bot.farm_mode = true;
}

bot_bank_manager()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    
    if ( !level.bot_tranzit_bank_enabled )
        return;
    
    while ( true )
    {
        wait 30; // Check every 30 seconds
        
        if ( !self.is_bot )
            continue;
        
        // Auto-deposit when points are high
        if ( self.score > level.bot_auto_bank_threshold )
        {
            deposit_amount = self.score - level.bot_min_points_keep;
            
            if ( deposit_amount >= 1000 )
            {
                // Use Universal Bank commands
                self deposit_logic( int( deposit_amount ) );
                wait 1;
            }
        }
        
        // Auto-withdraw when points are low and bank has funds
        if ( self.score < 10000 && isDefined( self.account_value ) && self.account_value > 0 )
        {
            withdraw_amount = int( min( 30, self.account_value ) ); // Withdraw up to 30k
            self withdraw_logic( withdraw_amount * 1000 );
            wait 1;
        }
    }
}

bot_power_station_handler()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    
    if ( !level.bot_tranzit_power_priority )
        return;
    
    // Wait for map to load
    wait 10;
    
    while ( true )
    {
        wait 5;
        
        if ( !self.is_bot || self.bot.tranzit_power_activated )
            continue;
        
        // Check if power is on
        if ( isDefined( level.power_on ) && level.power_on )
        {
            self.bot.tranzit_power_activated = true;
            continue;
        }
        
        // Priority: Turn on power if possible
        // This will be handled by main bot AI once at power station
        // Just ensure bot knows power is important
        self.bot.power_priority = true;
    }
}

bot_bus_navigation()
{
    self endon( "disconnect" );
    level endon( "end_game" );
    
    if ( !level.bot_tranzit_bus_aware )
        return;
    
    // Wait for bot initialization
    while ( !isDefined( self.bot ) )
        wait 0.05;
    
    while ( true )
    {
        wait 10;
        
        if ( !self.is_bot )
            continue;
        
        // Check if bus exists and is nearby
        bus = get_closest_bus();
        
        if ( !isDefined( bus ) )
            continue;
        
        distance_to_bus = distance( self.origin, bus.origin );
        
        // If bus is close, consider boarding
        if ( distance_to_bus < 500 )
        {
            // Bot will naturally path toward objectives
            // Bus awareness helps with decision making
            self.bot.bus_nearby = true;
            self.bot.bus_location = bus.origin;
        }
        else
        {
            self.bot.bus_nearby = false;
        }
    }
}

get_closest_bus()
{
    // Find the bus entity
    buses = getEntArray( "transit_bus", "targetname" );
    
    if ( !isDefined( buses ) || buses.size == 0 )
        return undefined;
    
    return buses[ 0 ];
}

// Universal Bank integration functions
// These mirror the Universal Bank mod for bot compatibility

deposit_logic( amount )
{
    if ( !isDefined( self.account_value ) )
    {
        // Initialize bank account
        self.account_value = self maps\mp\zombies\_zm_stats::get_map_stat( "depositBox", "zm_transit" );
    }
    
    if ( self.score <= 0 )
        return;
    
    if ( self.account_value >= 250 )
        return;
    
    if ( !isDefined( amount ) || amount < 1000 )
        return;
    
    num_score = int( floor( self.score / 1000 ) );
    num_amount = int( floor( amount / 1000 ) );
    
    // Clamp deposit amount to player's score
    if ( num_amount > num_score )
        num_amount = num_score;
    
    // Clamp deposit amount to 250 (max amount allowed in bank)
    if ( num_amount > 250 )
        num_amount = 250;
    
    // If amount is greater than what can fit in the bank clamp the deposit amount
    new_balance = self.account_value + num_amount;
    over_balance = new_balance - 250;
    
    if ( over_balance > 0 )
    {
        num_amount -= over_balance;
        new_balance -= over_balance;
    }
    
    self.account_value = new_balance;
    final_amount = num_amount * 1000;
    self.score -= final_amount;
    self maps\mp\zombies\_zm_stats::set_map_stat( "depositBox", new_balance, "zm_transit" );
    
    // Bots don't print, but log for debugging
    // iPrintLn( "Bot deposited " + final_amount );
}

withdraw_logic( amount )
{
    if ( !isDefined( self.account_value ) )
    {
        self.account_value = self maps\mp\zombies\_zm_stats::get_map_stat( "depositBox", "zm_transit" );
    }
    
    if ( self.account_value <= 0 )
        return;
    
    if ( self.score >= 1000000 )
        return;
    
    if ( !isDefined( amount ) || amount < 1000 )
        return;
    
    num_score = int( floor( self.score / 1000 ) );
    num_amount = int( floor( amount / 1000 ) );
    
    // Clamp amount to account value
    if ( num_amount > self.account_value )
        num_amount = self.account_value;
    
    new_balance = self.account_value - num_amount;
    
    // If withdraw amount + player's current score is greater than 1000 clamp the withdraw amount
    over_balance = num_score + num_amount - 1000;
    max_score_available = abs( num_score - 1000 );
    
    if ( over_balance > 0 )
    {
        new_balance = over_balance;
        num_amount = max_score_available;
    }
    
    self.account_value = new_balance;
    final_amount = num_amount * 1000;
    self.score += final_amount;
    self maps\mp\zombies\_zm_stats::set_map_stat( "depositBox", new_balance, "zm_transit" );
}

monitor_bot_banking()
{
    level endon( "end_game" );
    
    while ( true )
    {
        wait 60; // Every minute
        
        total_bot_points = 0;
        total_bot_bank = 0;
        
        foreach ( player in level.players )
        {
            if ( !isDefined( player.is_bot ) || !player.is_bot )
                continue;
            
            total_bot_points += player.score;
            
            if ( isDefined( player.account_value ) )
                total_bot_bank += player.account_value * 1000;
        }
        
        // Debug logging (for development)
        // iPrintLn( "Bot Points: " + total_bot_points + " | Bot Bank: " + total_bot_bank );
    }
}
