#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <cstrike>
#include <convar_class>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <shavit>
#define REQUIRE_PLUGIN

#pragma newdecls required
#pragma semicolon 1

bool g_bFreeze[MAXPLAYERS+1] = {true, ...};
bool g_bTeleported[MAXPLAYERS+1];
int g_nTeleportedTo[MAXPLAYERS+1];
UserMsg g_iKeyHintText;
Cookie g_hFreezeCookie;
ConVar g_cvStyleHint;
ConVar g_cvReleaseRamp;
float g_fRampTau[MAXPLAYERS+1];
float g_fRamp[MAXPLAYERS+1];
float g_fRampBase[MAXPLAYERS+1];
float g_fRampSimTicks[MAXPLAYERS+1];
int g_iRampFrames[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "Better seg",
	author = "wool (?), source reconstructed by tommy",
	description = "Freezes players after checkpoint teleports while the timer is running",
	version = "1.1.0",
	url = "https://github.com/dowoge/better-seg"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_seg_freeze", Cmd_Freeze, "Start recording");

	g_iKeyHintText = GetUserMessageId("KeyHintText");
	HookUserMessage(g_iKeyHintText, KeyText, true);

	g_hFreezeCookie = new Cookie("betterseg_freeze", "Freeze after checkpoint teleport", CookieAccess_Protected);
	g_hFreezeCookie.SetPrefabMenu(CookieMenu_OnOff_Int, "Freeze after teleport", OnFreezeCookieMenu);

	g_cvStyleHint = CreateConVar("betterseg_style_hint", "1", "Print the !seg_freeze hint in chat when a player changes style.", 0, true, 0.0, true, 1.0);
	g_cvReleaseRamp = CreateConVar("betterseg_release_ramp", "1.0", "After unfreezing, ramp the player's movement speed up over this many round trips so the client never has to catch up in one jump. 0 disables.", 0, true, 0.0);
	AutoExecConfig(true, "betterseg");
}

public void OnAllPluginsLoaded()
{
}

public void OnClientConnected(int client)
{
	g_bTeleported[client] = false;
	g_bFreeze[client] = true;
	g_fRampTau[client] = 0.0;
}

public void OnClientCookiesCached(int client)
{
	LoadFreezeCookie(client);
}

void LoadFreezeCookie(int client)
{
	char buf[8];
	g_hFreezeCookie.Get(client, buf, sizeof(buf));

	g_bFreeze[client] = (buf[0] == '\0') || (StringToInt(buf) != 0);
}

public void OnFreezeCookieMenu(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_SelectOption)
	{
		LoadFreezeCookie(client);
	}
}

bool TimerStarted(int client)
{
	// shavit restarts the timer every tick inside the start zone, so a timer
	// that has accumulated more than a couple of ticks has actually left it.
	return Shavit_GetTimerStatus(client) != Timer_Stopped && Shavit_GetClientTime(client) > 5.0 * GetTickInterval();
}

void Unfreeze(int client)
{
	if (!g_bTeleported[client])
	{
		return;
	}

	g_bTeleported[client] = false;

	if (GetEntityMoveType(client) == MOVETYPE_NONE)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}
}

// Client re-simulates unacked commands once it learns of the unfreeze, so a full-speed release
// jumps by rtt*speed. Ramping predicted movement speed lets the growing prediction lead fill that in.
void StartRamp(int client)
{
	float latency = GetClientLatency(client, NetFlow_Both);
	float tau = g_cvReleaseRamp.FloatValue * (RoundToCeil(latency / GetTickInterval()) + 1);

	if (tau <= 1.0)
	{
		return;
	}

	g_fRampTau[client] = tau;
	g_fRamp[client] = 0.0;
	g_fRampBase[client] = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
	g_fRampSimTicks[client] = 0.0;
	g_iRampFrames[client] = -1;

	AdvanceRamp(client);
}

void AdvanceRamp(int client)
{
	TrimSkippedReplayFrame(client);

	float r = g_fRamp[client] + (1.0 - g_fRamp[client]) / g_fRampTau[client];

	if (r >= 0.98)
	{
		StopRamp(client);
		return;
	}

	g_fRamp[client] = r;
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fRampBase[client] * r);

	int wholeTicks = RoundToFloor(g_fRampSimTicks[client]);
	g_fRampSimTicks[client] += r;

	bool skipped = RoundToFloor(g_fRampSimTicks[client]) == wholeTicks;
	g_iRampFrames[client] = (skipped && LibraryExists("shavit-replay-recorder")) ? Shavit_GetClientFrameCount(client) : -1;
}

void StopRamp(int client)
{
	if (g_fRampTau[client] <= 0.0)
	{
		return;
	}

	g_fRampTau[client] = 0.0;
	g_iRampFrames[client] = -1;
	Shavit_UpdateLaggedMovement(client, true);
}

void TrimSkippedReplayFrame(int client)
{
	if (g_iRampFrames[client] < 0)
	{
		return;
	}

	int expected = g_iRampFrames[client] + 1;
	g_iRampFrames[client] = -1;

	if (Shavit_GetClientFrameCount(client) != expected)
	{
		return;
	}

	ArrayList frames = Shavit_GetReplayData(client, true);

	if (frames == null)
	{
		return;
	}

	frames.Erase(frames.Length - 1);
	Shavit_SetReplayData(client, frames, true);
	delete frames;
}

public void Shavit_OnTimeIncrementPost(int client, float time)
{
	if (g_fRampTau[client] <= 0.0)
	{
		return;
	}

	timer_snapshot_t snapshot;
	Shavit_SaveSnapshot(client, snapshot, sizeof(snapshot));

	snapshot.iFractionalTicks -= RoundFloat((1.0 - g_fRamp[client]) * time / GetTickInterval() * 10000.0);

	while (snapshot.iFractionalTicks < 0)
	{
		snapshot.iFractionalTicks += 10000;
		snapshot.iFullTicks--;
	}

	Shavit_LoadSnapshot(client, snapshot, sizeof(snapshot), true);
}


public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (IsFakeClient(client) || GetClientTeam(client) == 1)
	{
		return;
	}

	if (g_fRampTau[client] > 0.0)
	{
		MoveType mt = GetEntityMoveType(client);

		if (Shavit_GetTimerStatus(client) != Timer_Running || (mt != MOVETYPE_WALK && mt != MOVETYPE_LADDER))
		{
			StopRamp(client);
		}
		else
		{
			AdvanceRamp(client);
		}
	}

	if (!g_bTeleported[client])
	{
		return;
	}

	if (!TimerStarted(client) || !g_bFreeze[client])
	{
		Unfreeze(client);
		return;
	}

	Shavit_TeleportToCheckpoint(client, g_nTeleportedTo[client], true);

	if (vel[0] || vel[1])
	{
		Unfreeze(client);
		StartRamp(client);
	}
	else
	{
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		SetEntityMoveType(client, MOVETYPE_NONE);
	}
}

public Action Shavit_OnSavePre(int client, int index, bool overflow, bool duplicate)
{
	if (g_bTeleported[client])
	{
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action Shavit_OnTeleport(int client, int index, int target)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	StopRamp(client);

	if (!g_bFreeze[client])
	{
		return Plugin_Continue;
	}

	g_nTeleportedTo[client] = index;
	g_bTeleported[client] = true;

	return Plugin_Continue;
}

public Action Cmd_Freeze(int client, int args)
{
	if (client < 1 || client > MaxClients)
	{
		return Plugin_Handled;
	}

	g_bFreeze[client] = !g_bFreeze[client];
	g_hFreezeCookie.Set(client, g_bFreeze[client] ? "1" : "0");

	PrintToChat(client, "Freeze after teleport: %s", g_bFreeze[client] ? "ON" : "OFF");

	return Plugin_Continue;
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	if (g_cvStyleHint.BoolValue)
	{
		Shavit_PrintToChat(client, "Use !seg_freeze to enable/disable freezing after teleports!");
	}

	Unfreeze(client);
	StopRamp(client);
}

public void Shavit_OnStop(int client, int track)
{
	StopRamp(client);
}

public void Shavit_OnRestart(int client, int track)
{
	StopRamp(client);
}

public Action Shavit_OnDelete(int client, int index, bool cleared)
{
	Unfreeze(client);

	return Plugin_Continue;
}

public Action KeyText(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!TimerStarted(players[0]) || GetClientTeam(players[0]) == 0)
	{
		return Plugin_Continue;
	}

	char buf[256];

	msg.ReadString(buf, 256);

	DataPack dp = new DataPack();
	dp.WriteCell(GetClientSerial(players[0]));
	dp.WriteString(buf);

	RequestFrame(SegmentFrame, dp);

	return Plugin_Handled;
}

void SegmentFrame(DataPack p)
{
	p.Reset();

	int client = GetClientFromSerial(p.ReadCell());

	char buf[256];
	p.ReadString(buf, 256);
	delete p;

	if (client == 0 || !TimerStarted(client))
	{
		return;
	}

	Format(buf, 256, "%s\n\nFreeze after teleport: %s", buf, g_bFreeze[client] ? "ON" : "OFF");

	Handle _buf = StartMessageOne("KeyHintText", client, USERMSG_BLOCKHOOKS);

	BfWriteByte(_buf, 1);
	BfWriteString(_buf, buf);

	EndMessage();
}
