# better-seg

A small [bhoptimer](https://github.com/shavitush/bhoptimer) add-on. When a player with a running timer teleports to a checkpoint, the plugin keeps them frozen at the checkpoint until they start moving, and it appends the current freeze setting to the checkpoint `KeyHintText` panel.

## Features

- Works on every style, but only once the run timer has started: `Shavit_GetTimerStatus` is not `Timer_Stopped` and `Shavit_GetClientTime` is above 5 ticks. Inside the start zone shavit restarts the timer every tick, so the time stays near zero there; a checkpoint saved while passing through the start zone with a running timer keeps its time and still freezes.
- Freezes the player in place after `Shavit_TeleportToCheckpoint` until they press a movement key (`vel[0]`/`vel[1]` become non-zero). While frozen, the player is re-teleported to the checkpoint every tick with zero velocity and `MOVETYPE_NONE`, so client prediction matches the server and there are no prediction errors until the player moves.
- Ramps the player's movement speed back up after the unfreeze instead of releasing at full speed (`betterseg_release_ramp`). The client only finds out about the unfreeze one round trip later and then re-simulates every unacknowledged command, so a full-speed release shows up as a single jump of `round trip × speed`. The plugin instead scales `m_flLaggedMovementValue` (which the client predicts) along `r += (1 - r) / tau` with `tau = round trip in ticks`, which makes the growing prediction lead exactly fill in the missing motion: the screen moves at full speed from the first snapshot after the key press, with no jump. The timer is only credited the simulated fraction of each ramp tick and replay frames are dropped for ticks that did not complete a whole simulated tick, so the recorded run is the same as without the ramp. The trade-off is that inputs during the ramp act on a slowed simulation for roughly one round trip.
- Blocks checkpoint saves while the player is still frozen after a teleport (`Shavit_OnSavePre`).
- Appends `Freeze after teleport: ON/OFF` to the checkpoint `KeyHintText` HUD panel.
- Notifies the player about `!seg_freeze` when they switch style (`betterseg_style_hint`, default `1`).
- Remembers each player's freeze setting with a clientprefs cookie (`betterseg_freeze`); also toggleable from the `!settings` menu.

## Commands

| Command | Description |
| --- | --- |
| `sm_seg_freeze` | Toggle freezing after teleport for the calling player (default: on, saved per player). |

## ConVars

| ConVar | Default | Description |
| --- | --- | --- |
| `betterseg_style_hint` | `1` | Print the `!seg_freeze` hint in chat on style change. Config written to `cfg/sourcemod/betterseg.cfg`. |
| `betterseg_release_ramp` | `1.0` | Length of the post-unfreeze speed ramp in round trips. `1.0` makes the screen move at exactly full speed; lower values overshoot briefly, higher values start slow. `0` releases at full speed immediately (old behaviour, jumps on high ping). |

## Requirements

- SourceMod 1.11 with the clientprefs extension
- [bhoptimer](https://github.com/shavitush/bhoptimer) with `shavit-core` and `shavit-checkpoints` running (`shavit-replay-recorder` optional)

## Building

Compile with the SourceMod 1.11 compiler and the bhoptimer include files on the include path:

```sh
spcomp -i /path/to/bhoptimer/addons/sourcemod/scripting/include addons/sourcemod/scripting/betterseg.sp
```

## Provenance

The original source of this plugin was lost. This source was reconstructed from the compiled `betterseg.smx` (built with SourcePawn 1.11.0.6934 on 2025-02-03) using its embedded debug information. Recompiling it with the same compiler and the bhoptimer includes from commit `afa6b07` (v3.5.0 era) produces a byte-identical `.code` section, identical debug line and local tables, and a `.data` section that differs only in the embedded compile timestamp. Function names, variable names, argument names and line numbers match the original.
