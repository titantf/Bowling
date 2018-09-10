/**
 *		
 *		Bowling Gamemode for Team Fortress 2
 *		https://github.com/TitanTF/Bowling
 *		
**/

#include <sdkhooks>
#include <tf2_stocks>
#include <tf2items_giveweapon>

#undef REQUIRE_PLUGIN
#tryinclude <steamtools>
#define REQUIRE_PLUGIN

#if defined _bSteamTools_included
bool bSteamTools;
#endif

#define PLUGIN_VERSION "1.0"
#define HIDEHUD_HEALTH (1 << 3)

ConVar
	g_cvMaxPlayers,
	g_cvWFP_Time,
	g_cvRoll_Time,
	g_cvGib;
	
Handle
	g_hHud_Party1,
	g_hHud_Party2,

	g_hHud_Score,

	g_hHud_Frame,
	g_hHud_Notifications;
	
int
	g_iMaxPlayers,
	g_iWaitingForPlayers,
	g_iRollTime,

	g_iAlpha = 255,
	
	g_iRemaining_Party1,
	g_iRemaining_Party2,

	g_iCurrentPlayer_Party1,
	g_iCurrentPlayer_Party2,
	
	g_iPlayers_Party1,
	g_iPlayers_Party2,

	g_iReady_Party1,
	g_iReady_Party2,

	g_iFrame_Lane1,
	g_iFrame_Lane2,
	
	g_iScore[MAXPLAYERS+1] = 0,

	g_iParty[MAXPLAYERS+1] = 0,
	g_iReady[MAXPLAYERS+1] = 0;
	
bool
	g_iAlpha_Add = false,
	
	g_bMatch_Party1 = false,
	g_bMatch_Party2 = false,
	
	g_bPlayerSelected_Lane1 = false,
	g_bPlayerSelected_Lane2 = false,
	
	g_bRolled[MAXPLAYERS+1] = false;
	

public Plugin myinfo = 
{
	name = "Bowling for TF2",
	author = "myst",
	description = "Adds a bowling gamemode to TF2. Only works on bowl_ and bowling_ maps.",
	version = PLUGIN_VERSION,
	url = "https://titan.tf"
}

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_TF2) {
		SetFailState("This plugin does not support any game besides TF2.");
	}
	
	RegConsoleCmd("sm_bhelp", Command_Help);
	
	RegConsoleCmd("sm_join", Command_SelectLane);
	RegConsoleCmd("sm_lane", Command_SelectLane);
	RegConsoleCmd("sm_lanes", Command_SelectLane);
	RegConsoleCmd("sm_bowl", Command_SelectLane);

	RegConsoleCmd("sm_r", Command_Ready);
	RegConsoleCmd("sm_ready", Command_Ready);
	
	RegConsoleCmd("sm_leave", Command_Leave);
	
	RegAdminCmd("sm_teleport", Command_Teleport, ADMFLAG_GENERIC, "Used to teleport a player to where you are pointing at. Use this to setup your pins.");
	RegAdminCmd("sm_getpos", Command_GetPos, ADMFLAG_GENERIC, "Used to print the coordinates of all pins from either lane 1 or 2. Use this after setting up the positions using sm_teleport.");
	
	g_cvMaxPlayers = CreateConVar("bowling_maxplayers", "6", "Sets the maximum players per lane.", FCVAR_NOTIFY, true, 1.0, true, 6.0);
	g_cvWFP_Time = CreateConVar("bowling_wfp_time", "120", "Sets the maximum waiting for players time.", FCVAR_NOTIFY, true, 10.0, true, 600.0);
	g_cvRoll_Time = CreateConVar("bowling_roll_time", "10", "Sets the maximum time allowed for players to roll their ball. Prevents a troll delaying.", FCVAR_NOTIFY, true, 5.0, true, 60.0);
	g_cvGib = FindConVar("tf_playergib");
	
	HookConVarChange(g_cvMaxPlayers, h_cvMaxPlayers);
	HookConVarChange(g_cvWFP_Time, h_cvWFP_Time);
	HookConVarChange(g_cvRoll_Time, h_cvRoll_Time);
	
	g_iMaxPlayers = GetConVarInt(g_cvMaxPlayers);
	g_iWaitingForPlayers = GetConVarInt(g_cvWFP_Time);
	g_iRollTime = GetConVarInt(g_cvRoll_Time);
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	
	HookEvent("player_death", Event_PlayerDeathPost, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	
	AddNormalSoundHook(NormalSoundHook);
	
	g_hHud_Party1 = CreateHudSynchronizer(); g_hHud_Party2 = CreateHudSynchronizer(); g_hHud_Score = CreateHudSynchronizer(); g_hHud_Frame = CreateHudSynchronizer(); g_hHud_Notifications = CreateHudSynchronizer();
}

public void OnPluginEnd()
{
	UnhookEvent("player_spawn", Event_PlayerSpawn);
	
	UnhookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	
	UnhookEvent("player_death", Event_PlayerDeathPost, EventHookMode_Post);
	UnhookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	
	for (int i = 1; i <= MaxClients; i++)
		OnClientDisconnect(i);
}

public void h_cvMaxPlayers(Handle convar, const char[] oldVal, const char[] newVal) {
	g_iMaxPlayers = StringToInt(newVal);
}

public void h_cvWFP_Time(Handle convar, const char[] oldVal, const char[] newVal) {
	g_iWaitingForPlayers = StringToInt(newVal);
}

public void h_cvRoll_Time(Handle convar, const char[] oldVal, const char[] newVal) {
	g_iRollTime = StringToInt(newVal);
}

public void OnMapStart()
{
	char mapname[128];
	GetCurrentMap(mapname, sizeof(mapname));
	if (StrContains(mapname, "bowl_", false) == -1 && StrContains(mapname, "bowling_", false) == -1)
	{
		#if defined _bSteamTools_included
		if (bSteamTools)
		{
			Steam_SetGameDescription("Team Fortress");
		}
		#endif
		
		RemoveServerTag("bowling");
		SetFailState("The map is not compatible with bowling. Unloading plugin..");
	}
	
	else
	{
		#if defined _bSteamTools_included
		if (bSteamTools)
		{
			char sFormat[64];
			Format(sFormat, sizeof(sFormat), "Bowling Mod (%s)", PLUGIN_VERSION);
			Steam_SetGameDescription(sFormat);
		}
		#endif
		AddServerTag("bowling");
	}
	
	SetConVarInt(g_cvGib, 0, true, false);
	
	ConnectPins();
	PrecacheServer();
	
	g_iAlpha = 255;
	g_iAlpha_Add = false;
	
	CreateTimer(1.0, Timer_Info, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.9, Timer_ChangeAlpha, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int iClient)
{
	if (g_iParty[iClient] != 0) {
		g_iParty[iClient] = 0;
	}
	
	if (IsValidClient(iClient)) {
		if (IsFakeClient(iClient)) {
			ChangeClientTeam(iClient, 1);
		}
	}
}

public void OnClientDisconnect(int iClient)
{
	if (g_iParty[iClient] != 0)
	{
		if (g_iParty[iClient] == 1)
		{
			g_iPlayers_Party1--;
			PrintToChat_LeftLane(iClient, 1);
			UpdateLane(1);
		}
		
		else if (g_iParty[iClient] == 2)
		{
			g_iPlayers_Party2--;
			PrintToChat_LeftLane(iClient, 2);
			UpdateLane(2);
		}
		
		g_iParty[iClient] = 0;
	}
	
	g_iScore[iClient] = 0;
	g_iReady[iClient] = 0;
	
	g_bRolled[iClient] = false;
	
	if (iClient == g_iCurrentPlayer_Party1 || iClient == g_iCurrentPlayer_Party2)
		RemovePlayer(iClient);
}

void UpdateLane(int lane)
{
	if (lane == 1)
	{
		if (g_iPlayers_Party1 == 0)
		{
			g_bMatch_Party1 = false;
			
			g_iFrame_Lane1 = 0;
			g_iReady_Party1 = 0;
			g_iRemaining_Party1 = 0;
			
			g_bPlayerSelected_Lane1 = false;
			
			PrintToChatAll("\x07ADFF2FThe session on Lane 1 has just ended. The lane is now open.");
		}
	}
	
	if (lane == 2)
	{
		if (g_iPlayers_Party2 == 0)
		{
			g_bMatch_Party2 = false;
			
			g_iFrame_Lane2 = 0;
			g_iReady_Party2 = 0;
			g_iRemaining_Party2 = 0;
			
			g_bPlayerSelected_Lane2 = false;
			
			PrintToChatAll("\x07ADFF2FThe session on Lane 2 has just ended. The lane is now open.");
		}
	}
}

public Action Event_PlayerSpawn(Handle hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if (!IsFakeClient(iClient) && GetClientTeam(iClient) == view_as<int>(TFTeam_Red)) {
		ChangeClientTeam(iClient, view_as<int>(TFTeam_Blue));
	}
	
	else if (IsFakeClient(iClient) && GetClientTeam(iClient) == view_as<int>(TFTeam_Blue)) {
		ChangeClientTeam(iClient, view_as<int>(TFTeam_Red));
	}
	
	if (IsFakeClient(iClient))
	{
		TF2_AddCondition(iClient, TFCond_MegaHeal, 9999.9);		
		SetEntityRenderMode(iClient, RENDER_TRANSCOLOR);
	}
}

public Action Event_PlayerTeam(Handle hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent,"userid"));

	if (!IsFakeClient(iClient)) {
		OnClientDisconnect(iClient);
	}
}
	
public Action Event_PlayerDeathPost(Handle hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
	
	if (IsFakeClient(iClient))
	{
		if (g_iParty[attacker] != 0)
		{
			g_iScore[attacker]++;
			
			EmitSoundToAll("3250320dcaf3b60f1417b7b37986c4a3/9c44fc81ae1c3b4b362d5576bf6cda53/hit.wav", iClient);
			
			ChangeClientTeam(iClient, 1);
			
			switch (g_iParty[attacker]) {
				case 1:
				{
					if (CheckPins(1)) {
						if (GetEntProp(GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 1)
						{
							PrintToChatAll("\x075885A2%N \x07FFFFFFscored a \x07CF6A32STRIKE\x07FFFFFF!", attacker);
							ShowSyncHudText_Notification(attacker, "S T R I K E", "strike");
						}
						
						else if (GetEntProp(GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 0)
						{
							PrintToChatAll("\x075885A2%N \x07FFFFFFscored a \x07FFD700SPARE\x07FFFFFF!", attacker);
							ShowSyncHudText_Notification(attacker, "S P A R E", "spare");
						}
						
						RemovePlayer(attacker);
					}
				}
				
				case 2:
				{
					if (CheckPins(2)) {
						if (GetEntProp(GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 1)
						{
							PrintToChatAll("\x075885A2%N \x07FFFFFFscored a \x07CF6A32STRIKE\x07FFFFFF!", attacker);
							ShowSyncHudText_Notification(attacker, "S T R I K E", "strike");
						}
						
						else if (GetEntProp(GetEntPropEnt(attacker, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 0)
						{
							PrintToChatAll("\x075885A2%N \x07FFFFFFscored a \x07FFD700SPARE\x07FFFFFF!", attacker);
							ShowSyncHudText_Notification(attacker, "S P A R E", "spare");
						}
						
						RemovePlayer(attacker);
					}
				}
			}
		}
	}

	else
	{
		CreateTimer(0.1, Respawn, iClient, TIMER_FLAG_NO_MAPCHANGE);
		
		if (iClient == g_iCurrentPlayer_Party1 || iClient == g_iCurrentPlayer_Party2)
			RemovePlayer(iClient);
	}
}

public Action Event_PlayerDeathPre(Handle hEvent, const char[] sEventName, bool bDontBroadcast)
{
	SetEventBroadcast(hEvent, true);
	return Plugin_Continue;
}

public Action NormalSoundHook(int clients[64], int &numClients, char sSound[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags)
{
	if (StrContains(sSound, "loose_cannon_shoot", false) != -1)
	{
		if (g_iParty[entity] == 1 || g_iParty[entity] == 2)
		{
			sSound = "3250320dcaf3b60f1417b7b37986c4a3/9c44fc81ae1c3b4b362d5576bf6cda53/roll.wav";
			return Plugin_Changed;
		}
	}
	
	if (StrContains(sSound, "pain", false) != -1) return Plugin_Stop;
	
	return Plugin_Continue;
}

public Action Respawn(Handle hTimer, int iClient)
{
	TF2_RespawnPlayer(iClient);
}

public Action Command_GetPos(int iClient, int iArgs)
{
	float flEye[3], flPos[3];
	int iTarget;
	
	if (iArgs)
	{
		char sTarget[64];
		GetCmdArgString(sTarget, sizeof(sTarget));
		
		iTarget = FindTargetByName(sTarget);
		
		if (iTarget == 0)
			return Plugin_Handled;
	}
	
	else {
		iTarget = iClient;
	}
	
	GetClientEyePosition(iTarget, flEye);
	GetClientAbsOrigin(iTarget, flPos);
	
	PrintToChat(iClient, "%f %f %f %f %f %f", flPos[0], flPos[1], flPos[2], flEye[0], flEye[1], flEye[2]);
	
	return Plugin_Handled;
}

public Action Command_Teleport(int iClient, int iArgs)
{
	if (iArgs < 1)
	{
		PrintToChat(iClient, "\x07FFFFFFUsage: sm_teleport <name>");

		return Plugin_Handled;
	}

	int iMaxPlayers, iPlayer;
	char sPlayerName[32]; char sName[32];
	float flTeleportOrigin[3];
	float flPlayerOrigin[3];

	iPlayer = -1;
	GetCmdArg(1, sPlayerName, sizeof(sPlayerName));

	iMaxPlayers = GetMaxClients();
	for (int i = 1; i <= iMaxPlayers; i++)
	{
		if (!IsClientConnected(i)) continue;

		GetClientName(i, sName, sizeof(sName));

		if (StrContains(sName, sPlayerName, false) != -1) iPlayer = i;
	}

	if (iPlayer == -1)
	{
		PrintToChat(iClient, "\x07FFFFFFNo matching iClient was found.");

		return Plugin_Handled;
	}

	GetClientName(iPlayer, sName, sizeof(sName));
	
	flTeleportOrigin[0] = flPlayerOrigin[0];
	flTeleportOrigin[1] = flPlayerOrigin[1];
	flTeleportOrigin[2] = (flPlayerOrigin[2] + 4);

	TeleportEntity(iPlayer, flTeleportOrigin, NULL_VECTOR, NULL_VECTOR);

	return Plugin_Handled;
}

public Action Timer_Info(Handle hTimer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iParty[i] == 0 && IsClientConnected(i))
		{
			char sFormat[1000];
			
			Format(sFormat, sizeof(sFormat), "Lane 1 - %i/%i %s\n \nLane 2 - %i/%i %s", g_iPlayers_Party1, g_iMaxPlayers, (g_bMatch_Party1 == true ? "(Locked)" : "(Open)"), g_iPlayers_Party2, g_iMaxPlayers, (g_bMatch_Party2 == true ? "(Locked)" : "(Open)"));
			
			Handle hBuffer = StartMessageOne("KeyHintText", i);
			BfWriteByte(hBuffer, 1);
			BfWriteString(hBuffer, sFormat);
			EndMessage();
		}
	}
}

public Action Timer_ChangeAlpha(Handle hTimer)
{
	if (g_iAlpha_Add) {
		g_iAlpha_Add = false;
	}
	
	else {
		g_iAlpha_Add = true;
	}
}

public Action Command_Help(int iClient, int iArgs)
{
	Handle hMenu = CreateMenu(hHelp, MenuAction_Select | MenuAction_Cancel | MenuAction_End);
	
	AddMenuItem(hMenu, "", "Strike\nWhen all 10 pins are knocked down with one ball.\n \n");
	AddMenuItem(hMenu, "", "Spare\nAll 10 pins are knocked down with 2 consecutive balls.\n \n");
	AddMenuItem(hMenu, "", "Game\nA game consists of 10 frames per person.\n \n");
	AddMenuItem(hMenu, "", "Frame\nA frame consists of up to two deliveries. However the\n10th frame consists of up to 3 deliveries.\n \n");
	AddMenuItem(hMenu, "", "Double\nOccurs when 2 strikes in a row are bowled.\n \n");
	AddMenuItem(hMenu, "", "Turkey\nOccurs when 3 strikes in a row are bowled.");
	
	DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
	
	return Plugin_Handled;
}

public int hHelp(Handle menu, MenuAction action, int iClient, int button)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			Command_Help(iClient, 0);
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Action Command_SelectLane(int iClient, int iArgs)
{
	if (iArgs)
	{
		char sLane[64];
		GetCmdArgString(sLane, sizeof(sLane));
		
		if (StringToInt(sLane) == 1 || StringToInt(sLane) == 2)
			SelectLane(iClient, StringToInt(sLane));
		else
			PrintToChat(iClient, "\x07FF4040Invalid argument received. Only 1 or 2 is accepted.");
	}
	
	else
	{
		char sFormatLane1[60]; char sFormatLane2[60];
		
		Handle hPanel = CreatePanel();
		SetPanelTitle(hPanel, "Lane Selection\n \n");
		
		Format(sFormatLane1, sizeof(sFormatLane1), "Lane 1 (%i/%i)%s", g_iPlayers_Party1, g_iMaxPlayers, (g_bMatch_Party1 == true ? " [Locked]" : " [Open]"));
		
		Format(sFormatLane2, sizeof(sFormatLane2), "Lane 2 (%i/%i)%s", g_iPlayers_Party2, g_iMaxPlayers, (g_bMatch_Party2 == true ? " [Locked]" : " [Open]"));

		if (g_iPlayers_Party1 < 6) {
			DrawPanelItem(hPanel, sFormatLane1);
		}
		else {
			DrawPanelItem(hPanel, sFormatLane1, ITEMDRAW_DISABLED);
		}
		
		if (g_iPlayers_Party2 < 6) {
			DrawPanelItem(hPanel, sFormatLane2);
		}
		else {
			DrawPanelItem(hPanel, sFormatLane2, ITEMDRAW_DISABLED);
		}
		
		DrawPanelText(hPanel, " ");
		
		for (int i = 0; i <= 6; i++) {
			DrawPanelItem(hPanel, " ", ITEMDRAW_NOTEXT);
		}
		
		DrawPanelItem(hPanel, "Close", ITEMDRAW_CONTROL);
		
		SendPanelToClient(hPanel, iClient, hLaneSelect, MENU_TIME_FOREVER);
	}
	
	return Plugin_Handled;
}

public int hLaneSelect(Handle menu, MenuAction action, int iClient, int button)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			switch (button)
			{
				case 1:
				{
					SelectLane(iClient, 1);
				}

				case 2:
				{
					SelectLane(iClient, 2);
				}

				case 10:
				{
					CloseHandle(menu);
				}
			}
		}

		case MenuAction_End:
		{
			CloseHandle(menu);
		}
	}
}

public Action Timer_WaitingForPlayers_Party1(Handle hTimer)
{
	if (g_iRemaining_Party1 == 0 || g_iReady_Party1 == g_iPlayers_Party1 || g_iPlayers_Party1 == g_iMaxPlayers)
    {
		if (g_iPlayers_Party1 >= 1)
		{
			g_iRemaining_Party1 = 10;
			CreateTimer(1.0, Timer_Countdown_Party1, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			
			if (g_iRemaining_Party1 == 0 || g_iPlayers_Party1 == g_iMaxPlayers)
				PrintToChat_LaneAnnounce(1, "\x07FFFFFFThe match will begin in 10 seconds..");
			else if (g_iReady_Party1 == g_iPlayers_Party1)
				PrintToChat_LaneAnnounce(1, "{titangrey}Everyone in the lane is ready. The match will begin in 10 seconds..");
				
			if (g_iPlayers_Party1 != g_iMaxPlayers)
				PrintToChatAll("\x07FF4040A match is about to start at Lane 1 in 10 seconds.. (%i/%i)", g_iPlayers_Party1, g_iMaxPlayers);
		}
		
		return Plugin_Stop;
    }
	
	g_iRemaining_Party1--;
	SetHudTextParams(-1.0, 0.15, 1.0, 255, 255, 255, 255);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == 1)
			{
				ShowSyncHudText(i, g_hHud_Party1, "\n \nLane 1\n \nWaiting for players.. (%i)\n \n \n \n \n \nThe match will start automatically when there are %i players.", g_iRemaining_Party1, g_iMaxPlayers);
				
				char sFormat[1000];
				for (int j = 1; j <= MaxClients; j++)
				{
					if (IsClientInGame(j))
					{
						if (!IsFakeClient(j) && g_iParty[j] == 1)
						{
							if (g_iReady[j])
								Format(sFormat, sizeof(sFormat), "%s%N ✔\n", sFormat, j);
							else
								Format(sFormat, sizeof(sFormat), "%s%N\n", sFormat, j);
						}
					}
				}
				
				Format(sFormat, sizeof(sFormat), "%s\n \n!r - Ready\n \n!leave - Leave", sFormat);
				
				Handle hBuffer = StartMessageOne("KeyHintText", i);
				BfWriteByte(hBuffer, 1);
				BfWriteString(hBuffer, sFormat);
				EndMessage();
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_WaitingForPlayers_Party2(Handle hTimer)
{
	if (g_iRemaining_Party2 == 0 || g_iReady_Party2 == g_iPlayers_Party2 || g_iPlayers_Party2 == g_iMaxPlayers)
    {
		if (g_iPlayers_Party2 >= 1)
		{
			g_iRemaining_Party2 = 10;
			CreateTimer(1.0, Timer_Countdown_Party2, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			
			if (g_iRemaining_Party2 == 0 || g_iPlayers_Party1 == g_iMaxPlayers)
				PrintToChat_LaneAnnounce(2, "\x07FFFFFFThe match will begin in 10 seconds..");
			else if (g_iReady_Party2 == g_iPlayers_Party2)
				PrintToChat_LaneAnnounce(2, "{titangrey}Everyone in the lane is ready. The match will begin in 10 seconds..");
				
			if (g_iPlayers_Party2 != g_iMaxPlayers)
				PrintToChatAll("\x07FF4040A match is about to start at Lane 2 in 10 seconds.. (%i/%i)", g_iPlayers_Party2, g_iMaxPlayers);
		}
		
		return Plugin_Stop; 
    }
	
	g_iRemaining_Party2--;
	SetHudTextParams(-1.0, 0.15, 1.0, 255, 255, 255, 255);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == 2)
			{
				ShowSyncHudText(i, g_hHud_Party2, "\n \nLane 2\n \nWaiting for players.. (%i)\n \n \n \n \n \nThe match will start automatically when there are %i players.", g_iRemaining_Party2, g_iMaxPlayers);
				
				char sFormat[1000];
				for (int j = 1; j <= MaxClients; j++)
				{
					if (IsClientInGame(j))
					{
						if (!IsFakeClient(j) && g_iParty[j] == 2)
						{
							if (g_iReady[j])
								Format(sFormat, sizeof(sFormat), "%s%N ✔\n", sFormat, j);
							else
								Format(sFormat, sizeof(sFormat), "%s%N\n", sFormat, j);
						}
					}
				}
				
				Format(sFormat, sizeof(sFormat), "%s\n \n!r - Ready\n \n!leave - Leave", sFormat);
				
				Handle hBuffer = StartMessageOne("KeyHintText", i);
				BfWriteByte(hBuffer, 1);
				BfWriteString(hBuffer, sFormat);
				EndMessage();
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_Countdown_Party1(Handle hTimer)
{
	if (g_iRemaining_Party1 == 0)
    {
		CreateTimer(1.0, Timer_Hud_Party1, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		g_bMatch_Party1 = true;
		
		g_iFrame_Lane1 = 1;
		TeleportPins(1);
		
		g_bPlayerSelected_Lane1 = false;
		
		return Plugin_Stop;
    }
	
	g_iRemaining_Party1--;
	SetHudTextParams(-1.0, 0.19, 1.0, 255, 255, 255, 255);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == 1)
			{
				ShowSyncHudText(i, g_hHud_Party1, "%i", g_iRemaining_Party1);
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_Countdown_Party2(Handle hTimer)
{
	if (g_iRemaining_Party2 == 0)
    {
		CreateTimer(1.0, Timer_Hud_Party2, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		g_bMatch_Party2 = true;
		
		g_iFrame_Lane2 = 1;
		TeleportPins(2);
		
		return Plugin_Stop;
    }
	
	g_iRemaining_Party2--;
	SetHudTextParams(-1.0, 0.19, 1.0, 255, 255, 255, 255);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == 2)
			{
				ShowSyncHudText(i, g_hHud_Party2, "%i", g_iRemaining_Party2);
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Timer_Hud_Party1(Handle hTimer)
{
	if (!g_bMatch_Party1) {
		return Plugin_Stop;
	}
	
	ShowScores(1);
	return Plugin_Continue;
}

public Action Timer_Hud_Party2(Handle hTimer)
{
	if (!g_bMatch_Party2) {
		return Plugin_Stop;
	}
	
	ShowScores(2);
	return Plugin_Continue;
}

public Action Timer_PlayCountdown(Handle hTimer, int iClient)
{
	switch (g_iParty[iClient])
	{
		case 1:
		{
			char sWeapon[50];
			
			GetClientWeapon(iClient, sWeapon, sizeof(sWeapon));
			
			if (iClient != g_iCurrentPlayer_Party1) {
				return Plugin_Stop;
			}
			
			else if (g_iRemaining_Party1 == 0 || (GetEntProp(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 0) || CheckPins(1))  {
				RemovePlayer(iClient);
				return Plugin_Stop;
			}
			
			else {
				g_iRemaining_Party1--;
			}
		}
		
		case 2:
		{
			char sWeapon[50];
			
			GetClientWeapon(iClient, sWeapon, sizeof(sWeapon));
			
			if (iClient != g_iCurrentPlayer_Party2) {
				return Plugin_Stop;
			}
			
			else if (g_iRemaining_Party2 == 0 || (GetEntProp(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 0) || CheckPins(2))  {
				RemovePlayer(iClient);
				return Plugin_Stop;
			}

			else {
				g_iRemaining_Party2--;
			}
		}
	}
	
	return Plugin_Continue;
}

public Action Command_Ready(int iClient, int iArgs)
{
	if (g_iParty[iClient] != 0)
	{
		if (g_iParty[iClient] == 1 && !g_bMatch_Party1 || g_iParty[iClient] == 2 && !g_bMatch_Party2)
		{
			if (g_iReady[iClient] == 0)
			{
				g_iReady[iClient] = 1;
				if (g_iParty[iClient] == 1) {
					g_iReady_Party1++;
				}
				else {
					g_iReady_Party2++;
				}
				PrintToChat(iClient, "\x07FFFFFFYou are now ready.");
			}
			
			else if (g_iReady[iClient] == 1)
			{
				g_iReady[iClient] = 0;
				if (g_iParty[iClient] == 1) {
					g_iReady_Party1--;
				}
				else {
					g_iReady_Party2--;
				}
				PrintToChat(iClient, "\x07FFFFFFYou are no longer ready.");
			}
		}
		
		else
		{
			PrintToChat(iClient, "\x07FFFFFFThe match has already started.");
		}
	}
	
	else
	{
		PrintToChat(iClient, "\x07FFFFFFPlease join a bowling lane first.");
	}
}

public Action Command_Leave(int iClient, int iArgs)
{
	if (g_iParty[iClient] != 0)
	{
		if (g_iParty[iClient] == 1)
		{
			g_iReady_Party1--; g_iPlayers_Party1--;
			
			PrintToChat(iClient, "\x07FFFFFFYou left Lane 1.");
			PrintToChat_LeftLane(iClient, 1);
			
			UpdateLane(1);
			
			if (iClient == g_iCurrentPlayer_Party1)
				RemovePlayer(iClient);
		}
		
		else
		{
			g_iReady_Party2--; g_iPlayers_Party2--;
			
			PrintToChat(iClient, "\x07FFFFFFYou left Lane 2.");
			PrintToChat_LeftLane(iClient, 2);
			
			UpdateLane(2);
			
			if (iClient == g_iCurrentPlayer_Party2)
				RemovePlayer(iClient);
		}
		
		g_iReady[iClient] = 0; g_iParty[iClient] = 0; g_iScore[iClient] = 0;
	}
	
	else
	{
		PrintToChat(iClient, "\x07FFFFFFYou are not in any lanes.");
	}
}

public void OnGameFrame()
{
	if (!g_bPlayerSelected_Lane1 && g_bMatch_Party1)
	{
		if (g_iFrame_Lane1 + 1 != 12) {
			SelectPlayer(1, g_iFrame_Lane1);
		}
		
		else {
			g_bPlayerSelected_Lane1 = true;
			EndSession(1);
		}
	}
	
	else if (!g_bPlayerSelected_Lane2 && g_bMatch_Party2)
	{
		if (g_iFrame_Lane2 + 1 != 12) {
			SelectPlayer(2, g_iFrame_Lane2);
		}
		
		else {
			g_bPlayerSelected_Lane2 = true;
			EndSession(2);
		}
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1) {
				SetEntProp(i, Prop_Send, "m_nStreaks", g_iScore[i], _, 0);
			}
			
			else if (IsFakeClient(i) && !g_bMatch_Party1 && !g_bMatch_Party2 && GetClientTeam(i) != 1) {
				ChangeClientTeam(i, 1);
			}
		}
	}
	
	if (g_iAlpha_Add) {
		g_iAlpha++;
	}
	
	else {
		g_iAlpha--;
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (IsFakeClient(i) && GetClientTeam(i) == view_as<int>(TFTeam_Red))
				SetEntityRenderColor(i, 255, 255, 255, g_iAlpha);
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
 	if (strcmp(classname, "tf_ammo_pack") == 0 || strcmp(classname, "tf_dropped_weapon") == 0)
		SDKHook(entity, SDKHook_Spawn, Hook_OnEntityCreated);
}

public Action Hook_OnEntityCreated(int entity) {
	AcceptEntityInput(entity, "Kill");
}

void RemovePlayer(int iClient)
{
	switch (g_iParty[iClient]) {
		case 1: g_bPlayerSelected_Lane1 = false, g_iCurrentPlayer_Party1 = 0;
		case 2: g_bPlayerSelected_Lane2 = false, g_iCurrentPlayer_Party2 = 0;
	}
	
	CreateTimer(1.7, TeleportOutside, iClient, TIMER_FLAG_NO_MAPCHANGE);
	TF2_RemoveCondition(iClient, TFCond_HalloweenCritCandy);
}

void SelectLane(int iClient, int lane)
{
	switch (lane)
	{
		case 1:
		{
			if (g_iPlayers_Party1 < g_iMaxPlayers)
			{
				if (g_iParty[iClient] == 1) {
					PrintToChat(iClient, "\x07FFFFFFYou are already in Lane 1.");
				}
				
				else
				{
					if (!g_bMatch_Party1)
					{
						if (g_iParty[iClient] == 2)
						{
							g_iPlayers_Party2--;
							UpdateLane(2);
							
							if (iClient == g_iCurrentPlayer_Party2)
								RemovePlayer(iClient);
						}
					
						if (g_iPlayers_Party1 == 0)
						{
							g_iRemaining_Party1 = g_iWaitingForPlayers;
							CreateTimer(1.0, Timer_WaitingForPlayers_Party1, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
						}
						
						g_iParty[iClient] = 1;
						
						g_iPlayers_Party1++;
						
						PrintToChat(iClient, "\x07FFFFFFYou joined Lane 1.");
						
						PrintToChat_JoinLane(iClient, 1);
					}
					
					else
					{
						PrintToChat(iClient, "\x07FF4040This match is in progress. Please join another lane or wait for the next session.");
						
						Command_SelectLane(iClient, 0);
					}
				}
			}
			
			else
			{
				PrintToChat(iClient, "\x07FFFFFFLane 1 is full.");

				Command_SelectLane(iClient, 0);
			}
		}

		case 2:
		{
			if (g_iPlayers_Party2 < g_iMaxPlayers)
			{
				if (g_iParty[iClient] == 2) {
					PrintToChat(iClient, "\x07FFFFFFYou are already in Lane 2.");
				}
				
				else
				{
					if (!g_bMatch_Party2)
					{
						if (g_iParty[iClient] == 1)
						{
							g_iPlayers_Party1--;
							UpdateLane(1);
							
							if (iClient == g_iCurrentPlayer_Party1)
								RemovePlayer(iClient);
						}
					
						if (g_iPlayers_Party2 == 0)
						{
							g_iRemaining_Party2 = g_iWaitingForPlayers;
							CreateTimer(1.0, Timer_WaitingForPlayers_Party2, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
						}
						
						g_iParty[iClient] = 2;
						
						g_iPlayers_Party2++;
						
						PrintToChat(iClient, "\x07FFFFFFYou joined Lane 2.");
						
						PrintToChat_JoinLane(iClient, 2);
					}
					
					else
					{
						PrintToChat(iClient, "\x07FF4040This match is in progress. Please join another lane or wait for the next session.");
						
						Command_SelectLane(iClient, 0);
					}
				}
			}
			
			else
			{
				PrintToChat(iClient, "\x07FFFFFFLane 2 is full.");
				
				Command_SelectLane(iClient, 0);
			}
		}
	}
}

void PrintToChat_JoinLane(int iClient, int lane)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == lane)
			{
				PrintToChat(i, "\x075885A2%N \x07FFFFFFhas joined Lane %i.", iClient, lane);
			}	
		}
	}
}

void PrintToChat_LeftLane(int iClient, int lane)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == lane)
			{
				PrintToChat(i, "\x075885A2%N \x07FFFFFFhas left the lane.", iClient);
			}	
		}
	}
}

void PrintToChat_LaneAnnounce(int lane, const char[] text)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == lane)
			{
				PrintToChat(i, "%s", text);
			}	
		}
	}
}

void ShowSyncHudText_Notification(int iClient, const char[] clientText, const char[] allText)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			switch (g_iParty[iClient])
			{
				case 1:
				{
					if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && i != g_iCurrentPlayer_Party1)
					{
						SetHudTextParamsEx(-1.0, 0.15, 5.0, {255,255,255,255}, {0,0,0,0}, 2, 0.1, 0.1, 0.1);
						ShowSyncHudText(i, g_hHud_Notifications, "%N scored a %s!", iClient, allText);
					}
					
					else if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && i == g_iCurrentPlayer_Party1)
					{
						SetHudTextParamsEx(-1.0, 0.15, 5.0, {255,255,255,255}, {0,0,0,0}, 2, 0.1, 0.1, 0.1);
						ShowSyncHudText(i, g_hHud_Notifications, clientText);
					}
				}
				
				case 2:
				{
					if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && i != g_iCurrentPlayer_Party2)
					{
						SetHudTextParamsEx(-1.0, 0.15, 5.0, {255,255,255,255}, {0,0,0,0}, 2, 0.1, 0.1, 0.1);
						ShowSyncHudText(i, g_hHud_Notifications, "%N scored a %s!", iClient, allText);
					}
					
					else if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && i == g_iCurrentPlayer_Party2)
					{
						SetHudTextParamsEx(-1.0, 0.15, 5.0, {255,255,255,255}, {0,0,0,0}, 2, 0.1, 0.1, 0.1);
						ShowSyncHudText(i, g_hHud_Notifications, clientText);
					}
				}
			}
		}
	}
}

void ShowScores(int lane)
{
	char sFormatScores[1000];
	
	switch (lane)
	{
		case 1:
		{
			Format(sFormatScores, sizeof(sFormatScores), "Lane 1\n \n");
			
			if (g_iRemaining_Party1 >= 1)
			{
				Format(sFormatScores, sizeof(sFormatScores), "%s%N (%02d:%02d)\n \n", sFormatScores, g_iCurrentPlayer_Party1, g_iRemaining_Party1 / 60, g_iRemaining_Party1 % 60);
			}
			
			else {
				Format(sFormatScores, sizeof(sFormatScores), "%s \n \n", sFormatScores);
			}
			
			Format(sFormatScores, sizeof(sFormatScores), "%sFrame %i/10\n", sFormatScores, g_iFrame_Lane1);
			
			for (int i = 0; i < g_iFrame_Lane1; i++) {
				StrCat(sFormatScores, sizeof(sFormatScores), "▬");
			}
			
			for (int i = 0; i < 10-g_iFrame_Lane1; i++) {
				StrCat(sFormatScores, sizeof(sFormatScores), " ");
			}
			
			Format(sFormatScores, sizeof(sFormatScores), "%s\n \n", sFormatScores);
		}
		
		case 2:
		{
			Format(sFormatScores, sizeof(sFormatScores), "Lane 2\n \n");
			
			if (g_iRemaining_Party2 >= 1)
			{
				Format(sFormatScores, sizeof(sFormatScores), "%s%N (%02d:%02d)\n \n", sFormatScores, g_iCurrentPlayer_Party2, g_iRemaining_Party2 / 60, g_iRemaining_Party2 % 60);
			}
			
			else {
				Format(sFormatScores, sizeof(sFormatScores), "%s \n \n", sFormatScores);
			}
			
			Format(sFormatScores, sizeof(sFormatScores), "%sFrame %i/10\n", sFormatScores, g_iFrame_Lane2);
			
			for (int i = 0; i < g_iFrame_Lane2; i++) {
				StrCat(sFormatScores, sizeof(sFormatScores), "▬");
			}
			
			for (int i = 0; i < 10-g_iFrame_Lane2; i++) {
				StrCat(sFormatScores, sizeof(sFormatScores), " ");
			}
			
			Format(sFormatScores, sizeof(sFormatScores), "%s\n \n", sFormatScores);
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == lane)
			{
				Format(sFormatScores, sizeof(sFormatScores), "%s%N - %i\n", sFormatScores, i, g_iScore[i]);
			}
		}
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == lane)
			{
				Handle hBuffer = StartMessageOne("KeyHintText", i);
				BfWriteByte(hBuffer, 1);
				BfWriteString(hBuffer, sFormatScores);
				EndMessage();
				
				SetHudTextParams(0.02, 0.02, 1.0, 255, 255, 255, 255);
				ShowSyncHudText(i, g_hHud_Score, "Score: %i", g_iScore[i]);
			}
		}
	}
}

stock bool SelectPlayer(int lane, int frame)
{
	if (frame == 1) {
		for (int i = 1; i <= MaxClients; i++)
			g_iReady[i] = 0;
	}
	
	bool bChosen = false
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == lane && !g_bRolled[i])
			{
				switch (lane)
				{
					case 1: g_bPlayerSelected_Lane1 = true;
					case 2: g_bPlayerSelected_Lane2 = true;
				}
				
				bChosen = true;
				g_bRolled[i] = true;
		
				CreateTimer(3.0, Timer_TeleportPlayer, i, TIMER_FLAG_NO_MAPCHANGE);
				
				break;
			}
		}
	}
	
	// no players was chosen = all players have played this frame
	if (!bChosen)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (g_iParty[i] == lane)
				g_bRolled[i] = false;
		}

		switch (lane)
		{
			case 1: g_bPlayerSelected_Lane1 = false, g_iFrame_Lane1++;
			case 2: g_bPlayerSelected_Lane2 = false, g_iFrame_Lane2++;
		}
	}
	
	else
	{
		switch (lane)
		{
			case 1: g_bPlayerSelected_Lane1 = true;
			case 2: g_bPlayerSelected_Lane2 = true;
		}
	}
}

public Action Timer_TeleportPlayer(Handle hTimer, int iClient)
{
	StripWeapons(iClient);
	
	switch (g_iParty[iClient])
	{
		case 1: g_iCurrentPlayer_Party1 = iClient, TeleportToLane(iClient, 1), TeleportPins(1), GiveLooseCannon(iClient, g_iFrame_Lane1);
		case 2: g_iCurrentPlayer_Party2 = iClient, TeleportToLane(iClient, 2), TeleportPins(2), GiveLooseCannon(iClient, g_iFrame_Lane2);
	}
}

void GiveLooseCannon(int iClient, int frame)
{
	if (IsClientInGame(iClient) && IsPlayerAlive(iClient))
	{
		TF2Items_GiveWeapon(iClient, 996);
		TF2_AddCondition(iClient, TFCond_HalloweenCritCandy, 9999.9);

		int weapon = GetPlayerWeaponSlot(iClient, 0);
		if (IsValidEntity(weapon))
		{
			SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 0);
			
			if (frame == 10)
			{
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				SetEntData(weapon, iAmmoTable, 3, 4, true);
			}
			
			else
			{
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				SetEntData(weapon, iAmmoTable, 2, 4, true);
			}
			
			int iOffset = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
			int iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(iClient, iAmmoTable+iOffset, 0, 4, true);
		}
	}
}

void TeleportToLane(int iClient, int lane)
{
	float flPos[3];
	
	if (lane == 1)
	{
		flPos[0] = 65.201431;
		flPos[1] = 1791.190551;
		flPos[2] = 2.031250;
	}
	
	else
	{
		flPos[0] = -633.743835;
		flPos[1] = 1792.109252;
		flPos[2] = 2.031250;
	}
	
	if (!IsPlayerAlive(iClient)) {
		TF2_RespawnPlayer(iClient);
	}
	
	TeleportEntity(iClient, flPos, NULL_VECTOR, NULL_VECTOR);
	
	if (!IsFlagSet(iClient, HIDEHUD_HEALTH))
	{
		int HideHUD = GetEntProp(iClient, Prop_Send, "m_iHideHUD");
		HideHUD ^= HIDEHUD_HEALTH;
		SetEntProp(iClient, Prop_Send, "m_iHideHUD", HideHUD);
	}
	
	SetHudTextParams(-1.0, 0.03, 5.0, 255, 255, 255, 255);
	
	if (lane == 1)
	{
		ShowSyncHudText(iClient, g_hHud_Frame, "- Frame %i -", g_iFrame_Lane1);
		g_iRemaining_Party1 = g_iRollTime;
		CreateTimer(1.0, Timer_PlayCountdown, iClient, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
	
	else
	{
		ShowSyncHudText(iClient, g_hHud_Frame, "- Frame %i -", g_iFrame_Lane2);
		g_iRemaining_Party2 = g_iRollTime;
		CreateTimer(1.0, Timer_PlayCountdown, iClient, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action TeleportOutside(Handle hTimer, int iClient)
{
	float flPos[3];
	
	if (g_iParty[iClient] == 1)
	{
		flPos[0] = 66.068328;
		flPos[1] = 1612.255249;
		flPos[2] = 0.031250;
	}
	
	else
	{
		flPos[0] = -638.619934;
		flPos[1] = 1612.123901;
		flPos[2] = 0.031250;
	}
	
	if (!IsPlayerAlive(iClient)) {
		TF2_RespawnPlayer(iClient);
	}
	
	TeleportEntity(iClient, flPos, NULL_VECTOR, NULL_VECTOR);
	TF2_RegeneratePlayer(iClient);
	
	SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 1);
	
	if (IsFlagSet(iClient, HIDEHUD_HEALTH))
	{
		int HideHUD = GetEntProp(iClient, Prop_Send, "m_iHideHUD");
		HideHUD ^= HIDEHUD_HEALTH;
		SetEntProp(iClient, Prop_Send, "m_iHideHUD", HideHUD);
	}
}

void RestoreDefaults(int lane)
{
	switch (lane)
	{
		case 1:
		{
			g_iRemaining_Party1 = 0;
			g_iPlayers_Party1 = 0;
			g_iReady_Party1 = 0;
			g_iFrame_Lane1 = 0;
			g_iCurrentPlayer_Party1 = 0;
			
			g_bPlayerSelected_Lane1 = false;
			g_bMatch_Party1 = false;
		}
		
		case 2:
		{
			g_iRemaining_Party2 = 0;
			g_iPlayers_Party2 = 0;
			g_iReady_Party2 = 0;
			g_iFrame_Lane2 = 0;
			g_iCurrentPlayer_Party2 = 0;
			
			g_bPlayerSelected_Lane2 = false;
			g_bMatch_Party2 = false;
		}
	}
}


void EndSession(int lane)
{
	switch (lane) {
		case 1: RestoreDefaults(1);
		case 2: RestoreDefaults(2);
	}
	
	int highestScore = 0;
	int highestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsClientInGame(z) && IsPlayerAlive(z) && g_iParty[z] == lane && g_iScore[z] > highestScore)
		{
			highestScore = g_iScore[z];
			highestScoreClient = z;
		}
	}
	
	int secondHighestScore = 0;
	int secondHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsClientInGame(z) && IsPlayerAlive(z) && g_iParty[z] == lane && g_iScore[z] > secondHighestScore && z != highestScoreClient)
		{
			secondHighestScore = g_iScore[z];
			secondHighestScoreClient = z;
		}
	}
	
	int thirdHighestScore = 0;
	int thirdHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsClientInGame(z) && IsPlayerAlive(z) && g_iParty[z] == lane && g_iScore[z] > thirdHighestScore && z != highestScoreClient && z != secondHighestScoreClient)
		{
			thirdHighestScore = g_iScore[z];
			thirdHighestScoreClient = z;
		}
	}
	
	int fourthHighestScore = 0;
	int fourthHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsClientInGame(z) && IsPlayerAlive(z) && g_iParty[z] == lane && g_iScore[z] > fourthHighestScore && z != highestScoreClient && z != secondHighestScoreClient && z != thirdHighestScoreClient)
		{
			fourthHighestScore = g_iScore[z];
			fourthHighestScoreClient = z;
		}
	}
	
	int fifthHighestScore = 0;
	int fifthHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsClientInGame(z) && IsPlayerAlive(z) && g_iParty[z] == lane && g_iScore[z] > fifthHighestScore && z != highestScoreClient && z != secondHighestScoreClient && z != thirdHighestScoreClient && z != fourthHighestScoreClient)
		{
			fifthHighestScore = g_iScore[z];
			fifthHighestScoreClient = z;
		}
	}
	
	int sixthHighestScore = 0;
	int sixthHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsClientInGame(z) && IsPlayerAlive(z) && g_iParty[z] == lane && g_iScore[z] > sixthHighestScore && z != highestScoreClient && z != secondHighestScoreClient && z != thirdHighestScoreClient && z != fourthHighestScoreClient && z != fifthHighestScoreClient)
		{
			sixthHighestScore = g_iScore[z];
			sixthHighestScoreClient = z;
		}
	}
	
	char sFormatHud[1000];
	char sFormatChat[1000];
	
	Format(sFormatChat, sizeof(sFormatChat), "\x07FFFFFFTop 3 Players:\n");
	
	if (highestScore != 0)
	{
		Format(sFormatHud, sizeof(sFormatHud), "%s\n#1] %N - %i", sFormatHud, highestScoreClient, g_iScore[highestScoreClient]);
		Format(sFormatChat, sizeof(sFormatChat), "%s\x07CF6A32%N \x07FFFFFF- %i", sFormatChat, highestScoreClient, g_iScore[highestScoreClient]);
	}
	
	if (secondHighestScore != 0)
	{
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#2] %N - %i", sFormatHud, secondHighestScoreClient, g_iScore[secondHighestScoreClient]);
		Format(sFormatChat, sizeof(sFormatChat), "%s\n\x07CF6A32%N \x07FFFFFF- %i", sFormatChat, secondHighestScoreClient, g_iScore[secondHighestScoreClient]);
	}
	
	else {
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#2] --- - -", sFormatHud);
	}
	
	if (thirdHighestScore != 0)
	{
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#3] %N - %i", sFormatHud, thirdHighestScoreClient, g_iScore[thirdHighestScoreClient]);
		Format(sFormatChat, sizeof(sFormatChat), "%s\n\x07CF6A32%N \x07FFFFFF- %i", sFormatChat, thirdHighestScoreClient, g_iScore[thirdHighestScoreClient]);
	}
	
	else {
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#3] --- - -", sFormatHud);
	}
	
	if (fourthHighestScore != 0)
	{
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#4] %N - %i", sFormatHud, fourthHighestScoreClient, g_iScore[fourthHighestScoreClient]);
	}
	
	else {
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#4] --- - -", sFormatHud);
	}
	
	if (fifthHighestScore != 0)
	{
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#5] %N - %i", sFormatHud, fifthHighestScoreClient, g_iScore[fifthHighestScoreClient]);
	}
	
	else {
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#5] --- - -", sFormatHud);
	}
	
	if (sixthHighestScore != 0)
	{
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#6] %N - %i", sFormatHud, sixthHighestScoreClient, g_iScore[sixthHighestScoreClient]);
	}
	
	else {
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#6] --- - -", sFormatHud);
	}
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsClientInGame(iClient) && g_iParty[iClient] == lane)
		{
			char clientid[32]; GetClientAuthId(iClient, AuthId_Steam3, clientid, sizeof(clientid));
			ServerCommand("sm_quest_bowling \"%s\"", clientid);
			
			SetHudTextParams(-1.0, 0.19, 15.0, 255, 255, 255, 255);
			ShowSyncHudText(iClient, g_hHud_Frame, sFormatHud);
			
			g_iParty[iClient] = 0;
			g_iReady[iClient] = 0;
			g_iScore[iClient] = 0;
			
			PrintToChat(iClient, "\x07FFFFFFYou left Lane %i.", lane);
		}
	}
	
	PrintToChatAll("\x07ADFF2FThe session on Lane %i has just ended. The lane is now open.\n%s", lane, sFormatChat);
}

void ConnectPins()
{	
	ServerCommand("sv_cheats 1; bot -team red -class medic -name Pin#1; bot -team red -class medic -name Pin#2; bot -team red -class medic -name Pin#3; bot -team red -class medic -name Pin#4; bot -team red -class medic -name Pin#5; bot -team red -class medic -name Pin#6;");
	ServerCommand("bot -team red -class medic -name Pin#7; bot -team red -class medic -name Pin#8; bot -team red -class medic -name Pin#9; bot -team red -class medic -name Pin#10");
	
	ServerCommand("bot -team red -class medic -name Pin#11; bot -team red -class medic -name Pin#12; bot -team red -class medic -name Pin#13; bot -team red -class medic -name Pin#14; bot -team red -class medic -name Pin#15; bot -team red -class medic -name Pin#16;");
	ServerCommand("bot -team red -class medic -name Pin#17; bot -team red -class medic -name Pin#18; bot -team red -class medic -name Pin#19; bot -team red -class medic -name Pin#20; sv_cheats 0");
}

void TeleportPins(int lane)
{
	switch (lane)
	{
		case 1:
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					if (GetClientTeam(i) == view_as<int>(TFTeam_Spectator))
					{
						char sName[100];
						GetClientName(i, sName, sizeof(sName))
						if (StrEqual(sName, "Pin#1") || StrEqual(sName, "Pin#2") || StrEqual(sName, "Pin#3") || StrEqual(sName, "Pin#4") || StrEqual(sName, "Pin#5") || StrEqual(sName, "Pin#6") || StrEqual(sName, "Pin#7") || StrEqual(sName, "Pin#8") || StrEqual(sName, "Pin#9") || StrEqual(sName, "Pin#10"))
						{
							ChangeClientTeam(i, 2);
							TF2_RespawnPlayer(i);
						}
					}
				}
			}
			
			float flPos[3]; float flAngle[3];
			flPos[2] = 0.031250; // z position should always be the same
			
			flAngle[0] = -0.346446;
			flAngle[1] = -89.998428;
			flAngle[2] = 0.000000;
			
			flPos[0] = 72.639099; flPos[1] = 2687.895263;
			TeleportEntity(FindTargetByName("Pin#1"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = 95.112854; flPos[1] = 2744.845458;
			TeleportEntity(FindTargetByName("Pin#2"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = 47.192626; flPos[1] = 2744.845458;
			TeleportEntity(FindTargetByName("Pin#3"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = 119.276855; flPos[1] = 2792.455078;
			TeleportEntity(FindTargetByName("Pin#4"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = 73.345581; flPos[1] = 2792.455078;
			TeleportEntity(FindTargetByName("Pin#5"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = 28.412414; flPos[1] = 2792.455078;
			TeleportEntity(FindTargetByName("Pin#6"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = 142.741516; flPos[1] = 2846.986816;
			TeleportEntity(FindTargetByName("Pin#7"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = 91.407653; flPos[1] = 2846.986816;
			TeleportEntity(FindTargetByName("Pin#8"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = 39.171752; flPos[1] = 2846.986816;
			TeleportEntity(FindTargetByName("Pin#9"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -8.980102; flPos[1] = 2846.986816;
			TeleportEntity(FindTargetByName("Pin#10"), flPos, flAngle, NULL_VECTOR);
		}
		
		case 2:
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					if (GetClientTeam(i) == view_as<int>(TFTeam_Spectator))
					{
						char sName[100];
						GetClientName(i, sName, sizeof(sName))
						if (StrEqual(sName, "Pin#11") || StrEqual(sName, "Pin#12") || StrEqual(sName, "Pin#13") || StrEqual(sName, "Pin#14") || StrEqual(sName, "Pin#15") || StrEqual(sName, "Pin#16") || StrEqual(sName, "Pin#17") || StrEqual(sName, "Pin#18") || StrEqual(sName, "Pin#19") || StrEqual(sName, "Pin#20"))
						{
							ChangeClientTeam(i, 2);
							TF2_RespawnPlayer(i);
						}
					}
				}
			}
			
			float flPos[3]; float flAngle[3];
			flPos[2] = 0.031250; // z position should always be the same
			
			flAngle[0] = -0.230963;
			flAngle[1] = -89.882896;
			flAngle[2] = 0.000000;
			
			flPos[0] = -646.124450; flPos[1] = 2687.895263;
			TeleportEntity(FindTargetByName("Pin#11"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -610.471008; flPos[1] = 2744.845458;
			TeleportEntity(FindTargetByName("Pin#12"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -665.804260; flPos[1] = 2744.845458;
			TeleportEntity(FindTargetByName("Pin#13"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -601.630004; flPos[1] = 2792.455078;
			TeleportEntity(FindTargetByName("Pin#14"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -642.486938; flPos[1] = 2792.455078;
			TeleportEntity(FindTargetByName("Pin#15"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -684.339782; flPos[1] = 2792.455078;
			TeleportEntity(FindTargetByName("Pin#16"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -572.653350; flPos[1] = 2846.986816;
			TeleportEntity(FindTargetByName("Pin#17"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -618.972167; flPos[1] = 2846.986816;
			TeleportEntity(FindTargetByName("Pin#18"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -663.770446; flPos[1] = 2846.986816;
			TeleportEntity(FindTargetByName("Pin#19"), flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = -711.663635; flPos[1] = 2846.986816;
			TeleportEntity(FindTargetByName("Pin#20"), flPos, flAngle, NULL_VECTOR);
		}
	}
}

void PrecacheServer()
{
	AddFileToDownloadsTable("sound/bowling/hit.wav");
	AddFileToDownloadsTable("sound/bowling/roll.wav");
	
	PrecacheSound("bowling/hit.wav", true);
	PrecacheSound("bowling/roll.wav", true);
}

void StripWeapons(int iClient)
{
	for (int i = 0; i <= 5; i++)
		TF2_RemoveWeaponSlot(iClient, i);
}

stock bool CheckPins(int iLane)
{
	switch (iLane)
	{
		case 1:
		{
			if (GetClientTeam(FindTargetByName("Pin#1")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#2")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#3")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#4")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#5")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#6")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#7")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#8")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#9")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#10")) == view_as<int>(TFTeam_Spectator))
			{
				return true;
			}
		}
		
		case 2:
		{
			if (GetClientTeam(FindTargetByName("Pin#11")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#12")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#13")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#14")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#15")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#16")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#17")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#18")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#19")) == view_as<int>(TFTeam_Spectator) && GetClientTeam(FindTargetByName("Pin#20")) == view_as<int>(TFTeam_Spectator))
			{
				return true;
			}
		}
	}
	
	return false;
}

stock int FindTargetByName(char[] name)
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsValidClient(iClient))
		{
			if (IsFakeClient(iClient))
			{
				char sName[32];
				GetClientName(iClient, sName, sizeof(sName));

				if (StrEqual(sName, name))
				{
					return iClient;
				}
			}
		}
	}

	return 0;
}

stock bool IsFlagSet(int iClient, int iFlag)
{
	int HideHUD = GetEntProp(iClient, Prop_Send, "m_iHideHUD");
	
	if (HideHUD & iFlag)
		return true;
		
	return false;
}

stock bool IsValidClient(int iClient, bool bReplay = true)
{
	if (iClient <= 0 || iClient > MaxClients || !IsClientInGame(iClient))
		return false;
	if (bReplay && (IsClientSourceTV(iClient) || IsClientReplay(iClient)))
		return false;
	return true;
}