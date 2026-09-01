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

public Plugin myinfo =
{
	name = "Better seg",
	author = "wool (?), source reconstructed by tommy",
	description = "Freezes players after checkpoint teleports on segmented styles",
	version = "1.0.0",
	url = "https://github.com/dowoge/better-seg"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_seg_freeze", Cmd_Freeze, "Start recording");

	g_iKeyHintText = GetUserMessageId("KeyHintText");
	HookUserMessage(g_iKeyHintText, KeyText, true);
}

public void OnAllPluginsLoaded()
{
}

public void OnClientConnected(int client)
{
	g_bTeleported[client] = false;
}

bool CanSegment(int client)
{
	return Shavit_GetStyleSettingBool(Shavit_GetBhopStyle(client), "segments");
}


public void OnPlayerRunCmdPre(int client, int buttons, int impulse, const float vel[3], const float angles[3], int weapon, int subtype, int cmdnum, int tickcount, int seed, const int mouse[2])
{
	if (IsFakeClient(client) || GetClientTeam(client) == 1)
	{
		return;
	}

	if (!CanSegment(client))
	{
		g_bTeleported[client] = false;
		return;
	}

	if (g_bTeleported[client])
	{

		if (g_bFreeze[client])
		{
			Shavit_TeleportToCheckpoint(client, g_nTeleportedTo[client], true);

			if (vel[0] || vel[1])
			{
				g_bTeleported[client] = false;
			}
		}
		else
		{
			g_bTeleported[client] = false;
		}
	}

	return;
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

	PrintToChat(client, "Freeze after teleport: %s", g_bFreeze[client] ? "ON" : "OFF");

	return Plugin_Continue;
}

public void Shavit_OnStyleChanged(int client, int oldstyle, int newstyle, int track, bool manual)
{
	if (Shavit_GetStyleSettingBool(newstyle, "segments"))
	{
		Shavit_PrintToChat(client, "Use !seg_freeze to enable/disable freezing after teleports!");
	}

	g_bTeleported[client] = false;
}

public Action Shavit_OnDelete(int client, int index, bool cleared)
{
	g_bTeleported[client] = false;

	return Plugin_Continue;
}

public Action KeyText(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!CanSegment(players[0]) || GetClientTeam(players[0]) == 0)
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

	if (client == 0 || !CanSegment(client))
	{
		return;
	}

	Format(buf, 256, "%s\n\nFreeze after teleport: %s", buf, g_bFreeze[client] ? "ON" : "OFF");

	Handle _buf = StartMessageOne("KeyHintText", client, USERMSG_BLOCKHOOKS);

	BfWriteByte(_buf, 1);
	BfWriteString(_buf, buf);

	EndMessage();
}
