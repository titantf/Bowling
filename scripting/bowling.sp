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

#define PLUGIN_VERSION "1.1"
#define HIDEHUD_HEALTH (1 << 3)

#define SOUND_ROLL 	"bowling/roll.wav"
#define SOUND_HIT 	"bowling/hit.wav"
	
ConVar
	g_cvMaxPlayers,
	g_cvWFP_Time,
	g_cvRoll_Time;
	
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
	
float
	g_sLane1_PlayingPos[3],
	g_sLane2_PlayingPos[3],
	g_sLane1_ExitPos[3],
	g_sLane2_ExitPos[3],
	
	g_sLane1_AnglePos[3],
	g_sLane2_AnglePos[3],
	
	g_sLane1_Pin1Pos[3],
	g_sLane1_Pin2Pos[3],
	g_sLane1_Pin3Pos[3],
	g_sLane1_Pin4Pos[3],
	g_sLane1_Pin5Pos[3],
	g_sLane1_Pin6Pos[3],
	g_sLane1_Pin7Pos[3],
	g_sLane1_Pin8Pos[3],
	g_sLane1_Pin9Pos[3],
	g_sLane1_Pin10Pos[3],
	
	g_sLane2_Pin1Pos[3],
	g_sLane2_Pin2Pos[3],
	g_sLane2_Pin3Pos[3],
	g_sLane2_Pin4Pos[3],
	g_sLane2_Pin5Pos[3],
	g_sLane2_Pin6Pos[3],
	g_sLane2_Pin7Pos[3],
	g_sLane2_Pin8Pos[3],
	g_sLane2_Pin9Pos[3],
	g_sLane2_Pin10Pos[3];
	
bool
	g_iAlpha_Add = false,
	
	g_bMatch_Party1 = false,
	g_bMatch_Party2 = false,
	
	g_bPlayerSelected_Lane1 = false,
	g_bPlayerSelected_Lane2 = false,
	
	g_bRolled[MAXPLAYERS+1] = false;
	
	
public Plugin myinfo = 
{
	name 			= 	"Bowling for TF2",
	author 			= 	"myst | titan.tf",
	description 	=	"Brings bowling to TF2. Only works on bowl_ and bowling_ maps.",
	version 		=	PLUGIN_VERSION,
	url 			=	"https://titan.tf"
}

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_TF2)
		SetFailState("This plugin does not support any game besides TF2.");
		
	RegConsoleCmd("sm_bhelp", Command_Help);
	
	RegConsoleCmd("sm_join", Command_SelectLane);
	RegConsoleCmd("sm_lane", Command_SelectLane);
	RegConsoleCmd("sm_lanes", Command_SelectLane);
	RegConsoleCmd("sm_bowl", Command_SelectLane);

	RegConsoleCmd("sm_r", Command_Ready);
	RegConsoleCmd("sm_ready", Command_Ready);
	
	RegConsoleCmd("sm_leave", Command_Leave);
	
	RegAdminCmd("sm_teleport", Command_Teleport, ADMFLAG_GENERIC, "Used to teleport a player to where you are pointing at. Use this to setup your pins.");
	RegAdminCmd("sm_getpos", Command_GetPos, ADMFLAG_GENERIC, "Used to print the coordinates of all pins from either lanne 1 or 2. Use this after setting up the positions using sm_teleport.");
	
	g_cvMaxPlayers = CreateConVar("bowling_maxplayers", "6", "Sets the maximum players per lane.", FCVAR_NOTIFY, true, 1.0, true, 6.0);
	g_cvWFP_Time = CreateConVar("bowling_wfp_time", "120", "Sets the maximum waiting for players time.", FCVAR_NOTIFY, true, 10.0, true, 600.0);
	g_cvRoll_Time = CreateConVar("bowling_roll_time", "10", "Sets the maximum time allowed for players to roll their ball. Prevents a troll delaying.", FCVAR_NOTIFY, true, 5.0, true, 60.0);
	
	HookConVarChange(g_cvMaxPlayers, ConvarChanged_MaxPlayers);
	HookConVarChange(g_cvWFP_Time, ConvarChanged_WFP_Time);
	HookConVarChange(g_cvRoll_Time, ConvarChanged_Roll_Time);
	
	g_iMaxPlayers = GetConVarInt(g_cvMaxPlayers);
	g_iWaitingForPlayers = GetConVarInt(g_cvWFP_Time);
	g_iRollTime = GetConVarInt(g_cvRoll_Time);
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeathPost, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	
	AddNormalSoundHook(NormalSoundHook);
	
	g_hHud_Party1 = CreateHudSynchronizer();
	g_hHud_Party2 = CreateHudSynchronizer()
	g_hHud_Score = CreateHudSynchronizer();
	g_hHud_Frame = CreateHudSynchronizer();
	g_hHud_Notifications = CreateHudSynchronizer();
	
	static char sMapConfigPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sMapConfigPath, sizeof(sMapConfigPath), "configs/bowling/maps.cfg");
	
	if (!FileExists(sMapConfigPath))
	{
		SetFailState("Failed to locate bowling config %s!", sMapConfigPath);
		return;
	}
	
	Handle hMapsConfig = CreateKeyValues("Bowling");
	if (!FileToKeyValues(hMapsConfig, sMapConfigPath))
	{
		SetFailState("Incorrect config structure %s!", sMapConfigPath);
		return;
	}
	
	char sMapName[128];
	GetCurrentMap(sMapName, sizeof(sMapName));
	
	if (KvJumpToKey(hMapsConfig, sMapName))
	{
		if (KvJumpToKey(hMapsConfig, "Players"))
		{
			g_sLane1_PlayingPos[0] = KvGetFloat(hMapsConfig, "lane1_playingpos_x", 0.0);
			g_sLane1_PlayingPos[1] = KvGetFloat(hMapsConfig, "lane1_playingpos_y", 0.0);
			g_sLane1_PlayingPos[2] = KvGetFloat(hMapsConfig, "lane1_playingpos_z", 0.0);
			
			g_sLane2_PlayingPos[0] = KvGetFloat(hMapsConfig, "lane2_playingpos_x", 0.0);
			g_sLane2_PlayingPos[1] = KvGetFloat(hMapsConfig, "lane2_playingpos_y", 0.0);
			g_sLane2_PlayingPos[2] = KvGetFloat(hMapsConfig, "lane2_playingpos_z", 0.0);
			
			g_sLane1_ExitPos[0] = KvGetFloat(hMapsConfig, "lane1_exitpos_x", 0.0);
			g_sLane1_ExitPos[1] = KvGetFloat(hMapsConfig, "lane1_exitpos_y", 0.0);
			g_sLane1_ExitPos[2] = KvGetFloat(hMapsConfig, "lane1_exitpos_z", 0.0);
			
			g_sLane2_ExitPos[0] = KvGetFloat(hMapsConfig, "lane2_exitpos_x", 0.0);
			g_sLane2_ExitPos[1] = KvGetFloat(hMapsConfig, "lane2_exitpos_y", 0.0);
			g_sLane2_ExitPos[2] = KvGetFloat(hMapsConfig, "lane2_exitpos_z", 0.0);
			
			KvGoBack(hMapsConfig);
		}
		
		if (KvJumpToKey(hMapsConfig, "Pins"))
		{
			g_sLane1_AnglePos[0] = KvGetFloat(hMapsConfig, "lane1_anglepos_x", 0.0);
			g_sLane1_AnglePos[1] = KvGetFloat(hMapsConfig, "lane1_anglepos_y", 0.0);
			g_sLane1_AnglePos[2] = KvGetFloat(hMapsConfig, "lane1_anglepos_z", 0.0);
			
			g_sLane2_AnglePos[0] = KvGetFloat(hMapsConfig, "lane2_anglepos_x", 0.0);
			g_sLane2_AnglePos[1] = KvGetFloat(hMapsConfig, "lane2_anglepos_y", 0.0);
			g_sLane2_AnglePos[2] = KvGetFloat(hMapsConfig, "lane2_anglepos_z", 0.0);
			
			g_sLane1_Pin1Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin1pos_x", 0.0);
			g_sLane1_Pin1Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin1pos_y", 0.0);
			g_sLane1_Pin1Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin1pos_z", 0.0);
			
			g_sLane1_Pin2Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin2pos_x", 0.0);
			g_sLane1_Pin2Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin2pos_y", 0.0);
			g_sLane1_Pin2Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin2pos_z", 0.0);
			
			g_sLane1_Pin3Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin3pos_x", 0.0);
			g_sLane1_Pin3Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin3pos_y", 0.0);
			g_sLane1_Pin3Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin3pos_z", 0.0);
			
			g_sLane1_Pin4Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin4pos_x", 0.0);
			g_sLane1_Pin4Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin4pos_y", 0.0);
			g_sLane1_Pin4Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin4pos_z", 0.0);
			
			g_sLane1_Pin5Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin5pos_x", 0.0);
			g_sLane1_Pin5Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin5pos_y", 0.0);
			g_sLane1_Pin5Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin5pos_z", 0.0);
			
			g_sLane1_Pin6Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin6pos_x", 0.0);
			g_sLane1_Pin6Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin6pos_y", 0.0);
			g_sLane1_Pin6Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin6pos_z", 0.0);
			
			g_sLane1_Pin7Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin7pos_x", 0.0);
			g_sLane1_Pin7Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin7pos_y", 0.0);
			g_sLane1_Pin7Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin7pos_z", 0.0);
			
			g_sLane1_Pin8Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin8pos_x", 0.0);
			g_sLane1_Pin8Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin8pos_y", 0.0);
			g_sLane1_Pin8Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin8pos_z", 0.0);
			
			g_sLane1_Pin9Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin9pos_x", 0.0);
			g_sLane1_Pin9Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin9pos_y", 0.0);
			g_sLane1_Pin9Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin9pos_z", 0.0);
			
			g_sLane1_Pin10Pos[0] = KvGetFloat(hMapsConfig, "lane1_pin10pos_x", 0.0);
			g_sLane1_Pin10Pos[1] = KvGetFloat(hMapsConfig, "lane1_pin10pos_y", 0.0);
			g_sLane1_Pin10Pos[2] = KvGetFloat(hMapsConfig, "lane1_pin10pos_z", 0.0);
			
			g_sLane2_Pin1Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin1pos_x", 0.0);
			g_sLane2_Pin1Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin1pos_y", 0.0);
			g_sLane2_Pin1Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin1pos_z", 0.0);
			
			g_sLane2_Pin2Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin2pos_x", 0.0);
			g_sLane2_Pin2Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin2pos_y", 0.0);
			g_sLane2_Pin2Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin2pos_z", 0.0);
			
			g_sLane2_Pin3Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin3pos_x", 0.0);
			g_sLane2_Pin3Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin3pos_y", 0.0);
			g_sLane2_Pin3Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin3pos_z", 0.0);
			
			g_sLane2_Pin4Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin4pos_x", 0.0);
			g_sLane2_Pin4Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin4pos_y", 0.0);
			g_sLane2_Pin4Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin4pos_z", 0.0);
			
			g_sLane2_Pin5Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin5pos_x", 0.0);
			g_sLane2_Pin5Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin5pos_y", 0.0);
			g_sLane2_Pin5Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin5pos_z", 0.0);
			
			g_sLane2_Pin6Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin6pos_x", 0.0);
			g_sLane2_Pin6Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin6pos_y", 0.0);
			g_sLane2_Pin6Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin6pos_z", 0.0);
			
			g_sLane2_Pin7Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin7pos_x", 0.0);
			g_sLane2_Pin7Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin7pos_y", 0.0);
			g_sLane2_Pin7Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin7pos_z", 0.0);
			
			g_sLane2_Pin8Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin8pos_x", 0.0);
			g_sLane2_Pin8Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin8pos_y", 0.0);
			g_sLane2_Pin8Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin8pos_z", 0.0);
			
			g_sLane2_Pin9Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin9pos_x", 0.0);
			g_sLane2_Pin9Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin9pos_y", 0.0);
			g_sLane2_Pin9Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin9pos_z", 0.0);
			
			g_sLane2_Pin10Pos[0] = KvGetFloat(hMapsConfig, "lane2_pin10pos_x", 0.0);
			g_sLane2_Pin10Pos[1] = KvGetFloat(hMapsConfig, "lane2_pin10pos_y", 0.0);
			g_sLane2_Pin10Pos[2] = KvGetFloat(hMapsConfig, "lane2_pin10pos_z", 0.0);
			
			KvGoBack(hMapsConfig);
		}
		
		KvGoBack(hMapsConfig);
		KvRewind(hMapsConfig);
	}
	
	else
		LogError("No configs were found for this map.");
}

public void OnPluginEnd()
{
	UnhookEvent("player_spawn", Event_PlayerSpawn);
	
	UnhookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	
	UnhookEvent("player_death", Event_PlayerDeathPost, EventHookMode_Post);
	UnhookEvent("player_death", Event_PlayerDeathPre, EventHookMode_Pre);
	
	for (int i = 1; i <= MaxClients; i++)
		Bowl_ResetPlayer(i);
}

public void ConvarChanged_MaxPlayers(Handle hConvar, const char[] sOldVal, const char[] sNewVal) {
	g_iMaxPlayers = StringToInt(sNewVal);
}

public void ConvarChanged_WFP_Time(Handle hConvar, const char[] sOldVal, const char[] sNewVal) {
	g_iWaitingForPlayers = StringToInt(sNewVal);
}

public void ConvarChanged_Roll_Time(Handle hConvar, const char[] sOldVal, const char[] sNewVal) {
	g_iRollTime = StringToInt(sNewVal);
}

public void OnMapStart()
{
	char sMapName[128];
	GetCurrentMap(sMapName, sizeof(sMapName));
	
	if (StrContains(sMapName, "bowl_", false) == -1 && StrContains(sMapName, "bowling_", false) == -1)
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
			Format(sFormat, sizeof(sFormat), "Bowling (%s)", PLUGIN_VERSION);
			
			Steam_SetGameDescription(sFormat);
		}
		#endif
		
		AddServerTag("bowling");
	}
	
	SetConVarInt(FindConVar("tf_playergib"), 0, true, false);
	SetConVarInt(FindConVar("mp_autoteambalance"), 0, true, false);
	SetConVarInt(FindConVar("mp_teams_unbalance_limit"), 0, true, false);
	
	Bowl_ConnectPins();
	PrecacheServer();
	
	g_iAlpha = 255;
	g_iAlpha_Add = false;
	
	CreateTimer(0.7, Timer_RightPanel, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	CreateTimer(0.9, Timer_PulsePins, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int iClient)
{
	if (g_iParty[iClient] != 0)
		g_iParty[iClient] = 0;
		
	if (IsValidClient(iClient))
		if (IsFakeClient(iClient))
			ChangeClientTeam(iClient, 1);
}

public void OnClientDisconnect(int iClient) {
	Bowl_ResetPlayer(iClient);
}

public Action Event_PlayerSpawn(Handle hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	
	if (!IsFakeClient(iClient) && GetClientTeam(iClient) == view_as<int>(TFTeam_Red))
		ChangeClientTeam(iClient, view_as<int>(TFTeam_Blue));
	else if (IsFakeClient(iClient) && GetClientTeam(iClient) == view_as<int>(TFTeam_Blue))
		ChangeClientTeam(iClient, view_as<int>(TFTeam_Red));
		
	if (IsFakeClient(iClient))
	{
		TF2_AddCondition(iClient, TFCond_MegaHeal, 9999.9);		
		SetEntityRenderMode(iClient, RENDER_TRANSCOLOR);
		StripWeapons(iClient);
	}
}

public Action Event_PlayerTeam(Handle hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent,"userid"));
	if (!IsFakeClient(iClient))
		Bowl_ResetPlayer(iClient);
}

public Action Event_PlayerDeathPre(Handle hEvent, const char[] sEventName, bool bDontBroadcast)
{
	SetEventBroadcast(hEvent, true);
	return Plugin_Continue;
}

public Action Event_PlayerDeathPost(Handle hEvent, const char[] sEventName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
	int iAttacker = GetClientOfUserId(GetEventInt(hEvent, "attacker"));
	
	if (IsFakeClient(iClient))
	{
		if (g_iParty[iAttacker] != 0)
		{
			g_iScore[iAttacker]++;
			
			EmitSoundToAll(SOUND_HIT, iClient);
			ChangeClientTeam(iClient, 1);
			
			switch (g_iParty[iAttacker])
			{
				case 1:
				{
					if (Bowl_CheckPins(1))
					{
						if (GetEntProp(GetEntPropEnt(iAttacker, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 1)
						{
							PrintToChatAll("\x075885A2%N \x07FFFFFFscored a \x07CF6A32STRIKE\x07FFFFFF!", iAttacker);
							ShowSyncHudText_Notification(iAttacker, "S T R I K E", "strike");
						}
						
						else if (GetEntProp(GetEntPropEnt(iAttacker, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 0)
						{
							PrintToChatAll("\x075885A2%N \x07FFFFFFscored a \x07FFD700SPARE\x07FFFFFF!", iAttacker);
							ShowSyncHudText_Notification(iAttacker, "S P A R E", "spare");
						}
						
						Bowl_RemovePlayer(iAttacker);
					}
				}
				
				case 2:
				{
					if (Bowl_CheckPins(2))
					{
						if (GetEntProp(GetEntPropEnt(iAttacker, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 1)
						{
							PrintToChatAll("\x075885A2%N \x07FFFFFFscored a \x07CF6A32STRIKE\x07FFFFFF!", iAttacker);
							ShowSyncHudText_Notification(iAttacker, "S T R I K E", "strike");
						}
						
						else if (GetEntProp(GetEntPropEnt(iAttacker, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 0)
						{
							PrintToChatAll("\x075885A2%N \x07FFFFFFscored a \x07FFD700SPARE\x07FFFFFF!", iAttacker);
							ShowSyncHudText_Notification(iAttacker, "S P A R E", "spare");
						}
						
						Bowl_RemovePlayer(iAttacker);
					}
				}
			}
		}
	}

	else
	{
		CreateTimer(0.1, Timer_Respawn, iClient, TIMER_FLAG_NO_MAPCHANGE);
		
		if (iClient == g_iCurrentPlayer_Party1 || iClient == g_iCurrentPlayer_Party2)
			Bowl_RemovePlayer(iClient);
	}
}

public Action NormalSoundHook(int iClients[64], int &iNumClients, char sSound[PLATFORM_MAX_PATH], int &iEntity, int &iChannel, float &flVolume, int &iLevel, int &iPitch, int &iFlags)
{
	if (StrContains(sSound, "loose_cannon_shoot", false) != -1)
	{
		if (g_iParty[iEntity] == 1 || g_iParty[iEntity] == 2)
		{
			sSound = SOUND_ROLL;
			return Plugin_Changed;
		}
	}
	
	if (StrContains(sSound, "pain", false) != -1)
		return Plugin_Stop;
		
	return Plugin_Continue;
}

public Action Timer_Respawn(Handle hTimer, int iClient) {
	TF2_RespawnPlayer(iClient);
}

public Action Command_GetPos(int iClient, int iArgs)
{
	float
		flEye[3],
		flPos[3];
		
	int
		iTarget;
		
	if (iArgs)
	{
		char sTarget[64];
		GetCmdArgString(sTarget, sizeof(sTarget));
		
		iTarget = FindTargetByName(sTarget);
		if (iTarget == 0)
			return Plugin_Handled;
	}
	
	else
		iTarget = iClient;
		
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
	
	int
		iMaxPlayers,
		iPlayer;
		
	char
		sPlayerName[MAX_NAME_LENGTH],
		sName[MAX_NAME_LENGTH];
		
	float
		flTeleportOrigin[3],
		flPlayerOrigin[3];
		
	iPlayer = -1;
	iMaxPlayers = GetMaxClients();
	GetCmdArg(1, sPlayerName, sizeof(sPlayerName));
	
	for (int i = 1; i <= iMaxPlayers; i++)
	{
		if (!IsValidClient(i))
			continue;
			
		GetClientName(i, sName, sizeof(sName));
		
		if (StrContains(sName, sPlayerName, false) != -1)
			iPlayer = i;
	}

	if (iPlayer == -1)
	{
		PrintToChat(iClient, "\x07FFFFFFNo matching client was found.");
		return Plugin_Handled;
	}

	GetClientName(iPlayer, sName, sizeof(sName));
	
	flTeleportOrigin[0] = flPlayerOrigin[0];
	flTeleportOrigin[1] = flPlayerOrigin[1];
	flTeleportOrigin[2] = (flPlayerOrigin[2] + 4);

	TeleportEntity(iPlayer, flTeleportOrigin, NULL_VECTOR, NULL_VECTOR);
	return Plugin_Handled;
}

public Action Timer_RightPanel(Handle hTimer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iParty[i] == 0 && IsClientConnected(i))
		{
			char sFormat[256];
			Format(sFormat, sizeof(sFormat), "Lane 1\n%i/%i %s\n \nLane 2\n%i/%i %s", g_iPlayers_Party1, g_iMaxPlayers, (g_bMatch_Party1 == true ? "(Locked)" : "(Open)"), g_iPlayers_Party2, g_iMaxPlayers, (g_bMatch_Party2 == true ? "(Locked)" : "(Open)"));
			
			Handle hBuffer = StartMessageOne("KeyHintText", i);
			BfWriteByte(hBuffer, 1);
			BfWriteString(hBuffer, sFormat);
			EndMessage();
		}
	}
}

public Action Timer_PulsePins(Handle hTimer)
{
	if (g_iAlpha_Add)
		g_iAlpha_Add = false;
	else
		g_iAlpha_Add = true;
}

public Action Command_Help(int iClient, int iArgs)
{
	Handle hMenu = CreateMenu(Handle_Help, MenuAction_Select | MenuAction_Cancel | MenuAction_End);
	SetMenuTitle(hMenu, "Bowling Guide\n \n");
	
	AddMenuItem(hMenu, "", "Strike\nWhen all 10 pins are knocked down with one ball.\n \n");
	AddMenuItem(hMenu, "", "Spare\nAll 10 pins are knocked down with 2 consecutive balls.\n \n");
	AddMenuItem(hMenu, "", "Game\nA game consists of 10 frames per person.\n \n");
	AddMenuItem(hMenu, "", "Frame\nA frame consists of up to two deliveries. However the\n10th frame consists of up to 3 deliveries.\n \n");
	AddMenuItem(hMenu, "", "Double\nOccurs when 2 strikes in a row are bowled.\n \n");
	AddMenuItem(hMenu, "", "Turkey\nOccurs when 3 strikes in a row are bowled.");
	
	DisplayMenu(hMenu, iClient, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int Handle_Help(Handle menu, MenuAction maAction, int iClient, int iButton)
{
	switch (maAction)
	{
		case MenuAction_Select:
			Command_Help(iClient, 0);
		case MenuAction_End:
			CloseHandle(menu);
	}
}

public Action Command_SelectLane(int iClient, int iArgs)
{
	if (iArgs)
	{
		char sLane[64];
		GetCmdArgString(sLane, sizeof(sLane));
		
		if (StringToInt(sLane) == 1 || StringToInt(sLane) == 2)
			Bowl_SelectLane(iClient, StringToInt(sLane));
		else
			PrintToChat(iClient, "\x07FF4040Invalid argument received. Only 1 or 2 is accepted.");
	}
	
	else
	{
		char sFormatLane1[64];
		char sFormatLane2[64];
		
		Handle hPanel = CreatePanel();
		SetPanelTitle(hPanel, "Lane Selection\n \n");
		
		Format(sFormatLane1, sizeof(sFormatLane1), "Lane 1 (%i/%i)%s", g_iPlayers_Party1, g_iMaxPlayers, (g_bMatch_Party1 == true ? " [Locked]" : " [Open]"));
		Format(sFormatLane2, sizeof(sFormatLane2), "Lane 2 (%i/%i)%s", g_iPlayers_Party2, g_iMaxPlayers, (g_bMatch_Party2 == true ? " [Locked]" : " [Open]"));
		
		if (g_iPlayers_Party1 < 6)
			DrawPanelItem(hPanel, sFormatLane1);
		else
			DrawPanelItem(hPanel, sFormatLane1, ITEMDRAW_DISABLED);
			
		if (g_iPlayers_Party2 < 6)
			DrawPanelItem(hPanel, sFormatLane2);
		else
			DrawPanelItem(hPanel, sFormatLane2, ITEMDRAW_DISABLED);
			
		DrawPanelText(hPanel, " ");
		
		for (int i = 0; i <= 6; i++)
			DrawPanelItem(hPanel, " ", ITEMDRAW_NOTEXT);
			
		DrawPanelItem(hPanel, "Close", ITEMDRAW_CONTROL);
		SendPanelToClient(hPanel, iClient, Handle_LaneSelect, MENU_TIME_FOREVER);
	}
	
	return Plugin_Handled;
}

public int Handle_LaneSelect(Handle menu, MenuAction maAction, int iClient, int iButton)
{
	switch (maAction)
	{
		case MenuAction_Select:
		{
			switch (iButton)
			{
				case 1:
					Bowl_SelectLane(iClient, 1);
				case 2:
					Bowl_SelectLane(iClient, 2);
				case 10:
					CloseHandle(menu);
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
				PrintToChat_LaneAnnounce(1, "\x07CCCCCCEveryone in the lane is ready. The match will begin in 10 seconds..");
				
			if (g_iPlayers_Party1 != g_iMaxPlayers)
				PrintToChatAll("\x07FF4040A match is about to start at Lane 1 in 10 seconds.. (%i/%i)", g_iPlayers_Party1, g_iMaxPlayers);
		}
		
		return Plugin_Stop;
    }
	
	g_iRemaining_Party1--;
	SetHudTextParams(-1.0, 0.15, 1.0, 255, 255, 255, 255);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == 1)
			{
				ShowSyncHudText(i, g_hHud_Party1, "\n \nLane 1\n \nWaiting for Players.. (%i)\n \n \n \n \n \nThe match will start automatically when there are %i players\nor when everyone is ready.", g_iRemaining_Party1, g_iMaxPlayers);
				
				char sFormat[512];
				for (int j = 1; j <= MaxClients; j++)
				{
					if (IsValidClient(j))
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
				
				Format(sFormat, sizeof(sFormat), "%s\n \n!r - Ready\n!leave - Leave", sFormat);
				
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
				PrintToChat_LaneAnnounce(2, "\x07CCCCCCEveryone in the lane is ready. The match will begin in 10 seconds..");
				
			if (g_iPlayers_Party2 != g_iMaxPlayers)
				PrintToChatAll("\x07FF4040A match is about to start at Lane 2 in 10 seconds.. (%i/%i)", g_iPlayers_Party2, g_iMaxPlayers);
		}
		
		return Plugin_Stop; 
    }
	
	g_iRemaining_Party2--;
	SetHudTextParams(-1.0, 0.15, 1.0, 255, 255, 255, 255);
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == 2)
			{
				ShowSyncHudText(i, g_hHud_Party2, "\n \nLane 2\n \nWaiting for players.. (%i)\n \n \n \n \n \nThe match will start automatically when there are %i players\nor when everyone is ready.", g_iRemaining_Party2, g_iMaxPlayers);
				
				char sFormat[256];
				for (int j = 1; j <= MaxClients; j++)
				{
					if (IsValidClient(j))
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
				
				Format(sFormat, sizeof(sFormat), "%s\n \n!r - Ready\n!leave - Leave", sFormat);
				
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
		if (IsValidClient(i))
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == 1)
				ShowSyncHudText(i, g_hHud_Party1, "%i", g_iRemaining_Party1);
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
		if (IsValidClient(i))
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == 2)
				ShowSyncHudText(i, g_hHud_Party2, "%i", g_iRemaining_Party2);
	}
	
	return Plugin_Continue;
}

public Action Timer_Hud_Party1(Handle hTimer)
{
	if (!g_bMatch_Party1)
		return Plugin_Stop;
		
	Bowl_ShowScores(1);
	return Plugin_Continue;
}

public Action Timer_Hud_Party2(Handle hTimer)
{
	if (!g_bMatch_Party2)
		return Plugin_Stop;
		
	Bowl_ShowScores(2);
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
			
			if (iClient != g_iCurrentPlayer_Party1)
				return Plugin_Stop;
				
			else if (g_iRemaining_Party1 == 0 || (GetEntProp(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 0) || Bowl_CheckPins(1))
			{
				Bowl_RemovePlayer(iClient);
				return Plugin_Stop;
			}
			
			else
				g_iRemaining_Party1--;
		}
		
		case 2:
		{
			char sWeapon[50];
			GetClientWeapon(iClient, sWeapon, sizeof(sWeapon));
			
			if (iClient != g_iCurrentPlayer_Party2)
				return Plugin_Stop;
				
			else if (g_iRemaining_Party2 == 0 || (GetEntProp(GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"), Prop_Send, "m_iClip1") == 0) || Bowl_CheckPins(2))
			{
				Bowl_RemovePlayer(iClient);
				return Plugin_Stop;
			}
			
			else
				g_iRemaining_Party2--;
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
				
				if (g_iParty[iClient] == 1)
					g_iReady_Party1++;
				else
					g_iReady_Party2++;
					
				PrintToChat(iClient, "\x07FFFFFFYou are now ready.");
			}
			
			else if (g_iReady[iClient] == 1)
			{
				g_iReady[iClient] = 0;
				
				if (g_iParty[iClient] == 1)
					g_iReady_Party1--;
				else
					g_iReady_Party2--;
					
				PrintToChat(iClient, "\x07FFFFFFYou are no longer ready.");
			}
		}
		
		else
			PrintToChat(iClient, "\x07FFFFFFThe match has already started.");
	}
	
	else
	{
		PrintToChat(iClient, "\x07FFFFFFPlease join a bowling lane first.");
		Command_SelectLane(iClient, 0);
	}
}

public Action Command_Leave(int iClient, int iArgs)
{
	if (g_iParty[iClient] != 0)
	{
		if (iClient != g_iCurrentPlayer_Party1 && iClient != g_iCurrentPlayer_Party2)
		{
			if (g_iParty[iClient] == 1)
			{
				g_iReady_Party1--;
				g_iPlayers_Party1--;
				
				PrintToChat(iClient, "\x07FFFFFFYou left Lane 1.");
				PrintToChat_LeftLane(iClient, 1);
				
				Bowl_UpdateLane(1);
					
				g_iReady[iClient] = 0;
				g_iParty[iClient] = 0;
				g_iScore[iClient] = 0;
			}
			
			else
			{
				g_iReady_Party2--;
				g_iPlayers_Party2--;
				
				PrintToChat(iClient, "\x07FFFFFFYou left Lane 2.");
				PrintToChat_LeftLane(iClient, 2);
				
				Bowl_UpdateLane(2);
					
				g_iReady[iClient] = 0;
				g_iParty[iClient] = 0;
				g_iScore[iClient] = 0;
			}
		}
	}
	
	else
		PrintToChat(iClient, "\x07FFFFFFYou are not in any lanes.");
}

public void OnGameFrame()
{
	if (!g_bPlayerSelected_Lane1 && g_bMatch_Party1)
	{
		if (g_iFrame_Lane1 + 1 != 12)
			Bowl_SelectPlayer(1, g_iFrame_Lane1);
			
		else
		{
			g_bPlayerSelected_Lane1 = true;
			CreateTimer(3.0, Bowl_EndSession, 1, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	
	else if (!g_bPlayerSelected_Lane2 && g_bMatch_Party2)
	{
		if (g_iFrame_Lane2 + 1 != 12)
			Bowl_SelectPlayer(2, g_iFrame_Lane2)
			
		else
		{
			g_bPlayerSelected_Lane2 = true;
			CreateTimer(3.0, Bowl_EndSession, 2, TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1)
				SetEntProp(i, Prop_Send, "m_nStreaks", g_iScore[i], _, 0);
			else if (IsFakeClient(i) && !g_bMatch_Party1 && !g_bMatch_Party2 && GetClientTeam(i) != 1)
				ChangeClientTeam(i, 1);
		}
	}
	
	if (g_iAlpha_Add)
		g_iAlpha++;
	else
		g_iAlpha--;
		
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
			if (IsFakeClient(i) && GetClientTeam(i) == view_as<int>(TFTeam_Red))
				SetEntityRenderColor(i, 255, 255, 255, g_iAlpha);
	}
}

public void OnEntityCreated(int iEntity, const char[] classname)
{
 	if (strcmp(classname, "tf_ammo_pack") == 0 || strcmp(classname, "tf_dropped_weapon") == 0)
		SDKHook(iEntity, SDKHook_Spawn, Hook_OnEntityCreated);
}

public Action Hook_OnEntityCreated(int iEntity) {
	AcceptEntityInput(iEntity, "Kill");
}

stock void Bowl_RemovePlayer(int iClient)
{
	switch (g_iParty[iClient])
	{
		case 1: g_bPlayerSelected_Lane1 = false, g_iCurrentPlayer_Party1 = 0;
		case 2: g_bPlayerSelected_Lane2 = false, g_iCurrentPlayer_Party2 = 0;
	}
	
	CreateTimer(1.7, Bowl_TeleportOutside, iClient, TIMER_FLAG_NO_MAPCHANGE);
	TF2_RemoveCondition(iClient, TFCond_HalloweenCritCandy);
}

stock void Bowl_SelectLane(int iClient, int iLane)
{
	switch (iLane)
	{
		case 1:
		{
			if (g_iPlayers_Party1 < g_iMaxPlayers)
			{
				if (g_iParty[iClient] == 1)
					PrintToChat(iClient, "\x07FFFFFFYou are already in Lane 1.");
					
				else
				{
					if (!g_bMatch_Party1)
					{
						if (g_iParty[iClient] == 2)
						{
							g_iPlayers_Party2--;
							Bowl_UpdateLane(2);
							
							if (iClient == g_iCurrentPlayer_Party2)
								Bowl_RemovePlayer(iClient);
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
				if (g_iParty[iClient] == 2)
					PrintToChat(iClient, "\x07FFFFFFYou are already in Lane 2.");
					
				else
				{
					if (!g_bMatch_Party2)
					{
						if (g_iParty[iClient] == 1)
						{
							g_iPlayers_Party1--;
							Bowl_UpdateLane(1);
							
							if (iClient == g_iCurrentPlayer_Party1)
								Bowl_RemovePlayer(iClient);
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

stock void PrintToChat_JoinLane(int iClient, int iLane)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsValidClient(i))
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == iLane)
				PrintToChat(i, "\x075885A2%N \x07FFFFFFhas joined Lane %i.", iClient, iLane);
}

stock void PrintToChat_LeftLane(int iClient, int iLane)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsValidClient(i))
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == iLane)
				PrintToChat(i, "\x075885A2%N \x07FFFFFFhas left the lane.", iClient);
}

stock void PrintToChat_LaneAnnounce(int iLane, const char[] sText)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsValidClient(i))
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == iLane)
				PrintToChat(i, "%s", sText);
}

stock void ShowSyncHudText_Notification(int iClient, const char[] sClientText, const char[] sAllText)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			switch (g_iParty[iClient])
			{
				case 1:
				{
					if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && i != g_iCurrentPlayer_Party1)
					{
						SetHudTextParamsEx(-1.0, 0.15, 5.0, {255,255,255,255}, {0,0,0,0}, 2, 0.1, 0.1, 0.1);
						ShowSyncHudText(i, g_hHud_Notifications, "%N scored a %s!", iClient, sAllText);
					}
					
					else if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && i == g_iCurrentPlayer_Party1)
					{
						SetHudTextParamsEx(-1.0, 0.15, 5.0, {255,255,255,255}, {0,0,0,0}, 2, 0.1, 0.1, 0.1);
						ShowSyncHudText(i, g_hHud_Notifications, sClientText);
					}
				}
				
				case 2:
				{
					if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && i != g_iCurrentPlayer_Party2)
					{
						SetHudTextParamsEx(-1.0, 0.15, 5.0, {255,255,255,255}, {0,0,0,0}, 2, 0.1, 0.1, 0.1);
						ShowSyncHudText(i, g_hHud_Notifications, "%N scored a %s!", iClient, sAllText);
					}
					
					else if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && i == g_iCurrentPlayer_Party2)
					{
						SetHudTextParamsEx(-1.0, 0.15, 5.0, {255,255,255,255}, {0,0,0,0}, 2, 0.1, 0.1, 0.1);
						ShowSyncHudText(i, g_hHud_Notifications, sClientText);
					}
				}
			}
		}
	}
}

stock void Bowl_UpdateLane(int iLane)
{
	if (iLane == 1)
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
	
	if (iLane == 2)
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

stock void Bowl_ShowScores(int iLane)
{
	char sFormatScores[512];
	switch (iLane)
	{
		case 1:
		{
			Format(sFormatScores, sizeof(sFormatScores), "Lane 1\n");
			if (g_iCurrentPlayer_Party1 > 0 && g_iRemaining_Party1 >= 1)
				Format(sFormatScores, sizeof(sFormatScores), "%s%N (%02d:%02d)\n \n", sFormatScores, g_iCurrentPlayer_Party1, g_iRemaining_Party1 / 60, g_iRemaining_Party1 % 60);
			else
				Format(sFormatScores, sizeof(sFormatScores), "%s \n \n", sFormatScores);
				
			Format(sFormatScores, sizeof(sFormatScores), "%sFrame %i/10\n", sFormatScores, g_iFrame_Lane1);
			
			for (int i = 0; i < g_iFrame_Lane1; i++)
				StrCat(sFormatScores, sizeof(sFormatScores), "▬");
			for (int i = 0; i < 10-g_iFrame_Lane1; i++)
				StrCat(sFormatScores, sizeof(sFormatScores), " ");
				
			Format(sFormatScores, sizeof(sFormatScores), "%s\n \n", sFormatScores);
		}
		
		case 2:
		{
			Format(sFormatScores, sizeof(sFormatScores), "Lane 2\n");
			if (g_iCurrentPlayer_Party2 && g_iRemaining_Party2 >= 1)
				Format(sFormatScores, sizeof(sFormatScores), "%s%N (%02d:%02d)\n \n", sFormatScores, g_iCurrentPlayer_Party2, g_iRemaining_Party2 / 60, g_iRemaining_Party2 % 60);
			else
				Format(sFormatScores, sizeof(sFormatScores), "%s \n \n", sFormatScores);
				
			Format(sFormatScores, sizeof(sFormatScores), "%sFrame %i/10\n", sFormatScores, g_iFrame_Lane2);
			
			for (int i = 0; i < g_iFrame_Lane2; i++)
				StrCat(sFormatScores, sizeof(sFormatScores), "▬");
			for (int i = 0; i < 10-g_iFrame_Lane2; i++)
				StrCat(sFormatScores, sizeof(sFormatScores), " ");
				
			Format(sFormatScores, sizeof(sFormatScores), "%s\n \n", sFormatScores);
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == iLane)
				Format(sFormatScores, sizeof(sFormatScores), "%s%N - %i\n", sFormatScores, i, g_iScore[i]);
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == iLane)
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

stock bool Bowl_SelectPlayer(int iLane, int iFrame)
{
	if (iFrame == 1)
	{
		for (int i = 1; i <= MaxClients; i++)
			g_iReady[i] = 0;
	}
	
	bool bChosen = false
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			if (!IsFakeClient(i) && GetClientTeam(i) >= 1 && g_iParty[i] == iLane && !g_bRolled[i])
			{
				switch (iLane)
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
			if (g_iParty[i] == iLane)
				g_bRolled[i] = false;
		}
		
		switch (iLane)
		{
			case 1: g_bPlayerSelected_Lane1 = false, g_iFrame_Lane1++;
			case 2: g_bPlayerSelected_Lane2 = false, g_iFrame_Lane2++;
		}
	}
	
	else
	{
		switch (iLane)
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
		case 1: g_iCurrentPlayer_Party1 = iClient, Bowl_TeleportToLane(iClient, 1), TeleportPins(1), Bowl_GiveLooseCannon(iClient, g_iFrame_Lane1);
		case 2: g_iCurrentPlayer_Party2 = iClient, Bowl_TeleportToLane(iClient, 2), TeleportPins(2), Bowl_GiveLooseCannon(iClient, g_iFrame_Lane2);
	}
}

stock void Bowl_GiveLooseCannon(int iClient, int iFrame)
{
	if (IsValidClient(iClient) && IsPlayerAlive(iClient))
	{
		TF2Items_GiveWeapon(iClient, 996);
		TF2_AddCondition(iClient, TFCond_HalloweenCritCandy, 9999.9);
		
		int iWeapon = GetPlayerWeaponSlot(iClient, 0);
		if (IsValidEntity(iWeapon))
		{
			SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 0);
			
			if (iFrame == 10)
			{
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				SetEntData(iWeapon, iAmmoTable, 3, 4, true);
				
				PrintToChat(iClient, "\x07FFFFFFIt's the last frame! You get up to 3 bowls.");
			}
			
			else
			{
				int iAmmoTable = FindSendPropInfo("CTFWeaponBase", "m_iClip1");
				SetEntData(iWeapon, iAmmoTable, 2, 4, true);
				
				PrintToChat(iClient, "\x07FFFFFFIt's your turn! You get up to 2 bowls.");
			}
			
			int iOffset = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType", 1)*4;
			int iAmmoTable = FindSendPropInfo("CTFPlayer", "m_iAmmo");
			SetEntData(iClient, iAmmoTable+iOffset, 0, 4, true);
		}
	}
}

stock void Bowl_TeleportToLane(int iClient, int iLane)
{
	float flPos[3];
	if (iLane == 1)
	{
		flPos[0] = g_sLane1_PlayingPos[0];
		flPos[1] = g_sLane1_PlayingPos[1];
		flPos[2] = g_sLane1_PlayingPos[2];
	}
	
	else
	{
		flPos[0] = g_sLane2_PlayingPos[0];
		flPos[1] = g_sLane2_PlayingPos[1];
		flPos[2] = g_sLane2_PlayingPos[2];
	}
	
	if (!IsPlayerAlive(iClient))
		TF2_RespawnPlayer(iClient);
		
	TeleportEntity(iClient, flPos, NULL_VECTOR, NULL_VECTOR);
	if (!IsFlagSet(iClient, HIDEHUD_HEALTH))
	{
		int HideHUD = GetEntProp(iClient, Prop_Send, "m_iHideHUD");
		HideHUD ^= HIDEHUD_HEALTH;
		SetEntProp(iClient, Prop_Send, "m_iHideHUD", HideHUD);
	}
	
	SetHudTextParams(-1.0, 0.1, 5.0, 255, 255, 255, 255);
	if (iLane == 1)
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

public Action Bowl_TeleportOutside(Handle hTimer, int iClient)
{
	float flPos[3];
	if (g_iParty[iClient] == 1)
	{
		flPos[0] = g_sLane1_ExitPos[0];
		flPos[1] = g_sLane1_ExitPos[1];
		flPos[2] = g_sLane1_ExitPos[2];
	}
	
	else
	{
		flPos[0] = g_sLane2_ExitPos[0];
		flPos[1] = g_sLane2_ExitPos[1];
		flPos[2] = g_sLane2_ExitPos[2];
	}
	
	if (IsPlayerAlive(iClient))
	{
		TeleportEntity(iClient, flPos, NULL_VECTOR, NULL_VECTOR);
		TF2_RegeneratePlayer(iClient);
	}
	
	SetEntProp(iClient, Prop_Send, "m_bDrawViewmodel", 1);
	if (IsFlagSet(iClient, HIDEHUD_HEALTH))
	{
		int HideHUD = GetEntProp(iClient, Prop_Send, "m_iHideHUD");
		HideHUD ^= HIDEHUD_HEALTH;
		SetEntProp(iClient, Prop_Send, "m_iHideHUD", HideHUD);
	}
}

stock void Bowl_RestoreDefaults(int iLane)
{
	switch (iLane)
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

stock void Bowl_ResetPlayer(int iClient)
{
	if (g_iParty[iClient] != 0)
	{
		if (g_iParty[iClient] == 1)
		{
			g_iPlayers_Party1--;
			PrintToChat_LeftLane(iClient, 1);
			Bowl_UpdateLane(1);
		}
		
		else if (g_iParty[iClient] == 2)
		{
			g_iPlayers_Party2--;
			PrintToChat_LeftLane(iClient, 2);
			Bowl_UpdateLane(2);
		}
		
		g_iParty[iClient] = 0;
	}
	
	g_iScore[iClient] = 0;
	g_iReady[iClient] = 0;
	
	g_bRolled[iClient] = false;
	
	if (iClient == g_iCurrentPlayer_Party1 || iClient == g_iCurrentPlayer_Party2)
		Bowl_RemovePlayer(iClient);
}

public Action Bowl_EndSession(Handle hTimer, int iLane)
{
	switch (iLane)
	{
		case 1: Bowl_RestoreDefaults(1);
		case 2: Bowl_RestoreDefaults(2);
	}
	
	int highestScore = 0;
	int highestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsValidClient(z) && IsPlayerAlive(z) && g_iParty[z] == iLane && g_iScore[z] > highestScore)
		{
			highestScore = g_iScore[z];
			highestScoreClient = z;
		}
	}
	
	int secondHighestScore = 0;
	int secondHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsValidClient(z) && IsPlayerAlive(z) && g_iParty[z] == iLane && g_iScore[z] > secondHighestScore && z != highestScoreClient)
		{
			secondHighestScore = g_iScore[z];
			secondHighestScoreClient = z;
		}
	}
	
	int thirdHighestScore = 0;
	int thirdHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsValidClient(z) && IsPlayerAlive(z) && g_iParty[z] == iLane && g_iScore[z] > thirdHighestScore && z != highestScoreClient && z != secondHighestScoreClient)
		{
			thirdHighestScore = g_iScore[z];
			thirdHighestScoreClient = z;
		}
	}
	
	int fourthHighestScore = 0;
	int fourthHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsValidClient(z) && IsPlayerAlive(z) && g_iParty[z] == iLane && g_iScore[z] > fourthHighestScore && z != highestScoreClient && z != secondHighestScoreClient && z != thirdHighestScoreClient)
		{
			fourthHighestScore = g_iScore[z];
			fourthHighestScoreClient = z;
		}
	}
	
	int fifthHighestScore = 0;
	int fifthHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsValidClient(z) && IsPlayerAlive(z) && g_iParty[z] == iLane && g_iScore[z] > fifthHighestScore && z != highestScoreClient && z != secondHighestScoreClient && z != thirdHighestScoreClient && z != fourthHighestScoreClient)
		{
			fifthHighestScore = g_iScore[z];
			fifthHighestScoreClient = z;
		}
	}
	
	int sixthHighestScore = 0;
	int sixthHighestScoreClient = -1;
	for (int z = 1; z <= GetMaxClients(); z++)
	{
		if (IsValidClient(z) && IsPlayerAlive(z) && g_iParty[z] == iLane && g_iScore[z] > sixthHighestScore && z != highestScoreClient && z != secondHighestScoreClient && z != thirdHighestScoreClient && z != fourthHighestScoreClient && z != fifthHighestScoreClient)
		{
			sixthHighestScore = g_iScore[z];
			sixthHighestScoreClient = z;
		}
	}
	
	char
		sFormatHud[512],
		sFormatChat[512];
		
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
	else
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#2] --- - -", sFormatHud);
		
	if (thirdHighestScore != 0)
	{
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#3] %N - %i", sFormatHud, thirdHighestScoreClient, g_iScore[thirdHighestScoreClient]);
		Format(sFormatChat, sizeof(sFormatChat), "%s\n\x07CF6A32%N \x07FFFFFF- %i", sFormatChat, thirdHighestScoreClient, g_iScore[thirdHighestScoreClient]);
	}
	else
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#3] --- - -", sFormatHud);
		
	if (fourthHighestScore != 0)
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#4] %N - %i", sFormatHud, fourthHighestScoreClient, g_iScore[fourthHighestScoreClient]);
	else
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#4] --- - -", sFormatHud);
		
	if (fifthHighestScore != 0)
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#5] %N - %i", sFormatHud, fifthHighestScoreClient, g_iScore[fifthHighestScoreClient]);
	else
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#5] --- - -", sFormatHud);
		
	if (sixthHighestScore != 0)
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#6] %N - %i", sFormatHud, sixthHighestScoreClient, g_iScore[sixthHighestScoreClient]);
	else
		Format(sFormatHud, sizeof(sFormatHud), "%s\n \n#6] --- - -", sFormatHud);
		
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsValidClient(iClient) && g_iParty[iClient] == iLane)
		{
			char sSteamId[32];
			GetClientAuthId(iClient, AuthId_Steam3, sSteamId, sizeof(sSteamId));
			
			SetHudTextParams(-1.0, 0.19, 15.0, 255, 255, 255, 255);
			ShowSyncHudText(iClient, g_hHud_Frame, sFormatHud);
			
			g_iParty[iClient] = 0;
			g_iReady[iClient] = 0;
			g_iScore[iClient] = 0;
			
			PrintToChat(iClient, "\x07FFFFFFYou left Lane %i.", iLane);
		}
	}
	
	PrintToChatAll("\x07ADFF2FThe session on Lane %i has just ended. The lane is now open.\n%s", iLane, sFormatChat);
}

stock void Bowl_ConnectPins()
{	
	ServerCommand("sv_cheats 1; bot kick all; bot -team red -class medic -name Pin#1; bot -team red -class medic -name Pin#2; bot -team red -class medic -name Pin#3; bot -team red -class medic -name Pin#4; bot -team red -class medic -name Pin#5; bot -team red -class medic -name Pin#6;");
	ServerCommand("bot -team red -class medic -name Pin#7; bot -team red -class medic -name Pin#8; bot -team red -class medic -name Pin#9; bot -team red -class medic -name Pin#10");
	
	ServerCommand("bot -team red -class medic -name Pin#11; bot -team red -class medic -name Pin#12; bot -team red -class medic -name Pin#13; bot -team red -class medic -name Pin#14; bot -team red -class medic -name Pin#15; bot -team red -class medic -name Pin#16;");
	ServerCommand("bot -team red -class medic -name Pin#17; bot -team red -class medic -name Pin#18; bot -team red -class medic -name Pin#19; bot -team red -class medic -name Pin#20; sv_cheats 0");
}

stock void TeleportPins(int iLane)
{
	switch (iLane)
	{
		case 1:
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					if (GetClientTeam(i) == view_as<int>(TFTeam_Spectator))
					{
						char sName[MAX_NAME_LENGTH];
						GetClientName(i, sName, sizeof(sName));
						
						if (StrEqual(sName, "Pin#1") || StrEqual(sName, "Pin#2") || StrEqual(sName, "Pin#3") || StrEqual(sName, "Pin#4") || StrEqual(sName, "Pin#5") || StrEqual(sName, "Pin#6") || StrEqual(sName, "Pin#7") || StrEqual(sName, "Pin#8") || StrEqual(sName, "Pin#9") || StrEqual(sName, "Pin#10"))
						{
							ChangeClientTeam(i, 2);
							TF2_RespawnPlayer(i);
						}
					}
				}
			}
			
			float
				flPos[3],
				flAngle[3];
				
			int
				iPin;
				
			flAngle[0] = g_sLane1_AnglePos[0];
			flAngle[1] = g_sLane1_AnglePos[1];
			flAngle[2] = g_sLane1_AnglePos[2];
			
			flPos[0] = g_sLane1_Pin1Pos[0];
			flPos[1] = g_sLane1_Pin1Pos[1];
			flPos[2] = g_sLane1_Pin1Pos[2];
			iPin = FindTargetByName("Pin#1");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
			
			flPos[0] = g_sLane1_Pin2Pos[0];
			flPos[1] = g_sLane1_Pin2Pos[1];
			flPos[2] = g_sLane1_Pin2Pos[2];
			iPin = FindTargetByName("Pin#2");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane1_Pin3Pos[0];
			flPos[1] = g_sLane1_Pin3Pos[1];
			flPos[2] = g_sLane1_Pin3Pos[2];
			iPin = FindTargetByName("Pin#3");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane1_Pin4Pos[0];
			flPos[1] = g_sLane1_Pin4Pos[1];
			flPos[2] = g_sLane1_Pin4Pos[2];
			iPin = FindTargetByName("Pin#4");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane1_Pin5Pos[0];
			flPos[1] = g_sLane1_Pin5Pos[1];
			flPos[2] = g_sLane1_Pin5Pos[2];
			iPin = FindTargetByName("Pin#5");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane1_Pin6Pos[0];
			flPos[1] = g_sLane1_Pin6Pos[1];
			flPos[2] = g_sLane1_Pin6Pos[2];
			iPin = FindTargetByName("Pin#6");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane1_Pin7Pos[0];
			flPos[1] = g_sLane1_Pin7Pos[1];
			flPos[2] = g_sLane1_Pin7Pos[2];
			iPin = FindTargetByName("Pin#7");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane1_Pin8Pos[0];
			flPos[1] = g_sLane1_Pin8Pos[1];
			flPos[2] = g_sLane1_Pin8Pos[2];
			iPin = FindTargetByName("Pin#8");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane1_Pin9Pos[0];
			flPos[1] = g_sLane1_Pin9Pos[1];
			flPos[2] = g_sLane1_Pin9Pos[2];
			iPin = FindTargetByName("Pin#9");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane1_Pin10Pos[0];
			flPos[1] = g_sLane1_Pin10Pos[1];
			flPos[2] = g_sLane1_Pin10Pos[2];
			iPin = FindTargetByName("Pin#10");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
		}
		
		case 2:
		{
			for (int i = 1; i <= MaxClients; i++)
			{
				if (IsValidClient(i))
				{
					if (GetClientTeam(i) == view_as<int>(TFTeam_Spectator))
					{
						char sName[MAX_NAME_LENGTH];
						GetClientName(i, sName, sizeof(sName));
						
						if (StrEqual(sName, "Pin#11") || StrEqual(sName, "Pin#12") || StrEqual(sName, "Pin#13") || StrEqual(sName, "Pin#14") || StrEqual(sName, "Pin#15") || StrEqual(sName, "Pin#16") || StrEqual(sName, "Pin#17") || StrEqual(sName, "Pin#18") || StrEqual(sName, "Pin#19") || StrEqual(sName, "Pin#20"))
						{
							ChangeClientTeam(i, 2);
							TF2_RespawnPlayer(i);
						}
					}
				}
			}
			
			float
				flPos[3],
				flAngle[3];
				
			int
				iPin;
				
			flAngle[0] = g_sLane2_AnglePos[0];
			flAngle[1] = g_sLane2_AnglePos[1];
			flAngle[2] = g_sLane2_AnglePos[2];
			
			flPos[0] = g_sLane2_Pin1Pos[0];
			flPos[1] = g_sLane2_Pin1Pos[1];
			flPos[2] = g_sLane2_Pin1Pos[2];
			iPin = FindTargetByName("Pin#11");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin2Pos[0];
			flPos[1] = g_sLane2_Pin2Pos[1];
			flPos[2] = g_sLane2_Pin2Pos[2];
			iPin = FindTargetByName("Pin#12");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin3Pos[0];
			flPos[1] = g_sLane2_Pin3Pos[1];
			flPos[2] = g_sLane2_Pin3Pos[2];
			iPin = FindTargetByName("Pin#13");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin4Pos[0];
			flPos[1] = g_sLane2_Pin4Pos[1];
			flPos[2] = g_sLane2_Pin4Pos[2];
			iPin = FindTargetByName("Pin#14");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin5Pos[0];
			flPos[1] = g_sLane2_Pin5Pos[1];
			flPos[2] = g_sLane2_Pin5Pos[2];
			iPin = FindTargetByName("Pin#15");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin6Pos[0];
			flPos[1] = g_sLane2_Pin6Pos[1];
			flPos[2] = g_sLane2_Pin6Pos[2];
			iPin = FindTargetByName("Pin#16");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin7Pos[0];
			flPos[1] = g_sLane2_Pin7Pos[1];
			flPos[2] = g_sLane2_Pin7Pos[2];
			iPin = FindTargetByName("Pin#17");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin8Pos[0];
			flPos[1] = g_sLane2_Pin8Pos[1];
			flPos[2] = g_sLane2_Pin8Pos[2];
			iPin = FindTargetByName("Pin#18");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin9Pos[0];
			flPos[1] = g_sLane2_Pin9Pos[1];
			flPos[2] = g_sLane2_Pin9Pos[2];
			iPin = FindTargetByName("Pin#19");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
			flPos[0] = g_sLane2_Pin10Pos[0];
			flPos[1] = g_sLane2_Pin10Pos[1];
			flPos[2] = g_sLane2_Pin10Pos[2];
			iPin = FindTargetByName("Pin#20");
			if (iPin > 0)
				TeleportEntity(iPin, flPos, flAngle, NULL_VECTOR);
				
		}
	}
}

stock bool Bowl_CheckPins(int iLane)
{
	int iPin;
	char sPin[32];
	
	switch (iLane)
	{
		case 1:
		{
			for (int i = 1; i <= 10; i++)
			{
				Format(sPin, sizeof(sPin), "Pin#%i", i);
				iPin = FindTargetByName(sPin);
				if (iPin == 0 || (iPin > 0 && GetClientTeam(iPin) != view_as<int>(TFTeam_Spectator)))
					return false;
			}
		}
		
		case 2:
		{
			for (int i = 11; i <= 20; i++)
			{
				Format(sPin, sizeof(sPin), "Pin#%i", i);
				iPin = FindTargetByName(sPin);
				if (iPin == 0 || (iPin > 0 && GetClientTeam(iPin) != view_as<int>(TFTeam_Spectator)))
					return false;
			}
		}
	}
	
	return true;
}

stock void PrecacheServer()
{
	char sFormat[PLATFORM_MAX_PATH];
	
	Format(sFormat, sizeof(sFormat), "sound/%s", SOUND_ROLL);
	AddFileToDownloadsTable(sFormat);
	
	Format(sFormat, sizeof(sFormat), "sound/%s", SOUND_HIT);
	AddFileToDownloadsTable(sFormat);
	
	PrecacheSound(SOUND_HIT, true);
	PrecacheSound(SOUND_ROLL, true);
}

stock void StripWeapons(int iClient)
{
	for (int i = 0; i <= 5; i++)
		TF2_RemoveWeaponSlot(iClient, i);
}

stock int FindTargetByName(char[] name)
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsValidClient(iClient))
		{
			if (IsFakeClient(iClient))
			{
				char sName[MAX_NAME_LENGTH];
				GetClientName(iClient, sName, sizeof(sName));
				
				if (StrEqual(sName, name))
					return iClient;
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