/*
COMPILE OPTIONS
*/

#pragma semicolon 1
#pragma newdecls required

/*
INCLUDES
*/

#include <sourcemod>
#include <sdkhooks>
#include <morecolors>
#include <lololib>

/*
PLUGIN INFO
*/

public Plugin myinfo = 
{
	name			= "Whitelist",
	author			= "Flexlolo",
	description		= "Whitelist plugin with real-time editing",
	version			= "1.0.0",
	url				= "github.com/Flexlolo/"
}

/*
GLOBAL VARIABLES
*/

#define WHITELIST_FILE 					"configs/whitelist.txt"
#define WHITELIST_STEAM_ID_LENGTH	 	32

#define WHITELIST_BLOCK_MESSAGE 		"Not whitelisted"

#define CONSOLE_WHITELIST 				"[Whitelist]"
#define CHAT_WHITELIST 					"\x072f4f4f[\x07ff6347Whitelist\x072f4f4f]:"
#define CHAT_VALUE 						"\x07ff6347"
#define CHAT_SUCCESS 					"\x07FFC0CB"
#define CHAT_ERROR 						"\x07DC143C"

// whitelist
char g_sWhitelist_Path[PLATFORM_MAX_PATH];

bool g_bWhitelist = true;
bool g_bWhitelist_Pause = false;

ArrayList g_hWhitelist;
StringMap g_hWhitelist_Map;

// SteamID check
ArrayList g_hConnect_SteamID;
ArrayList g_hConnect_UserID;

char g_sSteamID[MAXPLAYERS + 1][WHITELIST_STEAM_ID_LENGTH];
int g_iUserID[MAXPLAYERS + 1];

/*
NATIVES AND FORWARDS
*/

public void OnPluginStart()
{
	// Arrays
	g_hWhitelist 		= new ArrayList(WHITELIST_STEAM_ID_LENGTH);
	g_hWhitelist_Map 	= new StringMap();
	g_hConnect_SteamID 	= new ArrayList(WHITELIST_STEAM_ID_LENGTH);
	g_hConnect_UserID 	= new ArrayList(1);

	// Events
	HookEvent("player_connect_client", Event_PlayerConnect, EventHookMode_Post);

	// Commands
	RegAdminCmd("sm_whitelist", Command_Whitelist, ADMFLAG_ROOT, "Manage whitelist");

	// Whitelist initialization
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client))
		{
			Connect_UpdateInfo(client);
		}
	}

	BuildPath(Path_SM, g_sWhitelist_Path, sizeof(g_sWhitelist_Path), WHITELIST_FILE);

	Whitelist_Reload();
}

public void OnMapStart()
{
	if (g_bWhitelist_Pause)
	{
		Whitelist_Pause_Toggle(false);
		Whitelist_Check();
	}
}

// This is earliest function that is called when client connects
// Here we get client steamid provided on connection
public Action Event_PlayerConnect(Handle event, const char[] name, bool dontBroadcast)
{
	int userid = GetEventInt(event, "userid");

	char sSteamID[WHITELIST_STEAM_ID_LENGTH];
	GetEventString(event, "networkid", sSteamID, sizeof(sSteamID));

	int size = g_hConnect_SteamID.Length;

	g_hConnect_SteamID.Resize(size + 1);
	g_hConnect_UserID.Resize(size + 1);

	g_hConnect_SteamID.SetString(size, sSteamID);
	g_hConnect_UserID.Set(size, userid);

	return Plugin_Continue;
}

// OnClientConnect is called to ask if player can connect
// Here we check if player is whitelisted
public bool OnClientConnect(int client, char[] RejectMessage, int maxlength)
{
	Connect_UpdateInfo(client);

	int size = g_hConnect_UserID.Length;
	int line = -1;

	for (int i; i < size; i++)
	{
		if (g_iUserID[client] == g_hConnect_UserID.Get(i))
		{
			line = i;
			break;
		}
	}

	if (!IsFakeClient(client))
	{
		if (line != -1)
		{
			g_hConnect_SteamID.GetString(line, g_sSteamID[client], sizeof(g_sSteamID[]));
			lolo_SteamID2(g_sSteamID[client], sizeof(g_sSteamID[]), g_sSteamID[client]);

			g_hConnect_SteamID.Erase(line);
			g_hConnect_UserID.Erase(line);
		}

		if (g_bWhitelist)
		{
			if (g_bWhitelist_Pause)
			{
				return true;
			}
			else if (Whitelist_Access_SteamID(g_sSteamID[client]))
			{
				return true;
			}
			else 
			{
				Format(RejectMessage, maxlength, WHITELIST_BLOCK_MESSAGE);
				return false;
			}
		}
		else
		{
			return true;
		}
	}
	else
	{
		if (line != -1)
		{
			g_hConnect_SteamID.GetString(line, g_sSteamID[client], sizeof(g_sSteamID[]));

			g_hConnect_SteamID.Erase(line);
			g_hConnect_UserID.Erase(line);
		}

		return true;
	}
}

stock void Connect_UpdateInfo(int client)
{
	g_iUserID[client] = GetClientUserId(client);
	GetClientAuthId(client, AuthId_Steam2, g_sSteamID[client], sizeof(g_sSteamID[]));
}

/*
COMMANDS
*/

public Action Command_Whitelist(int client, int args)
{
	if (args)
	{
		char sArgs[192];
		GetCmdArgString(sArgs, sizeof(sArgs));

		if (strlen(sArgs))
		{

			if (lolo_String_Startswith(sArgs, "on ", true) || StrEqual(sArgs, "on", true))
			{
				Whitelist_Toggle(true);

				if (client)
				{
					CPrintToChat(client, "%s %sEnabled.", CHAT_WHITELIST, CHAT_SUCCESS);
				}
				else
				{
					PrintToServer("%s Enabled.", CONSOLE_WHITELIST);
				}
			}
			else if (lolo_String_Startswith(sArgs, "off ", true) || StrEqual(sArgs, "off", true))
			{
				Whitelist_Toggle(false);

				if (client)
				{
					CPrintToChat(client, "%s %sDisabled.", CHAT_WHITELIST, CHAT_SUCCESS);
				}
				else
				{
					PrintToServer("%s Disabled.", CONSOLE_WHITELIST);
				}
			}
			else if (lolo_String_Startswith(sArgs, "reload ", true) || StrEqual(sArgs, "reload", true))
			{
				Whitelist_Reload();

				if (client)
				{
					CPrintToChat(client, "%s %sReloaded.", CHAT_WHITELIST, CHAT_SUCCESS);
				}
				else
				{
					PrintToServer("%s Reloaded.", CONSOLE_WHITELIST);
				}
			}
			else if (lolo_String_Startswith(sArgs, "unpause ", true) || StrEqual(sArgs, "unpause", true))
			{
				Whitelist_Pause_Toggle(false);

				if (client)
				{
					CPrintToChat(client, "%s %sUnpaused.", CHAT_WHITELIST, CHAT_SUCCESS);
				}
				else
				{
					PrintToServer("%s Unpaused.", CONSOLE_WHITELIST);
				}
			}
			else if (lolo_String_Startswith(sArgs, "check ", true) || StrEqual(sArgs, "check", true))
			{
				Whitelist_Check();

				if (client)
				{
					CPrintToChat(client, "%s %sAll players were checked.", CHAT_WHITELIST, CHAT_SUCCESS);
				}
				else
				{
					PrintToServer("%s All players were checked.", CONSOLE_WHITELIST);
				}
			}
			else if (lolo_String_Startswith(sArgs, "add ", true))
			{
				Whitelist_Change(client, sArgs);
			}
			else if (lolo_String_Startswith(sArgs, "remove ", true))
			{
				Whitelist_Change(client, sArgs);
			}
			else if (lolo_String_Startswith(sArgs, "pause ", true) || StrEqual(sArgs, "pause", true))
			{
				Whitelist_Pause_Toggle(true);

				if (client)
				{
					CPrintToChat(client, "%s %sPaused.", CHAT_WHITELIST, CHAT_SUCCESS);
				}
				else
				{
					PrintToServer("%s Paused.", CONSOLE_WHITELIST);
				}
			}
			else if (lolo_String_Startswith(sArgs, "list", true))
			{
				Whitelist_List(client);
			}
			else if (lolo_String_Startswith(sArgs, "help", true))
			{
				Whitelist_Help(client);
			}
		}
	}
	else
	{
		Whitelist_Help(client);
	}
	

	return Plugin_Handled;
}

// whitelist help
stock void Whitelist_Help(int client)
{
	char[] usage = "usage:\n" ...
					"    sm_whitelist <on/off>  - Toggle whitelist\n" ...
					"    sm_whitelist reload  - Reload whitelist\n" ...
					"    sm_whitelist <pause/unpause>  - Toggle pause\n" ...
					"    sm_whitelist check  - Initiate whitelist check\n" ...
					"    sm_whitelist add <target> (<name>)  - Whitelist player\n" ...
					"    sm_whitelist remove <target>  - Unwhitelist player\n" ...
					"    sm_whitelist list - Generate list\n";

	if (client)
	{
		CPrintToChat(client, "%s %sCheck console for usage.", CHAT_WHITELIST, CHAT_SUCCESS);
		PrintToConsole(client, usage);
	}
	else
	{
		PrintToServer(usage);
	}
}

// whitelist <add/remove> <target> <name (on add)>
stock void Whitelist_Change(int client, const char[] sArgs)
{
	if (StrContains(sArgs, " ", false) != -1)
	{
		char sArg[3][64];
		ExplodeString(sArgs, " ", sArg, sizeof(sArg), sizeof(sArg[]), true);

		if (strlen(sArg[0]))
		{
			bool add;

			if (StrEqual(sArg[0], "add", true))
			{
				add = true;
			}

			if (strlen(sArg[1]))
			{
				ArrayList hTargets = lolo_Target_Process(client, sArg[1]);

				if (hTargets != null)
				{
					if (hTargets.Length == 1)
					{
						int target = hTargets.Get(0);

						GetClientAuthId(target, AuthId_Steam2, sArg[1], sizeof(sArg[]));

						if (add)
						{
							if (Whitelist_Access_SteamID(sArg[1]))
							{
								if (client)
								{
									CPrintToChat(client, "%s %sPlayer already whitelisted.", CHAT_WHITELIST, CHAT_ERROR);
								}
								else
								{
									PrintToServer("%s Player already whitelisted.", CONSOLE_WHITELIST);
								}
							}
							else
							{
								if (!strlen(sArg[2]))
								{
									GetClientName(target, sArg[2], sizeof(sArg[]));
								}

								Whitelist_Add(client, sArg[1], sArg[2]);

								if (client)
								{
									CPrintToChat(client, "%s %sPlayer added to whitelist. (%s%s %s| %s%s%s)", CHAT_WHITELIST, CHAT_SUCCESS, 
																											CHAT_VALUE, sArg[1], CHAT_SUCCESS, 
																											CHAT_VALUE, sArg[2], CHAT_SUCCESS);
								}
								else
								{
									PrintToServer("%s Player added to whitelist. (%s | %s)", CONSOLE_WHITELIST, sArg[1], sArg[2]);
								}
							}
						}
						else
						{
							if (Whitelist_Access_SteamID(sArg[1]))
							{
								Whitelist_Remove(sArg[1]);

								if (client)
								{
									CPrintToChat(client, "%s %sPlayer deleted from whitelist. (%s%s%s)", CHAT_WHITELIST, CHAT_SUCCESS, 
																										CHAT_VALUE, sArg[1], CHAT_SUCCESS);
								}
								else
								{
									PrintToServer("%s Player deleted from whitelist. (%s)", CONSOLE_WHITELIST, sArg[1]);
								}
							}
							else
							{
								if (client)
								{
									CPrintToChat(client, "%s %sPlayer is not whitelisted.", CHAT_WHITELIST, CHAT_ERROR);
								}
								else
								{
									PrintToServer("%s Player is not whitelisted.", CONSOLE_WHITELIST);
								}
							}
						}
					}
					else if (hTargets.Length == 0)
					{
						if (lolo_String_Startswith(sArg[1], "#STEAM", true))
						{
							if (add)
							{
								if (Whitelist_Access_SteamID(sArg[1][1]))
								{
									if (client)
									{
										CPrintToChat(client, "%s %sPlayer already whitelisted.", CHAT_WHITELIST, CHAT_ERROR);
									}
									else
									{
										PrintToServer("%s Player already whitelisted.", CONSOLE_WHITELIST);
									}
								}
								else
								{
									if (strlen(sArg[2]))
									{
										Whitelist_Add(client, sArg[1][1], sArg[2]);

										if (client)
										{
											CPrintToChat(client, "%s %sPlayer added to whitelist. (%s%s %s| %s%s%s)", CHAT_WHITELIST, CHAT_SUCCESS, 
																													CHAT_VALUE, sArg[1][1], CHAT_SUCCESS, 
																													CHAT_VALUE, sArg[2], CHAT_SUCCESS);
										}
										else
										{
											PrintToServer("%s Player added to whitelist. (%s | %s)", CONSOLE_WHITELIST, sArg[1][1], sArg[2]);
										}
									}
									else
									{
										if (client)
										{
											CPrintToChat(client, "%s %sInvalid command format.", CHAT_WHITELIST, CHAT_ERROR);
										}
										else
										{
											PrintToServer("%s Invalid command format.", CONSOLE_WHITELIST);
										}
									}
								}
							}
							else
							{
								if (Whitelist_Access_SteamID(sArg[1][1]))
								{
									Whitelist_Remove(sArg[1][1]);

									if (client)
									{
										CPrintToChat(client, "%s %sPlayer deleted from whitelist. (%s%s%s)", CHAT_WHITELIST, CHAT_SUCCESS, 
																											CHAT_VALUE, sArg[1][1], CHAT_SUCCESS);
									}
									else
									{
										PrintToServer("%s Player deleted from whitelist. (%s)", CONSOLE_WHITELIST, sArg[1][1]);
									}
								}
								else
								{
									if (client)
									{
										CPrintToChat(client, "%s %sPlayer is not whitelisted.", CHAT_WHITELIST, CHAT_ERROR);
									}
									else
									{
										PrintToServer("%s Player is not whitelisted.", CONSOLE_WHITELIST);
									}
								}
							}
						}
						else
						{
							if (client)
							{
								CPrintToChat(client, "%s %sInvalid target.", CHAT_WHITELIST, CHAT_ERROR);
							}
							else
							{
								PrintToServer("%s Invalid target.", CONSOLE_WHITELIST);
							}
						}
					}
					else
					{
						if (client)
						{
							CPrintToChat(client, "%s %sMultiple targets.", CHAT_WHITELIST, CHAT_ERROR);
						}
						else
						{
							PrintToServer("%s Multiple targets.", CONSOLE_WHITELIST);
						}
					}
				}
				else
				{
					if (client)
					{
						CPrintToChat(client, "%s %sInvalid target.", CHAT_WHITELIST, CHAT_ERROR);
					}
					else
					{
						PrintToServer("%s Invalid target.", CONSOLE_WHITELIST);
					}
				}

				lolo_CloseHandle(hTargets);
			}
			else
			{
				if (client)
				{
					CPrintToChat(client, "%s %sInvalid command format.", CHAT_WHITELIST, CHAT_ERROR);
				}
				else
				{
					PrintToServer("%s Invalid command format.", CONSOLE_WHITELIST);
				}
			}
		}
	}
}

// whitelist list
stock void Whitelist_List(int client)
{
	if (!g_hWhitelist.Length)
	{
		if (client)
		{
			CPrintToChat(client, "%s %Whitelist is empty.", CHAT_WHITELIST, CHAT_ERROR);
		}
		else
		{
			PrintToServer("%s Whitelist is empty.", CONSOLE_WHITELIST);
		}

	}
	else
	{
		if (client)
		{
			CPrintToChat(client, "%s %sCheck console for output.", CHAT_WHITELIST, CHAT_SUCCESS);
			PrintToConsole(client, "Whitelist:");
		}
		else
		{
			PrintToServer("Whitelist:");
		}

		char line[WHITELIST_STEAM_ID_LENGTH];

		for (int i; i < g_hWhitelist.Length; i++)
		{
			g_hWhitelist.GetString(i, line, sizeof(line));

			if (client)
			{
				PrintToConsole(client, line);
			}
			else
			{
				PrintToServer(line);
			}
		}
	}
}

// Sub-commands implementation
public void Whitelist_Toggle(bool toggle)
{
	bool old = g_bWhitelist;

	g_bWhitelist = toggle;
	
	if (old != toggle)
	{
		if (g_bWhitelist && !g_bWhitelist_Pause)
		{
			Whitelist_Check();
		}
	}
}

public bool Whitelist_Access(int client)
{
	return Whitelist_Access_SteamID(g_sSteamID[client]);
}

public bool Whitelist_Access_SteamID(const char[] sSteamID)
{
	int result;

	if (g_hWhitelist_Map.GetValue(sSteamID, result))
	{
		return true;
	}

	return false;
}

public void Whitelist_Add(int client, const char[] sSteamID, const char[] sName)
{
	if (FileExists(g_sWhitelist_Path))
	{
		File hFile = OpenFile(g_sWhitelist_Path, "a+");

		if (hFile != null)
		{
			char sDate[64];
			FormatTime(sDate, sizeof(sDate), "%Y_%m_%d_%H_%M", GetTime());

			char sMap[64];
			GetCurrentMap(sMap, sizeof(sMap));

			if (client)
			{
				char sAdminName[32];
				GetClientName(client, sAdminName, sizeof(sAdminName));

				char sAdminSteamID[WHITELIST_STEAM_ID_LENGTH];
				GetClientAuthId(client, AuthId_Steam2, sAdminSteamID, sizeof(sAdminSteamID));

				hFile.WriteLine("//%s - added by %s (%s) at %s - %s", sName, sAdminName, sAdminSteamID, sMap, sDate);
			}
			else
			{
				hFile.WriteLine("//%s - added from server console at %s - %s", sName, sMap, sDate);
			}

			hFile.WriteLine("%s;", sSteamID);
		}

		lolo_CloseHandle(hFile);

		Whitelist_Insert(sSteamID);
	}
}

public void Whitelist_Remove(const char[] sSteamID)
{
	if (FileExists(g_sWhitelist_Path))
	{
		char sWhitelist_Path_Old[PLATFORM_MAX_PATH];
		Format(sWhitelist_Path_Old, sizeof(sWhitelist_Path_Old), "%s.old", g_sWhitelist_Path);

		RenameFile(sWhitelist_Path_Old, g_sWhitelist_Path);

		File hFileOld = OpenFile(sWhitelist_Path_Old, "r+");
		File hFile = OpenFile(g_sWhitelist_Path, "w+");

		if (hFileOld == null || hFile == null) return;

		char line[128];
		char sSteamID2[WHITELIST_STEAM_ID_LENGTH];

		int size;
			
		while (!hFileOld.EndOfFile() && hFileOld.ReadLine(line, sizeof(line)))
		{
			bool modified = false;

			if (!lolo_String_Startswith(line, "//", false))
			{
				size = strlen(line);

				if (size)
				{
					int newline = StrContains(line, "\n", false);

					if (newline != -1) size = newline + 1;
					else size += 1;
				}

				if (size)
				{
					if (size > sizeof(sSteamID2))
					{
						size = sizeof(sSteamID2);
					}

					strcopy(sSteamID2, size, line);
				}

				if (StrEqual(sSteamID, sSteamID2))
				{
					char write[WHITELIST_STEAM_ID_LENGTH + 3];
					Format(write, sizeof(write), "// %s", sSteamID2);
					hFile.WriteLine(write);
					modified = true;
				}
			}

			if (!modified)
			{
				if (line[strlen(line)-1] == '\n')
				{
					strcopy(line, strlen(line), line);
				}

				hFile.WriteLine(line);
			}
		}

		lolo_CloseHandle(hFile);
		lolo_CloseHandle(hFileOld);

		DeleteFile(sWhitelist_Path_Old);
	}

	Whitelist_Delete(sSteamID);
}

public void Whitelist_Pause_Toggle(bool toggle)
{
	g_bWhitelist_Pause = toggle;
}

public void Whitelist_Check()
{
	if (g_bWhitelist)
	{
		for (int client = 1; client <= MaxClients; client++)
		{
			if (IsClientConnected(client))
			{
				if (!IsFakeClient(client))
				{
					if (!Whitelist_Access(client))
					{
						KickClient(client, WHITELIST_BLOCK_MESSAGE);
					}
				}
			}
		}
	}
}

public void Whitelist_Reload()
{
	g_hWhitelist.Clear();
	g_hWhitelist_Map.Clear();

	Whitelist_Parse();

	if (g_bWhitelist && !g_bWhitelist_Pause)
	{
		Whitelist_Check();
	}
}

public void Whitelist_Parse()
{
	if (FileExists(g_sWhitelist_Path))
	{
		File hFile = OpenFile(g_sWhitelist_Path, "r");

		if (hFile == null) return;

		char line[128];
		char sSteamID[WHITELIST_STEAM_ID_LENGTH];

		int size;
		Regex r = new Regex("^STEAM_");

		while (!hFile.EndOfFile() && hFile.ReadLine(line, sizeof(line)))
		{
			if (lolo_String_Startswith(line, "//", false)) continue;
			if (r.Match(line) < 1) continue;

			size = strlen(line);

			if (size)
			{
				int newline = StrContains(line, "\n", false);

				if (newline != -1) size = newline + 1;
				else size += 1;
			}

			if (size)
			{
				if (size > sizeof(sSteamID))
				{
					size = sizeof(sSteamID);
				}

				strcopy(sSteamID, size, line);

				Whitelist_Insert(sSteamID);
			}		
		}

		lolo_CloseHandle(hFile);
	}
}

public void Whitelist_Insert(const char[] sSteamID)
{
	int size = g_hWhitelist.Length;

	g_hWhitelist.Resize(size + 1);
	g_hWhitelist.SetString(size, sSteamID);

	g_hWhitelist_Map.SetValue(sSteamID, 1, true);
}

public int Whitelist_SteamID_Index(const char[] sSteamID)
{
	if (Whitelist_Access_SteamID(sSteamID))
	{
		char compare[WHITELIST_STEAM_ID_LENGTH];

		for (int i; i < g_hWhitelist.Length; i++)
		{
			g_hWhitelist.GetString(i, compare, sizeof(compare));

			if (StrEqual(sSteamID, compare))
			{
				return i;
			}
		}	
	}

	return -1;
}

public void Whitelist_Delete(const char[] sSteamID)
{
	// Delete
	int index = Whitelist_SteamID_Index(sSteamID);

	if (index != -1)
	{
		g_hWhitelist.Erase(index);
		g_hWhitelist_Map.Remove(sSteamID);
	}

	// In case player is on server we also check for that.
	Whitelist_Check();
}