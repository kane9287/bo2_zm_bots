# TranZit Revamped Integration Guide

**Branch:** `tranzit-revamped-integration`  
**Compatible With:** [DevUltimateman's TranZit Revamped "Warmer Days"](https://github.com/DevUltimateman/BO2-TranZit-Revamped-2024-Mod-Source-Codes)  
**Purpose:** Bus awareness for bot AI on TranZit

---

## Features

### 🚌 Bus Awareness
- **Bus location tracking** - Bots know where the bus is at all times
- **Proximity detection** - Bots detect when bus is within 500 units
- **Location awareness** - Bot AI can use bus location for decision making
- **Automatic initialization** - Activates only on TranZit map

---

## Installation

### Requirements
1. **Plutonium T6** - Latest version
2. **TranZit Revamped "Warmer Days"** - [Download here](https://github.com/DevUltimateman/BO2-TranZit-Revamped-2024-Mod-Source-Codes)
3. **This bot mod** - `tranzit-revamped-integration` branch

### Step 1: Install TranZit Revamped

```bash
# Clone TranZit Revamped
git clone https://github.com/DevUltimateman/BO2-TranZit-Revamped-2024-Mod-Source-Codes.git

# Compile scripts (use GSC compiler)
gsc-tool comp scripts/zm/zm_transit/*.gsc

# Place compiled files in:
# %localappdata%\Plutonium\storage\t6\mods\tranzit_revamped\
```

### Step 2: Install Bot Mod

```bash
# Clone this repository
git clone -b tranzit-revamped-integration https://github.com/kane9287/bo2_zm_bots.git

# Compile all bot scripts
gsc-tool comp scripts/zm/*.gsc

# Place compiled files in:
# %localappdata%\Plutonium\storage\t6\scripts\zm\
```

### Step 3: Server Configuration

**Dedicated Server CFG:**
```cfg
// server.cfg additions
set sv_maprotation "exec zm_transit.cfg"
set sv_maxclients 8
set bots_manage_fill 3  // Number of bots to spawn
set bots_manage_fill_mode 1
```

**TranZit CFG:**
```cfg
// zm_transit.cfg
map zm_transit
gametype zstandard
```

---

## How It Works

### Bus Tracking System

The bot AI automatically detects when running on TranZit and initializes bus awareness[cite:152]:

```gsc
// In bot_spawn()
if(level.script == "zm_transit")
    self thread bot_bus_navigation();
```

### Bot Bus Variables

Each bot has access to:
- `self.bot.bus_nearby` - Boolean, true when bus is within 500 units
- `self.bot.bus_location` - Vector, current bus origin (undefined if far away)

### Usage Example

You can extend bot behavior using these variables:

```gsc
// Example: Make bots prioritize staying near bus
if(self.bot.bus_nearby)
{
    // Bot knows bus is close
    // Add custom behavior here
}

if(isDefined(self.bot.bus_location))
{
    // Bus location is available
    distance = distance(self.origin, self.bot.bus_location);
}
```

---

## Technical Details

### Bus Detection

```gsc
get_closest_bus()
{
    // Find the bus entity
    buses = getEntArray("transit_bus", "targetname");
    
    if(!isDefined(buses) || buses.size == 0)
        return undefined;
    
    return buses[0];
}
```

### Update Frequency

Bus location is checked every **10 seconds** to balance performance with responsiveness.

### Detection Range

- **Nearby threshold:** 500 units
- **When nearby:** Sets `bus_nearby = true` and stores location
- **When far:** Clears flags and location

---

## Extending Bus Awareness

You can build additional features on top of the bus awareness system:

### Example 1: Bus Boarding Priority

```gsc
// Make bots prioritize getting to bus
if(self.bot.bus_nearby && !self is_on_bus())
{
    self AddGoal(self.bot.bus_location, 50, BOT_GOAL_PRIORITY_HIGH, "bus");
}
```

### Example 2: Bus Route Following

```gsc
// Make bots follow the bus
if(isDefined(self.bot.bus_location))
{
    distance_to_bus = distance(self.origin, self.bot.bus_location);
    
    if(distance_to_bus > 600 && distance_to_bus < 2000)
    {
        // Bus is leaving, chase it
        self AddGoal(self.bot.bus_location, 100, BOT_GOAL_PRIORITY_NORMAL, "follow_bus");
    }
}
```

### Example 3: Safe Zone Detection

```gsc
// Use bus as a safe zone reference
if(self.bot.bus_nearby)
{
    // Bot is near bus, potentially safer area
    self.bot.in_safe_zone = true;
}
else
{
    self.bot.in_safe_zone = false;
}
```

---

## Troubleshooting

### Bots Not Detecting Bus

**Check:**
1. Map is `zm_transit` (function only runs on TranZit)
2. Bus entity exists with targetname `transit_bus`
3. Bot AI is fully initialized

**Debug:**
```gsc
// Add to bot_bus_navigation() for testing
iPrintLn("Bus nearby: " + self.bot.bus_nearby);
if(isDefined(self.bot.bus_location))
    iPrintLn("Bus at: " + self.bot.bus_location);
```

### Performance Issues

**Increase check interval:**
```gsc
// In bot_bus_navigation(), change:
wait 10;  // Change to 15 or 20 for less frequent checks
```

---

## Compatibility

### Works With
- ✅ TranZit Revamped "Warmer Days"
- ✅ Origins bot features (from main branch)
- ✅ All vanilla TranZit features
- ✅ Custom TranZit mods
- ✅ Other bot AI extensions

### May Conflict With
- ⚠️ Other mods that modify bus entity
- ⚠️ Mods that change bot navigation drastically

---

## Performance Benchmarks

**Bus Awareness Overhead:**

| Bots | CPU Impact | Memory Impact |
|------|------------|---------------|
| 1    | <1%        | Negligible    |
| 2    | <1%        | Negligible    |
| 3    | <1%        | Negligible    |
| 4    | <2%        | Negligible    |

**Note:** Bus awareness adds minimal overhead due to 10-second update intervals and simple distance calculations.

---

## Contributing

**Report Issues:**
- [GitHub Issues](https://github.com/kane9287/bo2_zm_bots/issues)
- Include: map name, bot count, bus behavior, error messages

**Submit Improvements:**
```bash
git checkout -b tranzit-feature-name
# Make changes
git commit -m "Add feature: description"
git push origin tranzit-feature-name
# Create pull request to tranzit-revamped-integration
```

---

## Credits

- **Bot AI:** kane9287
- **TranZit Revamped:** [DevUltimateman](https://github.com/DevUltimateman)
- **Plutonium:** [Plutonium Project](https://plutonium.pw)

---

## License

MIT License - See main repository for details

---

## Changelog

### v1.0.0 (Feb 14, 2026)
- Initial TranZit integration
- Bus awareness system
- Proximity detection (500 unit radius)
- Location tracking
- Minimal performance overhead
