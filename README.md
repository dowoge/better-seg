# better-seg

A small [bhoptimer](https://github.com/shavitush/bhoptimer) add-on. When a player with a running timer teleports to a checkpoint, the plugin keeps them frozen at the checkpoint until they start moving, and it appends the current freeze setting to the checkpoint `KeyHintText` panel.

## Features

- Works on every style, but only once the run timer has started: `Shavit_GetTimerStatus` is not `Timer_Stopped` and `Shavit_GetClientTime` is above 5 ticks. Inside the start zone shavit restarts the timer every tick, so the time stays near zero there; a checkpoint saved while passing through the start zone with a running timer keeps its time and still freezes.
- Freezes the player in place after `Shavit_TeleportToCheckpoint` until they press a movement key (`vel[0]`/`vel[1]` become non-zero). While frozen, the player is re-teleported to the checkpoint every tick with zero velocity and `MOVETYPE_NONE`, so client prediction matches the server and there are no prediction errors until the player moves.
- Blocks checkpoint saves while the player is still frozen after a teleport (`Shavit_OnSavePre`).
- Appends `Freeze after teleport: ON/OFF` to the checkpoint `KeyHintText` HUD panel.
- Notifies the player about `!seg_freeze` when they switch style.
- Remembers each player's freeze setting with a clientprefs cookie (`betterseg_freeze`); also toggleable from the `!settings` menu.

## Commands

| Command | Description |
| --- | --- |
| `sm_seg_freeze` | Toggle freezing after teleport for the calling player (default: on, saved per player). |

## Requirements

- SourceMod 1.11 with the clientprefs extension
- [bhoptimer](https://github.com/shavitush/bhoptimer) with `shavit-core` and `shavit-checkpoints` running

## Building

Compile with the SourceMod 1.11 compiler and the bhoptimer include files on the include path:

```sh
spcomp -i /path/to/bhoptimer/addons/sourcemod/scripting/include addons/sourcemod/scripting/betterseg.sp
```

## Provenance

The original source of this plugin was lost. This source was reconstructed from the compiled `betterseg.smx` (built with SourcePawn 1.11.0.6934 on 2025-02-03) using its embedded debug information. Recompiling it with the same compiler and the bhoptimer includes from commit `afa6b07` (v3.5.0 era) produces a byte-identical `.code` section, identical debug line and local tables, and a `.data` section that differs only in the embedded compile timestamp. Function names, variable names, argument names and line numbers match the original.
