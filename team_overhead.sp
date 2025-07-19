#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.0"
#define SPRITE_MODEL "materials/sprites/team.vmt"
#define SPRITE_SCALE 0.05
#define SPRITE_HEIGHT_OFFSET 80.0

// Edict flags for transmission control
#define FL_EDICT_FULLCHECK    (0<<0)  // call ShouldTransmit() each time
#define FL_EDICT_ALWAYS       (1<<3)  // always transmit this entity
#define FL_EDICT_DONTSEND     (1<<4)  // don't transmit this entity
#define FL_EDICT_PVSCHECK     (1<<5)  // always transmit entity, but cull against PVS

int g_iSpriteIndex = -1;
int g_iPlayerSprites[MAXPLAYERS + 1] = {-1, ...};
bool g_bSpritesDisabled[MAXPLAYERS + 1] = {false, ...};

public Plugin myinfo = 
{
    name = "Team Overhead",
    author = "rcnoob",
    description = "Shows sprites above teammates heads",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_team", Event_PlayerTeam);
    
    RegConsoleCmd("sm_togglesprites", Command_DisableSprites, "Toggle teammate sprites on/off");
    RegConsoleCmd("togglesprites", Command_DisableSprites, "Toggle teammate sprites on/off");
}

public void OnPluginEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        RemovePlayerSprite(i);
    }
}

public void OnMapStart()
{
    g_iSpriteIndex = PrecacheModel(SPRITE_MODEL);
    
    AddFileToDownloadsTable("materials/sprites/team.vmt");
    AddFileToDownloadsTable("materials/sprites/team.vtf");
    
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iPlayerSprites[i] = -1;
        g_bSpritesDisabled[i] = false;
    }
}

public void OnClientDisconnect(int client)
{
    RemovePlayerSprite(client);
    g_bSpritesDisabled[client] = false;
}

public void OnGameFrame()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidClient(client) && IsPlayerAlive(client) && g_iPlayerSprites[client] != -1)
        {
            UpdateSpritePosition(client);
        }
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client))
    {
        CreateTimer(0.5, Timer_CreateSprite, GetClientUserId(client));
    }
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client))
    {
        RemovePlayerSprite(client);
    }
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidClient(client))
    {
        RemovePlayerSprite(client);
        CreateTimer(1.0, Timer_CreateSprite, GetClientUserId(client));
    }
}

public Action Timer_CreateSprite(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidClient(client) && IsPlayerAlive(client))
    {
        CreatePlayerSprite(client);
    }
    return Plugin_Stop;
}

void CreatePlayerSprite(int client)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
        return;
    
    RemovePlayerSprite(client);
    
    float pos[3];
    GetClientAbsOrigin(client, pos);
    pos[2] += SPRITE_HEIGHT_OFFSET;
    
    int sprite = CreateEntityByName("env_sprite");
    if (sprite == -1)
        return;
    
    DispatchKeyValue(sprite, "model", SPRITE_MODEL);
    DispatchKeyValueFloat(sprite, "scale", SPRITE_SCALE);
    DispatchKeyValue(sprite, "rendermode", "9");
    DispatchKeyValue(sprite, "renderamt", "255");
    DispatchKeyValue(sprite, "spawnflags", "1");
    
    DispatchSpawn(sprite);
    TeleportEntity(sprite, pos, NULL_VECTOR, NULL_VECTOR);
    
    SetEdictFlags(sprite, (GetEdictFlags(sprite) & ~FL_EDICT_ALWAYS));
    
    SDKHook(sprite, SDKHook_SetTransmit, Hook_SpriteTransmit);
    
    g_iPlayerSprites[client] = EntIndexToEntRef(sprite);
}

void RemovePlayerSprite(int client)
{
    if (g_iPlayerSprites[client] != -1)
    {
        int sprite = EntRefToEntIndex(g_iPlayerSprites[client]);
        if (IsValidEntity(sprite))
        {
            SDKUnhook(sprite, SDKHook_SetTransmit, Hook_SpriteTransmit);
            AcceptEntityInput(sprite, "Kill");
        }
        g_iPlayerSprites[client] = -1;
    }
}

void UpdateSpritePosition(int client)
{
    if (g_iPlayerSprites[client] == -1)
        return;
    
    int sprite = EntRefToEntIndex(g_iPlayerSprites[client]);
    if (!IsValidEntity(sprite))
    {
        g_iPlayerSprites[client] = -1;
        return;
    }
    
    float pos[3];
    GetClientAbsOrigin(client, pos);
    pos[2] += SPRITE_HEIGHT_OFFSET;
    
    TeleportEntity(sprite, pos, NULL_VECTOR, NULL_VECTOR);
}

public Action Hook_SpriteTransmit(int sprite, int client)
{
    if (g_bSpritesDisabled[client])
        return Plugin_Handled;
    
    int spriteOwner = -1;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (g_iPlayerSprites[i] != -1 && EntRefToEntIndex(g_iPlayerSprites[i]) == sprite)
        {
            spriteOwner = i;
            break;
        }
    }
    
    if (spriteOwner == -1 || !IsValidClient(spriteOwner))
        return Plugin_Handled;
    
    if (client == spriteOwner)
        return Plugin_Handled;
    
    if (!IsValidClient(client))
        return Plugin_Handled;
    
    int clientTeam = GetClientTeam(client);
    int ownerTeam = GetClientTeam(spriteOwner);
    
    if (clientTeam == ownerTeam && clientTeam > CS_TEAM_SPECTATOR)
        return Plugin_Continue;
    
    return Plugin_Handled;
}

public Action Command_DisableSprites(int client, int args)
{
    if (!IsValidClient(client))
        return Plugin_Handled;
    
    g_bSpritesDisabled[client] = !g_bSpritesDisabled[client];
    
    if (g_bSpritesDisabled[client])
    {
        PrintToChat(client, "\x01[Team Overhead] Teammate sprites are now \x02disabled\x01.");
    }
    else
    {
        PrintToChat(client, "\x01[Team Overhead] Teammate sprites are now \x04enabled\x01.");
    }
    
    return Plugin_Handled;
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}