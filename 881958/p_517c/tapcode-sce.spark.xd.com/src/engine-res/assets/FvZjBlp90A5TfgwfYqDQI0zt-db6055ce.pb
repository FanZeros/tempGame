
Ãb
TSLobbyServer.protoCEProto.TSLobbyServer"V
LobbyServerMessage

request_id (R	requestId!
message_body (RmessageBody"f
RequestAcceptInvite

invite_key (	R	inviteKey
agree (Ragree
password (	Rpassword"5
ResponseAcceptInvite

error_code (R	errorCode"•
RequestTeamCreate
	max_count (RmaxCount(
team_custom_data (RteamCustomData

is_private (R	isPrivate
password (	Rpassword"L
ResponseTeamCreate

error_code (R	errorCode
team_id (RteamId"t
RequestTeamInvite
user_id (RuserId,
invite_custom_data (RinviteCustomData
timeout (Rtimeout"K
ResponseTeamInvite

error_code (R	errorCode
result (Rresult"{
RequestTeamList
map_name (	RmapName
number (Rnumber
mode (	Rmode!
find_private (RfindPrivate"Ÿ
TeamInfo
id (Rid
owner_id (RownerId
	team_name (	RteamName
	team_type (RteamType
map_name (	RmapName

user_count (R	userCount$
max_user_count (RmaxUserCount
password (	Rpassword
mode	 (	Rmode
	mode_args
 (	RmodeArgs
status (Rstatus(
team_custom_data (RteamCustomData 
in_game_time (R
inGameTime

is_private (R	isPrivate"P
ResponseTeamList<
	team_list (2.CEProto.TSLobbyServer.TeamInfoRteamList"|
RequestModifyTeamInfo(
team_custom_data (RteamCustomData

is_private (R	isPrivate
password (	Rpassword"€
ResponseModifyTeamInfo

error_code (R	errorCode

is_private (R	isPrivate(
team_custom_data (RteamCustomData"!
RequestTeamInfo
id (Rid"P
ResponseTeamInfo<
	team_info (2.CEProto.TSLobbyServer.TeamInfoRteamInfo")
NotifyTeamJoin
user_id (RuserId"¸
NotifyTeamInvited
from (Rfrom

invite_key (	R	inviteKey(
team_custom_data (RteamCustomData,
invite_custom_data (RinviteCustomData
timeout (Rtimeout"
RequestTeamLeave"2
ResponseTeamLeave

error_code (R	errorCode"G
NotifyTeamLeave
user_id (RuserId
	is_kicked (RisKicked"W
NotifyTeamCurrentStatus<
team (2(.CEProto.TSLobbyServer.CurrentTeamStatusRteam"
RequestTeamApplyMaster"8
ResponseTeamApplyMaster

error_code (R	errorCode"W
NotifyTeamMasterChanged

old_master (R	oldMaster

new_master (R	newMaster".
RequestTeamKickUser
user_id (RuserId"5
ResponseTeamKickUser

error_code (R	errorCode"h
RequestTeamApplyJoin
	target_id (RtargetId
team_id (RteamId
password (	Rpassword"6
ResponseTeamApplyJoin

error_code (R	errorCode"M
NotifyTeamApplyJoin

request_id (R	requestId
user_id (RuserId"N
RequestTeamJoinAccept
pending_key (	R
pendingKey
agree (Ragree"7
ResponseTeamJoinAccept

error_code (R	errorCode"
RequestTeamTransferMaster";
ResponseTeamTransferMaster

error_code (R	errorCode"
RequestUserCurrentStatus"Ú
LobbyUserInfo
user_id (RuserId
online (Ronline
team_id (RteamId
room_id (RroomId
in_matching (R
inMatching
	in_gaming (RinGaming(
in_middle_gaming (RinMiddleGaming"Ð
CurrentTeamStatus
team_id (RteamIdA
	user_list (2$.CEProto.TSLobbyServer.LobbyUserInfoRuserList
master (Rmaster(
team_custom_data (RteamCustomData

is_private (R	isPrivate"
CurrentRoomStatus"ì
CurrentMatcherStatus
map_name (	RmapName

match_info (R	matchInfo(
operator_user_id (RoperatorUserIdA
	user_list (2$.CEProto.TSLobbyServer.LobbyUserInfoRuserList
	mode_args (RmodeArgs
tag (	Rtag"ø
CurrentGameStatus&
game_session_id (RgameSessionIdA
	user_list (2$.CEProto.TSLobbyServer.LobbyUserInfoRuserList
map_name (	RmapName
create_time (R
createTime
map_kind (RmapKind!
package_type (RpackageType"¼
ResponseUserCurrentStatus8
user (2$.CEProto.TSLobbyServer.LobbyUserInfoRuser<
team (2(.CEProto.TSLobbyServer.CurrentTeamStatusRteam<
room (2(.CEProto.TSLobbyServer.CurrentRoomStatusRroomE
matcher (2+.CEProto.TSLobbyServer.CurrentMatcherStatusRmatcher<
game (2(.CEProto.TSLobbyServer.CurrentGameStatusRgameI
middle_game (2(.CEProto.TSLobbyServer.CurrentGameStatusR
middleGameE
	game_list (2(.CEProto.TSLobbyServer.CurrentGameStatusRgameListR
middle_game_list (2(.CEProto.TSLobbyServer.CurrentGameStatusRmiddleGameList"
RequestGameCanReconnect"½
CanReconnectInfo
map_name (	RmapName!
package_type (RpackageType
map_kind (RmapKind

session_id (R	sessionId
create_time (R
createTime
tag (	Rtag"²
ResponseGameCanReconnect

error_code (R	errorCode
result (Rresult
map_name (	RmapNameD
	info_list (2'.CEProto.TSLobbyServer.CanReconnectInfoRinfoList"5
RequestGameReconnect

session_id (R	sessionId"Ù
ConnectInfo
	server_ip (RserverIp
server_port (R
serverPort&
game_session_id (RgameSessionId
old_room_id (R	oldRoomId
now_room_id (R	nowRoomId
	mode_args (RmodeArgs
map_name (	RmapName!
package_type (RpackageType
map_kind	 (RmapKind
ws_port
 (RwsPort
pod_ip (	RpodIp"š
ResponseGameReconnect

error_code (R	errorCodeE
connect_info (2".CEProto.TSLobbyServer.ConnectInfoRconnectInfo
	login_key (	RloginKey";
RequestGameCancelReconnect

session_id (R	sessionId"<
ResponseGameCancelReconnect

error_code (R	errorCode"¹
NotifyGameStart

error_code (R	errorCodeE
connect_info (2".CEProto.TSLobbyServer.ConnectInfoRconnectInfo
	login_key (	RloginKey$
is_quick_start (RisQuickStart$
middleKeyFull (	RmiddleKeyFull6
use_entrance_connection (RuseEntranceConnection
message_key (R
messageKey"i
RegisterGameParams
map_name (	RmapName
	mode_args (RmodeArgs
	game_mode (RgameMode"
RequestGameStart"
RequestGameQuickStart"A

GameRecord
	user_list (RuserList
winner (Rwinner"]
RequestGameMyRecordListB
record_list (2!.CEProto.TSLobbyServer.GameRecordR
recordList"
RequestGameRecordDetail"
ResponseGameRecordDetail"à
RequestGameMiddleJoin
map_name (	RmapName
	mode_args (RmodeArgs
	game_mode (RgameMode$
is_quick_start (RisQuickStart
map_kind (RmapKind
host_region (	R
hostRegion
tag (	Rtag"V
ResponseGameMiddleJoin

error_code (R	errorCode

middle_key (	R	middleKey"º
RequestMatchStart
map_name (	RmapName

match_info (R	matchInfo
	mode_args (RmodeArgs
	user_list (RuserList
host_region (	R
hostRegion
tag (	Rtag"3
ResponseMatchStart

error_code (R	errorCode"
RequestMatchCancel"4
ResponseMatchCancel

error_code (R	errorCode"ª
NotifyMatchStatusChanged
match_event (R
matchEventN
match_status (2+.CEProto.TSLobbyServer.CurrentMatcherStatusRmatchStatus

error_code (R	errorCode"x
NotifySyncUserGameStatus
	game_type (RgameType
user_id (RuserId&
game_session_id (RgameSessionId"P
NotifySyncUserMatchStatus
user_id (RuserId
matching (Rmatching"9
RequestOtherUserState 
user_id_list (R
userIdList"@
ResponseOtherUserState&
user_state_list (	RuserStateList"?
NotifyKickYouFromBackend#
can_reconnect (RcanReconnect"w
RequestWorldId
map_name (	RmapName

world_type (	R	worldType
world_id (RworldId
env (	Renv"l
ResponseWorldId

error_code (R	errorCode
world_id (RworldId
remote_path (	R
remotePath"Z
RequestPrewarmWorld
world_id (RworldId
env (	Renv
region (	Rregion"V
ResponsePrewarmWorld

error_code (R	errorCode
remote_path (	R
remotePath"i
RequestWorldFinish
map_name (	RmapName

world_type (	R	worldType
world_id (RworldId"O
ResponseWorldFinish

error_code (R	errorCode
world_id (RworldId"Œ
RequestSetRandomTerrainConfig

request_id (R	requestId
map_name (	RmapName

world_type (	R	worldType
data (Rdata"ž
ResponseSetRandomTerrainConfig

request_id (R	requestId
map_name (	RmapName

world_type (	R	worldType#
progress_code (RprogressCode"
NotifyHostDownloadingMap"
RequestTeamStartGame
map_name (	RmapName
	mode_args (RmodeArgs
host_region (	R
hostRegion
tag (	Rtag"6
ResponseTeamStartGame

error_code (R	errorCode*º
LobbyServerMessageType
LOBBYSERVERMESSAGE_MIN€`
REQUEST_TEAM_CREATE`
REQUEST_TEAM_INVITE‚`
REQUEST_ACCEPT_INVITEƒ`
NOTIFY_TEAM_INVITED„`
REQUEST_TEAM_LEAVE…`
REQUEST_TEAM_APPLY_MASTER†`
NOTIFY_TEAM_APPLY_MASTER‡`%
 REQUEST_TEAM_ACCEPT_APPLY_MASTERˆ`
REQUEST_TEAM_KICK_USERŠ`
REQUEST_TEAM_APPLY_JOIN‹`#
REQUEST_TEAM_ACCEPT_APPLY_JOINŒ`
NOTIFY_TEAM_APPLY_JOIN`!
REQUEST_TEAM_TRANSFER_MASTERŽ`
NOTIFY_TEAM_LEAVE`
NOTIFY_TEAM_JOIN`
NOTIFY_TEAM_CURRENT_STATUS‘`
NOTIFY_TEAM_MASTER_CHANGED’`
REQUEST_TEAM_LIST“`
REQUEST_MODIFY_TEAM_INFO”`
REQUEST_TEAM_INFO•`
REQUEST_ROOM_CREAT `
REQUEST_ROOM_JOIN¡`
REQUEST_ROOM_LIST¢`
REQUEST_ROOM_LEAVE£`
REQUEST_ROOM_READY¤`
REQUEST_ROOM_START_GAME¥`
REQUEST_ROOM_INVITE¦`
REQUEST_ROOM_ACCEPT_INVITE§`
NOTIFY_ROOM_ACCEPT¨`
REQUEST_ROOM_APPLY_MASTER©`%
 REQUEST_ROOM_ACCEPT_APPLY_MASTERª`
NOTIFY_ROOM_INFO_CHANGED«` 
REQUEST_USER_CURRENT_STATUSÀ`
REQUEST_GAME_CAN_RECONNECTà`
REQUEST_GAME_RECONNECTá`"
REQUEST_GAME_CANCEL_RECONNECTâ`
NOTIFY_GAME_STARTã`
REQUEST_GAME_STARTä`
REQUEST_GAME_QUICK_STARTå` 
REQUEST_GAME_MY_RECORD_LISTæ`
REQUEST_GAME_RECORD_DETAILç`
REQUEST_GAME_MIDDLE_JOINè` 
NOTIFY_HOST_DOWNLOADING_MAPé`!
NOTIFY_SYNC_USER_GAME_STATUSƒa
REQUEST_OTHER_USER_STATE…a
REQUEST_MATCH_START€a
REQUEST_MATCH_CANCELa 
NOTIFY_MATCH_STATUS_CHANGED‚a"
NOTIFY_SYNC_USER_MATCH_STATUS„a
REQUEST_TEAM_START_GAME†a!
NOTIFY_KICK_YOU_FROM_BACKEND€b
REQUEST_WORLD_IDb
REQUEST_PREWARM_WORLD‚b
REQUEST_WORLD_FINISHƒb&
!REQUEST_SET_RANDOM_TERRAIN_CONFIG„b
LOBBYSERVERMESSAGE_MAXÿc*
InviteErrorCode
	I_SUCCESS 
I_INVALID_USER
I_INVALID_ROOM
I_PENDING_INVITE
I_ROOM_FULL
I_USER_IN_OTHER_ROOM
I_HAS_DISMISSED
I_FROM_NOT_IDLE
I_INVITE_TEAM

I_INVALID_TEAM
I_INVALID_INVITE_TIMEOUT
I_DIFFERENT_TAG*û
AcceptInviteErrorCode

AI_SUCCESS 
AI_INVALID_USER
AI_INVALID_ROOM
AI_ROOM_FULL
AI_ROOM_NOT_IDLE
AI_ALREADY_IN
AI_INVALID_TEAM
AI_INVALID_REQUEST_ID
AI_INVALID_REQUEST_ID_TYPE
AI_INVALID_PASSWORD_ERROR	*E
TeamErrorCode
	T_SUCCESS 
T_TEAM_NOT_FIND
T_NOT_MASTER*8
LeaveTeamErrorCode

LT_SUCCESS 
LT_NOT_IN_ROOM*§
KickUserErrorCode
KUOR_SUCCESS 
KUOR_CANNOT_KICK_SELF
KUOR_INVALID_USER
KURO_NOT_IN_SAME_PLACE
KUOR_ROOM_NOT_IDLE
KUOR_PERMISSION_DENIED*²
TeamApplyJoinErrorCode

AJ_SUCCESS 
AJ_HAS_IN_TEAM
AJ_TARGET_NOT_IN_TEAM
AJ_TARGET_TEAM_NOT_VALID
AJ_TARGET_TEAM_FULL
AJ_PARAM_VALID
AJ_TARGET_USER_NOT_VALID 
AJ_TARGET_NOT_IN_TARGET_TEAM
AJ_TEAM_NOT_ALL_IDLING
AJ_USER_NOT_IDLING	
AJ_TEAM_PASSWORD_ERROR
*)
TeamJoinAcceptErrorCode

JA_SUCCESS *4
ReconnectErrorCode
	R_SUCCESS 
R_GAME_OVER*ç
GameStartErrorCode

SG_SUCCESS 
SG_PLAYER_NOT_READY
SG_HOST_IS_FULL
SG_HOST_NO_RESPONSE
SG_BALANCE_NO_RESPONSE
SG_ROOM_NOT_IDEL
SG_ROOM_OWNER_NOT_ME
SG_ROOM_NOT_EXISTS
SG_HOST_NOT_EXISTS
SG_REGISTER_GAME_FAILED	
SG_USER_HAS_IN_GAME
&
"SG_QUERY_MYSQL_PACKAGE_TYPE_FAILED 
SG_GENERATE_MIDDLE_KEY_FAILD*]
GameStartFromType
GameStartFrom_MYSELF 
GameStartFrom_TEAM
GameStartFrom_ROOM*„
MatchErrorCode
	M_SUCCESS 
M_INVALID_TEAM
M_ALREADY_MATCHING
M_AMS_TIMEOUT
M_NOT_GAME_CHANNEL
M_USER_IN_GAMING
M_SELF_NOT_IN_USER_LIST
M_OTHER_USER_NOT_IDLE
M_OTHER_USER_NOT_IN_TEAM 
M_USE_USER_LIST_WITHOUT_TEAM	*o
CancelMatchErrorCode

CM_SUCCESS 
CM_INVALID_TEAM
CM_ALREADY_CANCEL_MATCHING
CM_AMS_TIMEOUT*i

MatchEvent
MATCH_PENDING 
MATCH_START
MATCH_SUCCESS
MATCH_CANCELED
MATCH_FAILED*b
WorldIdErrorCode

WI_SUCCESS 
WI_RANDOM_TERRAIN_ERROR!
WI_RANDOM_TERRAIN_WORLD_ERROR*9
PrewarmWorldErrorCode

PW_SUCCESS 
PW_NOT_FOUND