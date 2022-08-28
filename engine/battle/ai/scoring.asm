AIScoring: ; used only for BANK(AIScoring)

SubstituteImmuneEffects:	;joenote - added this table to track for substitute immunities
	db $01 ; unused sleep effect
	db EFFECT_SLEEP
	db EFFECT_POISON
	db EFFECT_PARALYZE
	db EFFECT_CONFUSE
	db EFFECT_LEECH_SEED
	db EFFECT_ACCURACY_DOWN
	db EFFECT_DEFENSE_DOWN
	db EFFECT_DEFENSE_DOWN_2
	db EFFECT_ATTACK_DOWN
	db $FF

AI_Basic:
; Don't do anything redundant:
;  -Using status-only moves if the player can't be statused
;  -Using moves that fail if they've already been used

	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b ; b is num moves on 1st pass
	ret z ; if b os 0 return we are done

	inc hl ; increment score to next move score
	ld a, [de] ; load the move struct
	and a
	ret z ; return if no move

	inc de ; increment to next move
	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	ld c, a ; load move effect into c

; Dismiss moves with special effects if they are
; useless or not a good choice right now.
; For example, healing moves, weather moves, Dream Eater...
	push hl
	push de
	push bc
	farcall AI_Redundant
	pop bc
	pop de
	pop hl
	jp nz, .discourage ; discourage if AI_Redundant - loop bck to check move

; Dismiss status-only moves if the player can't be statused.
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	push hl
	push de
	push bc
	ld hl, StatusOnlyEffects
	ld de, 1
	call IsInArray ; is the move status only

	pop bc
	pop de
	pop hl
	jr nc, .checkSub ; if not skip following

	ld a, [wBattleMonStatus]
	and a
	jr nz, .discourage ; discourage if the player is already statused - loop back to check move

.checkSub
; dismiss moves blocked by sub if sub is up
    ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a	;check for substitute bit
	jr z, .checkSafeguard	;if the substitute bit is not set, then skip out of this block
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	push hl
	push de
	push bc
	ld hl, SubstituteImmuneEffects
	ld de, 1
	call IsInArray	;see if a is found in the hl array (carry flag set if true)
	pop bc
	pop de
	pop hl
	jr c, .discourage ; discourage if sub is up and blocks move - loop back to check move

.checkSafeguard
; Dismiss Safeguard if it's already active.
;	ld a, [wPlayerScreens]
;	bit SCREENS_SAFEGUARD, a
;	jr nz, .discourage


; Greatly encourage a move if it will KO the player
; skip if enemy is slower and weakened and has priority

.checkKO
	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .checkmove

    ld a, 1
	ldh [hBattleTurn], a
	push hl
	push de
	push bc
	callfar EnemyAttackDamage
	callfar BattleCommand_DamageCalc
	callfar BattleCommand_Stab
	ld a, [wCurDamage + 1]
	ld c, a ; c is curDamage upper
	ld a, [wCurDamage]
	ld b, a ; b is curDamage lower
	ld a, [wBattleMonHP + 1]
	cp c ; compare upper
	ld a, [wBattleMonHP]
	sbc b ; compare lower and set flag
	pop bc
	pop de
	pop hl
    jp nc, .checkmove

; don't encourage explosion as much
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_SELFDESTRUCT
	jr z, .lesserEncouragement

; encourage more accurate moves of they can kill
	ld a, [wEnemyMoveStruct + MOVE_ACC]
	cp 100 percent
	jr c, .notAcc
	dec [hl]
	dec [hl]
.notAcc
	dec [hl]
    dec [hl]
.lesserEncouragement
    dec [hl]
    dec [hl]
    dec [hl]
    jp .checkmove

.discourage
	call AIDiscourageMove
	jp .checkmove

INCLUDE "data/battle/ai/status_only_effects.asm"

AI_Smart_Switch:
; Enemies can switch intelligently under certain conditions
; switch if unboosted enemy is SLP or FRZ and player sets up
; don't switch if enemy is weakened, just let it die
; switch if enemy accuracy at -2 or lower
; switch if enemy is cursed
; 50% chance to switch per turn if enemy afflicted with toxic
; 50% chance to switch per turn if enemy afflicted with leech seed

; possibly switch if enemy is setup bait
	ld a, [wEnemyMonStatus]
	and 1 << FRZ | SLP
	;and 1 << FRZ
	jr nz, .checkSetUpAndSwitchIfPlayerSetsUp

; don't switch if enemy is weakened, just let it die
	call AICheckEnemyQuarterHP
	ret nc

; switch if enemy accuracy at -2 or lower
    ld a, [wEnemyAccLevel]
	cp BASE_STAT_LEVEL - 1
	jp c, .switch

; switch if enemy is cursed
	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	bit SUBSTATUS_CURSE, a
	jp nz, .switch

; if enemy afflicted with toxic
; 50% chance to switch when above 50% hp if not set up
; switch when below 50% hp
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr z, .checkLeechSeed
	call AICheckEnemyHalfHP
	jp nc, .switch
	jp .checkSetUpAndSwitch50

.checkLeechSeed
; 50% chance to switch per turn if enemy afflicted with leech seed
    ld a, BATTLE_VARS_SUBSTATUS4
	call GetBattleVarAddr
	bit SUBSTATUS_LEECH_SEED, a
	jr nz, .switch50

    ret

.checkSetUpAndSwitchIfPlayerSetsUp
; don't switch if enemy mon is already set up
    ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc
    ld a, [wEnemySAtkLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc

; switch if player attempts to set up
	ld a, [wPlayerMoveStruct + MOVE_EFFECT]
	cp EFFECT_ATTACK_UP_2
	jr z, .switch
	cp EFFECT_SP_ATK_UP
	jr z, .switch
	cp EFFECT_SP_ATK_UP_2
	jr z, .switch
	cp EFFECT_SUBSTITUTE
	jr z, .switch
	cp EFFECT_CURSE
	jr z, .switch
	cp EFFECT_FURIOUS_WILL
	jr z, .switch
	cp EFFECT_GEOMANCY
	jr z, .switch
	cp EFFECT_CALM_MIND
	jr z, .switch
	cp EFFECT_DRAGON_DANCE
	jr z, .switch
	cp EFFECT_QUIVER_DANCE
	jr z, .switch
	ret

.checkSetUpAndSwitch50
; don't switch if enemy mon is already set up
    ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc
    ld a, [wEnemySAtkLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc
	jr .switch50

.switch50
    call AI_50_50
	ret c
.switch
    ld a, $1
    ld [wEnemyIsSwitching], a
	ret

AI_Setup:
; Use stat-modifying moves on turn 1.

; 50% chance to greatly encourage stat-up moves during the first turn of enemy's Pokemon.
; 50% chance to greatly encourage stat-down moves during the first turn of player's Pokemon.
; Almost 90% chance to greatly discourage stat-modifying moves otherwise.

	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b
	ret z

	inc hl
	ld a, [de]
	and a
	ret z

	inc de
	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_EFFECT]

	cp EFFECT_ATTACK_UP
	jr c, .checkmove
	cp EFFECT_EVASION_UP + 1
	jr c, .statup

;	cp EFFECT_ATTACK_DOWN - 1
	jr z, .checkmove
	cp EFFECT_EVASION_DOWN + 1
	jr c, .statdown

	cp EFFECT_ATTACK_UP_2
	jr c, .checkmove
	cp EFFECT_EVASION_UP_2 + 1
	jr c, .statup

;	cp EFFECT_ATTACK_DOWN_2 - 1
	jr z, .checkmove
	cp EFFECT_EVASION_DOWN_2 + 1
	jr c, .statdown

	jr .checkmove

.statup
	ld a, [wEnemyTurnsTaken]
	and a
	jr nz, .discourage

	jr .encourage

.statdown
	ld a, [wPlayerTurnsTaken]
	and a
	jr nz, .discourage

.encourage
	call AI_50_50
	jr c, .checkmove

	dec [hl]
	dec [hl]
	jr .checkmove

.discourage
	call Random
	cp 12 percent
	jr c, .checkmove
	inc [hl]
	inc [hl]
	jr .checkmove


AI_Types:
; Dismiss any move that the player is immune to.
; Encourage super-effective moves.
; Discourage not very effective moves unless
; all damaging moves are of the same type.

	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b
	ret z

	inc hl
	ld a, [de]
	and a
	ret z

	inc de
	call AIGetEnemyMove

	push hl
	push bc
	push de
	ld a, 1
	ldh [hBattleTurn], a
	callfar BattleCheckTypeMatchup
	pop de
	pop bc
	pop hl

	ld a, [wTypeMatchup]
	and a
	jr z, .immune
	cp EFFECTIVE
	jr z, .checkmove
	jr c, .noteffective

; effective
	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .checkmove
	dec [hl]
	jr .checkmove

.noteffective
; Discourage this move if there are any moves
; that do damage of a different type.
	push hl
	push de
	push bc
	ld a, [wEnemyMoveStruct + MOVE_TYPE]
	and TYPE_MASK
	ld d, a
	ld hl, wEnemyMonMoves
	ld b, NUM_MOVES + 1
	ld c, 0
.checkmove2
	dec b
	jr z, .movesdone

	ld a, [hli]
	and a
	jr z, .movesdone

	call AIGetEnemyMove
	ld a, [wEnemyMoveStruct + MOVE_TYPE]
	and TYPE_MASK
	cp d
	jr z, .checkmove2
	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr nz, .damaging
	jr .checkmove2

.damaging
	ld c, a
.movesdone
	ld a, c
	pop bc
	pop de
	pop hl
	and a
	jr z, .checkmove
	inc [hl]
	jr .checkmove

.immune
	call AIDiscourageMove
	jr .checkmove


AI_Offensive:
; Greatly discourage non-damaging moves.

	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b
	ret z

	inc hl
	ld a, [de]
	and a
	ret z

	inc de
	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr nz, .checkmove

	inc [hl]
	inc [hl]
	jr .checkmove


AI_Smart:
; Context-specific scoring.

	ld hl, wEnemyAIMoveScores
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b
	ret z

	ld a, [de]
	inc de
	and a
	ret z

	push de
	push bc
	push hl
	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	ld hl, AI_Smart_EffectHandlers
	ld de, 3
	call IsInArray

	inc hl
	jr nc, .nextmove

	ld a, [hli]
	ld e, a
	ld d, [hl]

	pop hl
	push hl

	ld bc, .nextmove
	push bc

	push de
	ret

.nextmove
	pop hl
	pop bc
	pop de
	inc hl
	jr .checkmove

AI_Smart_EffectHandlers:
	dbw EFFECT_SLEEP,            AI_Smart_Sleep
	dbw EFFECT_LEECH_HIT,        AI_Smart_LeechHit
	dbw EFFECT_SELFDESTRUCT,     AI_Smart_Selfdestruct
	dbw EFFECT_DREAM_EATER,      AI_Smart_DreamEater
	dbw EFFECT_MIRROR_MOVE,      AI_Smart_MirrorMove
	dbw EFFECT_EVASION_UP,       AI_Smart_EvasionUp
	dbw EFFECT_ALWAYS_HIT,       AI_Smart_AlwaysHit
	dbw EFFECT_ACCURACY_DOWN,    AI_Smart_AccuracyDown
	dbw EFFECT_RESET_STATS,      AI_Smart_ResetStats
	dbw EFFECT_FORCE_SWITCH,     AI_Smart_ForceSwitch
	dbw EFFECT_HEAL,             AI_Smart_Heal
	dbw EFFECT_TOXIC,            AI_Smart_Toxic
	dbw EFFECT_LIGHT_SCREEN,     AI_Smart_LightScreen
	dbw EFFECT_OHKO,             AI_Smart_Ohko
	dbw EFFECT_SUPER_FANG,       AI_Smart_SuperFang
	dbw EFFECT_TRAP_TARGET,      AI_Smart_TrapTarget
	dbw EFFECT_CONFUSE,          AI_Smart_Confuse
	dbw EFFECT_SP_DEF_UP_2,      AI_Smart_SpDefenseUp2
	dbw EFFECT_REFLECT,          AI_Smart_Reflect
	dbw EFFECT_PARALYZE,         AI_Smart_Paralyze
	dbw EFFECT_SPEED_DOWN_HIT,   AI_Smart_SpeedDownHit
	dbw EFFECT_SUBSTITUTE,       AI_Smart_Substitute
	dbw EFFECT_HYPER_BEAM,       AI_Smart_HyperBeam
	dbw EFFECT_MIMIC,            AI_Smart_Mimic
	dbw EFFECT_LEECH_SEED,       AI_Smart_LeechSeed
	dbw EFFECT_DISABLE,          AI_Smart_Disable
	dbw EFFECT_COUNTER,          AI_Smart_Counter
	dbw EFFECT_ENCORE,           AI_Smart_Encore
	dbw EFFECT_PAIN_SPLIT,       AI_Smart_PainSplit
	dbw EFFECT_SNORE,            AI_Smart_Snore
	dbw EFFECT_LOCK_ON,          AI_Smart_LockOn
	dbw EFFECT_SLEEP_TALK,       AI_Smart_SleepTalk
	dbw EFFECT_DESTINY_BOND,     AI_Smart_DestinyBond
	dbw EFFECT_REVERSAL,         AI_Smart_Reversal
	dbw EFFECT_SPITE,            AI_Smart_Spite
	dbw EFFECT_HEAL_BELL,        AI_Smart_HealBell
	dbw EFFECT_PRIORITY_HIT,     AI_Smart_PriorityHit
	dbw EFFECT_MEAN_LOOK,        AI_Smart_MeanLook
	dbw EFFECT_NIGHTMARE,        AI_Smart_Nightmare
	dbw EFFECT_FLAME_WHEEL,      AI_Smart_FlameWheel
	dbw EFFECT_CURSE,            AI_Smart_Curse
	dbw EFFECT_PROTECT,          AI_Smart_Protect
	dbw EFFECT_FORESIGHT,        AI_Smart_Foresight
	dbw EFFECT_PERISH_SONG,      AI_Smart_PerishSong
	dbw EFFECT_SANDSTORM,        AI_Smart_Sandstorm
	dbw EFFECT_ENDURE,           AI_Smart_Endure
	dbw EFFECT_ROLLOUT,          AI_Smart_Rollout
	dbw EFFECT_SWAGGER,          AI_Smart_Swagger
	dbw EFFECT_FURY_CUTTER,      AI_Smart_FuryCutter
	dbw EFFECT_ATTRACT,          AI_Smart_Attract
	dbw EFFECT_SAFEGUARD,        AI_Smart_Safeguard
	dbw EFFECT_MAGNITUDE,        AI_Smart_Magnitude
	dbw EFFECT_BATON_PASS,       AI_Smart_BatonPass
	dbw EFFECT_PURSUIT,          AI_Smart_Pursuit
	dbw EFFECT_RAPID_SPIN,       AI_Smart_RapidSpin
	dbw EFFECT_MORNING_SUN,      AI_Smart_MorningSun
	dbw EFFECT_SYNTHESIS,        AI_Smart_Synthesis
	dbw EFFECT_MOONLIGHT,        AI_Smart_Moonlight
	dbw EFFECT_HIDDEN_POWER,     AI_Smart_HiddenPower
	dbw EFFECT_RAIN_DANCE,       AI_Smart_RainDance
	dbw EFFECT_SUNNY_DAY,        AI_Smart_SunnyDay
	dbw EFFECT_BELLY_DRUM,       AI_Smart_BellyDrum
	dbw EFFECT_PSYCH_UP,         AI_Smart_PsychUp
	dbw EFFECT_MIRROR_COAT,      AI_Smart_MirrorCoat
	dbw EFFECT_TWISTER,          AI_Smart_Twister
	dbw EFFECT_EARTHQUAKE,       AI_Smart_Earthquake
	dbw EFFECT_FUTURE_SIGHT,     AI_Smart_FutureSight
	dbw EFFECT_GUST,             AI_Smart_Gust
	dbw EFFECT_STOMP,            AI_Smart_Stomp
	dbw EFFECT_SOLARBEAM,        AI_Smart_Solarbeam
	dbw EFFECT_THUNDER,          AI_Smart_Thunder
	dbw EFFECT_FLY,              AI_Smart_Fly
	dbw EFFECT_HOLY_ARMOUR,      AI_Smart_HolyArmour
	dbw EFFECT_FURIOUS_WILL,     AI_Smart_FuriousWill
	dbw EFFECT_ATTACK_UP_2,      AI_Smart_SwordsDance
	dbw EFFECT_DEFENSE_UP_2,     AI_Smart_Barrier
	dbw EFFECT_SP_ATK_UP_2,      AI_Smart_NastyPlot
	dbw EFFECT_GEOMANCY,         AI_Smart_Geomancy
	dbw EFFECT_CALM_MIND,        AI_Smart_CalmMind
	dbw EFFECT_DRAGON_DANCE,     AI_Smart_DragonDance
	dbw EFFECT_CONFUSE_HIT,      AI_Smart_DynamicPunch
    dbw EFFECT_QUIVER_DANCE,     AI_Smart_QuiverDance
    dbw EFFECT_SPIKES,           AI_Smart_Spikes
	db -1 ; end

AI_Smart_Sleep:
; Greatly encourage sleep inducing moves if the enemy has either Dream Eater or Nightmare.
; 50% chance to greatly encourage sleep inducing moves otherwise.

; if faster then continue
	call AICompareSpeed
	jr c, .continue

; discourage if faster player has picked substitute
	ld a, [wCurPlayerMove]
	cp SUBSTITUTE
	jr nc, .continue
	inc [hl]
	inc [hl]
	inc [hl]
	ret

.continue
	ld b, EFFECT_DREAM_EATER
	call AIHasMoveEffect
	jr c, .encourage

	ld b, EFFECT_NIGHTMARE
	call AIHasMoveEffect
	ret nc

.encourage
	call AI_50_50
	ret c
	dec [hl]
	dec [hl]
	ret

AI_Smart_LeechHit:
	push hl
	ld a, 1
	ldh [hBattleTurn], a
	callfar BattleCheckTypeMatchup
	pop hl

; 60% chance to discourage this move if not very effective.
	ld a, [wTypeMatchup]
	cp EFFECTIVE
	jr c, .discourage

; Do nothing if effectiveness is neutral.
	ret z

; Do nothing if enemy's HP is full.
	call AICheckEnemyMaxHP
	ret c

; 80% chance to encourage this move otherwise.
	call AI_80_20
	ret c

	dec [hl]
	ret

.discourage
	call Random
	cp 39 percent + 1
	ret c

	inc [hl]
	ret

AI_Smart_LockOn:
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_LOCK_ON, a
	jr nz, .player_locked_on

	push hl
	call AICheckEnemyQuarterHP
	jr nc, .discourage

	call AICheckEnemyHalfHP
	jr c, .skip_speed_check

	call AICompareSpeed
	jr nc, .discourage

.skip_speed_check
	ld a, [wPlayerEvaLevel]
	cp BASE_STAT_LEVEL + 3
	jr nc, .maybe_encourage
	cp BASE_STAT_LEVEL + 1
	jr nc, .do_nothing

	ld a, [wEnemyAccLevel]
	cp BASE_STAT_LEVEL - 2
	jr c, .maybe_encourage
	cp BASE_STAT_LEVEL
	jr c, .do_nothing

	ld hl, wEnemyMonMoves
	ld c, NUM_MOVES + 1
.checkmove
	dec c
	jr z, .discourage

	ld a, [hli]
	and a
	jr z, .discourage

	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_ACC]
	cp 71 percent - 1
	jr nc, .checkmove

	ld a, 1
	ldh [hBattleTurn], a

	push hl
	push bc
	farcall BattleCheckTypeMatchup
	ld a, [wTypeMatchup]
	cp EFFECTIVE
	pop bc
	pop hl
	jr c, .checkmove

.do_nothing
	pop hl
	ret

.discourage
	pop hl
	inc [hl]
	ret

.maybe_encourage
	pop hl
	call AI_50_50
	ret c

	dec [hl]
	dec [hl]
	ret

.player_locked_on
	push hl
	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld c, NUM_MOVES + 1

.checkmove2
	inc hl
	dec c
	jr z, .dismiss

	ld a, [de]
	and a
	jr z, .dismiss

	inc de
	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_ACC]
	cp 71 percent - 1
	jr nc, .checkmove2

	dec [hl]
	dec [hl]
	jr .checkmove2

.dismiss
	pop hl
	jp AIDiscourageMove

AI_Smart_Selfdestruct:
; Selfdestruct, Explosion

; never use against ghost types
    ld a, [wBattleMonType1]
	cp GHOST
	jr z, .discourage
	ld a, [wBattleMonType2]
	cp GHOST
	jr z, .discourage

; Unless this is the enemy's last Pokemon...
	push hl
	farcall FindAliveEnemyMons
	pop hl
	jr nc, .notlastmon

; ...greatly discourage this move unless this is the player's last Pokemon too.
	push hl
	call AICheckLastPlayerMon
	pop hl
	jr nz, .discourage

.notlastmon
; if enemy's HP is below 25% just boom
	call AICheckEnemyQuarterHP
	jr nc, .encourage

; if player has highly boosted stats just boom
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr nc, .encourage
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr nc, .encourage

; if player is faster and has slightly boosted stats just boom
    call AICompareSpeed
    jr c, .continue
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .encourage
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .encourage

.continue
; Greatly discourage this move if enemy's HP is above 50%.
	call AICheckEnemyHalfHP
	jr c, .discourage

; if we are here we are below 1/2 hp and player is non boosted
; if we have no other move that can ko the player just boom

.encourage
    dec [hl]
    ret
.discourage
	inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AI_Smart_DreamEater:
; 90% chance to greatly encourage this move.
; The AI_Basic layer will make sure that
; Dream Eater is only used against sleeping targets.
	call Random
	cp 10 percent
	ret c
	dec [hl]
	dec [hl]
	dec [hl]
	ret

AI_Smart_EvasionUp:
; Dismiss this move if enemy's evasion can't raise anymore.
	ld a, [wEnemyEvaLevel]
	cp MAX_STAT_LEVEL
	jp nc, AIDiscourageMove

; If enemy's HP is full...
	call AICheckEnemyMaxHP
	jr nc, .hp_mismatch_1

; ...greatly encourage this move if player is badly poisoned.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .greatly_encourage

; ...70% chance to greatly encourage this move if player is not badly poisoned.
	call Random
	cp 70 percent
	jr nc, .not_encouraged

.greatly_encourage
	dec [hl]
	dec [hl]
	ret

.hp_mismatch_1

; Greatly discourage this move if enemy's HP is below 25%.
	call AICheckEnemyQuarterHP
	jr nc, .hp_mismatch_2

; If enemy's HP is above 25% but not full, 4% chance to greatly encourage this move.
	call Random
	cp 4 percent
	jr c, .greatly_encourage

; If enemy's HP is between 25% and 50%,...
	call AICheckEnemyHalfHP
	jr nc, .hp_mismatch_3

; If enemy's HP is above 50% but not full, 20% chance to greatly encourage this move.
	call AI_80_20
	jr c, .greatly_encourage
	jr .not_encouraged

.hp_mismatch_3
; ...50% chance to greatly discourage this move.
	call AI_50_50
	jr c, .not_encouraged

.hp_mismatch_2
	inc [hl]
	inc [hl]

; 30% chance to end up here if enemy's HP is full and player is not badly poisoned.
; 77% chance to end up here if enemy's HP is above 50% but not full.
; 96% chance to end up here if enemy's HP is between 25% and 50%.
; 100% chance to end up here if enemy's HP is below 25%.
; In other words, we only end up here if the move has not been encouraged or dismissed.
.not_encouraged
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .maybe_greatly_encourage

	ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_LEECH_SEED, a
	jr nz, .maybe_encourage

; Discourage this move if enemy's evasion level is higher than player's accuracy level.
	ld a, [wEnemyEvaLevel]
	ld b, a
	ld a, [wPlayerAccLevel]
	cp b
	jr c, .discourage

; Greatly encourage this move if the player is in the middle of Fury Cutter or Rollout.
	ld a, [wPlayerFuryCutterCount]
	and a
	jr nz, .greatly_encourage

	ld a, [wPlayerSubStatus1]
	bit SUBSTATUS_ROLLOUT, a
	jr nz, .greatly_encourage

.discourage
	inc [hl]
	ret

; Player is badly poisoned.
; 70% chance to greatly encourage this move.
; This would counter any previous discouragement.
.maybe_greatly_encourage
	call Random
	cp 31 percent + 1
	ret c

	dec [hl]
	dec [hl]
	ret

; Player is seeded.
; 50% chance to encourage this move.
; This would partly counter any previous discouragement.
.maybe_encourage
	call AI_50_50
	ret c

	dec [hl]
	ret

AI_Smart_AlwaysHit:
; 80% chance to greatly encourage this move if either...

; ...enemy's accuracy level has been lowered three or more stages
	ld a, [wEnemyAccLevel]
	cp BASE_STAT_LEVEL - 2
	jr c, .encourage

; ...or player's evasion level has been raised three or more stages.
	ld a, [wPlayerEvaLevel]
	cp BASE_STAT_LEVEL + 3
	ret c

.encourage
	call AI_80_20
	ret c

	dec [hl]
	dec [hl]
	ret

AI_Smart_MirrorMove:
; If the player did not use any move last turn...
	ld a, [wLastPlayerCounterMove]
	and a
	jr nz, .usedmove

; ...do nothing if enemy is slower than player
	call AICompareSpeed
	ret nc

; ...or dismiss this move if enemy is faster than player.
	jp AIDiscourageMove

; If the player did use a move last turn...
.usedmove
	push hl
	ld hl, UsefulMoves
	ld de, 1
	call IsInArray
	pop hl

; ...do nothing if he didn't use a useful move.
	ret nc

; If he did, 50% chance to encourage this move...
	call AI_50_50
	ret c

	dec [hl]

; ...and 90% chance to encourage this move again if the enemy is faster.
	call AICompareSpeed
	ret nc

	call Random
	cp 10 percent
	ret c

	dec [hl]
	ret

AI_Smart_AccuracyDown:
; If player's HP is full...
	call AICheckPlayerMaxHP
	jr nc, .hp_mismatch_1

; ...and enemy's HP is above 50%...
	call AICheckEnemyHalfHP
	jr nc, .hp_mismatch_1

; ...greatly encourage this move if player is badly poisoned.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .greatly_encourage

; ...70% chance to greatly encourage this move if player is not badly poisoned.
	call Random
	cp 70 percent
	jr nc, .not_encouraged

.greatly_encourage
	dec [hl]
	dec [hl]
	ret

.hp_mismatch_1

; Greatly discourage this move if player's HP is below 25%.
	call AICheckPlayerQuarterHP
	jr nc, .hp_mismatch_2

; If player's HP is above 25% but not full, 4% chance to greatly encourage this move.
	call Random
	cp 4 percent
	jr c, .greatly_encourage

; If player's HP is between 25% and 50%,...
	call AICheckPlayerHalfHP
	jr nc, .hp_mismatch_3

; If player's HP is above 50% but not full, 20% chance to greatly encourage this move.
	call AI_80_20
	jr c, .greatly_encourage
	jr .not_encouraged

; ...50% chance to greatly discourage this move.
.hp_mismatch_3
	call AI_50_50
	jr c, .not_encouraged

.hp_mismatch_2
	inc [hl]
	inc [hl]

; We only end up here if the move has not been already encouraged.
.not_encouraged
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .maybe_greatly_encourage

	ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_LEECH_SEED, a
	jr nz, .encourage

; Discourage this move if enemy's evasion level is higher than player's accuracy level.
	ld a, [wEnemyEvaLevel]
	ld b, a
	ld a, [wPlayerAccLevel]
	cp b
	jr c, .discourage

; Greatly encourage this move if the player is in the middle of Fury Cutter or Rollout.
	ld a, [wPlayerFuryCutterCount]
	and a
	jr nz, .greatly_encourage

	ld a, [wPlayerSubStatus1]
	bit SUBSTATUS_ROLLOUT, a
	jr nz, .greatly_encourage

.discourage
	inc [hl]
	ret

; Player is badly poisoned.
; 70% chance to greatly encourage this move.
; This would counter any previous discouragement.
.maybe_greatly_encourage
	call Random
	cp 31 percent + 1
	ret c

	dec [hl]
	dec [hl]
	ret

; Player is seeded.
; 50% chance to encourage this move.
; This would partly counter any previous discouragement.
.encourage
	call AI_50_50
	ret c

	dec [hl]
	ret

AI_Smart_ResetStats:
; 85% chance to encourage this move if any of enemy's stat levels is lower than -2.
	push hl
	ld hl, wEnemyAtkLevel
	ld c, NUM_LEVEL_STATS
.enemystatsloop
	dec c
	jr z, .enemystatsdone
	ld a, [hli]
	cp BASE_STAT_LEVEL - 2
	jr c, .encourage
	jr .enemystatsloop

; 85% chance to encourage this move if any of player's stat levels is higher than +2.
.enemystatsdone
	ld hl, wPlayerAtkLevel
	ld c, NUM_LEVEL_STATS
.playerstatsloop
	dec c
	jr z, .discourage
	ld a, [hli]
	cp BASE_STAT_LEVEL + 3
	jr c, .playerstatsloop

.encourage
	pop hl
	call Random
	cp 16 percent
	ret c
	dec [hl]
	ret

; Discourage this move if neither:
; Any of enemy's stat levels is	lower than -2.
; Any of player's stat levels is higher than +2.
.discourage
	pop hl
	inc [hl]
	ret

AI_Smart_Spikes:
; discourage if player has spikes on the field, otherwise encourage
	ld a, [wPlayerScreens]
	bit SCREENS_SPIKES, a
	jr nz, .discourage
	dec [hl]
	dec [hl]
	dec [hl]
	ret
.discourage
    inc [hl]
    inc [hl]
    inc [hl]
    inc [hl]
    ret

AI_Smart_ForceSwitch:
; Whirlwind, Roar.
; don't use if player has only one pokemon left
	push hl
	call AICheckLastPlayerMon
	pop hl
	jr z, .discourage
; encourage if player has spikes on the field
	ld a, [wPlayerScreens]
	bit SCREENS_SPIKES, a
	jr nz, .encourage
; encourage this move if any of player's stat levels are boosted.
	ld hl, wPlayerAtkLevel
	ld c, NUM_LEVEL_STATS
.playerstatsloop
	dec c
	jr z, .discourage
	ld a, [hli]
	cp BASE_STAT_LEVEL + 1
	jr c, .playerstatsloop
	dec [hl]
	dec [hl]
.encourage
	dec [hl]
	ret
.discourage
    inc [hl]
    inc [hl]
    inc [hl]
    ret

AI_Smart_Heal:
AI_Smart_MorningSun:
AI_Smart_Synthesis:
AI_Smart_Moonlight:
; don't use if we are at risk of being KOd by boosted player, just attack them
; physical
; does player have boosted attack
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 3
	jr c, .special
; does enemy have non-boosted defense
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr c, .dontBoost
.special
; does player have boosted special attack
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 3
	jr c, .continue
; does enemy have non-boosted special defense
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .continue
.dontBoost
; is player SLP or FRZ
	ld a, [wBattleMonStatus]
	and SLP
	jr nz, .continue
	;bit FRZ, a
	;jr nz, .continue
; is player attacking
	ld a, [wPlayerMoveStruct + MOVE_POWER]
	and a
	jr nz, .discourage

.continue
; don't use when above 50% hp
	call AICheckEnemyHalfHP
	jr c, .discourage

; check if the move is Rest
	ld a, [wEnemyMoveStruct + MOVE_ANIM]
	cp REST
	jr nz, .healBelowHalfHp

; if it is Rest check if the enemy is afflicted with toxic
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr z, .restHeal

; if enemy knows Rest and is afflicted with toxic cancel any switching and heal below 1/2 HP
    ld a, $0
    ld [wEnemyIsSwitching], a
    jr .healBelowHalfHp

; for rest heal below 1/4 HP if faster than player, discourage otherwise
; if slower than player 50% chance to heal below 1/2 HP and guaranteed below 1/4 HP
.restHeal
    call AICheckEnemyQuarterHP
    jr c, .encourage
	call AICompareSpeed
	jr nc, .discourage
 	call AI_50_50
 	ret c

; otherwise encourage heal when under 1/2 hp
.healBelowHalfHp
    call AICheckEnemyHalfHP
    ret c

; fall through
.encourage
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	ret
.discourage
    inc [hl]
    inc [hl]
    inc [hl]
    inc [hl]
    ret

AI_Smart_Toxic:
AI_Smart_LeechSeed:
; Discourage this move if player's HP is below 50%.

	call AICheckPlayerHalfHP
	ret c
	inc [hl]
	ret

AI_Smart_LightScreen:
AI_Smart_Reflect:
; Over 90% chance to discourage this move unless enemy's HP is full.

	call AICheckEnemyMaxHP
	ret c
	call Random
	cp 8 percent
	ret c
	inc [hl]
	ret

AI_Smart_Ohko:
; Dismiss this move if player's level is higher than enemy's level.
; Else, discourage this move is player's HP is below 50%.

	ld a, [wBattleMonLevel]
	ld b, a
	ld a, [wEnemyMonLevel]
	cp b
	jp c, AIDiscourageMove
	call AICheckPlayerHalfHP
	ret c
	inc [hl]
	ret

AI_Smart_TrapTarget:
; Wrap, Fire Spin, Clamp

; 50% chance to discourage this move if the player is already trapped.
	ld a, [wPlayerWrapCount]
	and a
	jr nz, .discourage

; 50% chance to greatly encourage this move if player is either
; badly poisoned, in love, identified, stuck in Rollout, or has a Nightmare.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .encourage

	ld a, [wPlayerSubStatus1]
	and 1 << SUBSTATUS_IN_LOVE | 1 << SUBSTATUS_ROLLOUT | 1 << SUBSTATUS_IDENTIFIED | 1 << SUBSTATUS_NIGHTMARE
	jr nz, .encourage

; Else, 50% chance to greatly encourage this move if it's the player's Pokemon first turn.
	ld a, [wPlayerTurnsTaken]
	and a
	jr z, .encourage

; 50% chance to discourage this move otherwise.
.discourage
	call AI_50_50
	ret c
	inc [hl]
	ret

.encourage
	call AICheckEnemyQuarterHP
	ret nc
	call AI_50_50
	ret c
	dec [hl]
	dec [hl]
	ret

AI_Smart_RazorWind:
	ld a, [wEnemySubStatus1]
	bit SUBSTATUS_PERISH, a
	jr z, .no_perish_count

	ld a, [wEnemyPerishCount]
	cp 3
	jr c, .discourage

.no_perish_count
	push hl
	ld hl, wPlayerUsedMoves
	ld c, NUM_MOVES

.checkmove
	ld a, [hli]
	and a
	jr z, .movesdone

	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_PROTECT
	jr z, .dismiss
	dec c
	jr nz, .checkmove

.movesdone
	pop hl
	ld a, [wEnemySubStatus3]
	bit SUBSTATUS_CONFUSED, a
	jr nz, .maybe_discourage

	call AICheckEnemyHalfHP
	ret c

.maybe_discourage
	call Random
	cp 79 percent - 1
	ret c

.discourage
	inc [hl]
	ret

.dismiss
	pop hl
	ld a, [hl]
	add 6
	ld [hl], a
	ret

AI_Smart_Confuse:
; 90% chance to discourage this move if player's HP is between 25% and 50%.
	call AICheckPlayerHalfHP
	ret c
	call Random
	cp 10 percent
	jr c, .skipdiscourage
	inc [hl]

.skipdiscourage
; Discourage again if player's HP is below 25%.
	call AICheckPlayerQuarterHP
	ret c
	inc [hl]
	ret

AI_Smart_SpDefenseUp2:
; Discourage this move if enemy's HP is lower than 50%.
	call AICheckEnemyHalfHP
	jr nc, .discourage

; Discourage this move if enemy's special defense level is higher than +3.
	ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 4
	jr nc, .discourage

; 80% chance to greatly encourage this move if
; enemy's Special Defense level is lower than +2,
; and the player's Pokémon is Special-oriented.
	cp BASE_STAT_LEVEL + 2
	ret nc

	push hl
; Get the pointer for the player's Pokémon's base Attack
	ld a, [wBattleMonSpecies]
	ld hl, BaseData + BASE_ATK
	ld bc, BASE_DATA_SIZE
	call AddNTimes
; Get the Pokémon's base Attack
	ld a, BANK(BaseData)
	call GetFarByte
	ld d, a
; Get the pointer for the player's Pokémon's base Special Attack
	ld bc, BASE_SAT - BASE_ATK
	add hl, bc
; Get the Pokémon's base Special Attack
	ld a, BANK(BaseData)
	call GetFarByte
	pop hl
; If its base Attack is greater than its base Special Attack,
; don't encourage this move.
	cp d
	ret c

.encourage
	call AI_80_20
	ret c
	dec [hl]
	dec [hl]
	ret

.discourage
	inc [hl]
	ret

AI_Smart_Fly:
; Fly, Dig

; Greatly encourage this move if the player is
; flying or underground, and slower than the enemy.

	ld a, [wPlayerSubStatus3]
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	ret z

	call AICompareSpeed
	ret nc

	dec [hl]
	dec [hl]
	dec [hl]
	ret

AI_Smart_SuperFang:
; Discourage this move if player's HP is below 25%.
	call AICheckPlayerQuarterHP
	ret c
	inc [hl]
	ret

AI_Smart_Paralyze:
; never use thunderwave against ground types
	ld a, [wEnemyMoveStruct + MOVE_ANIM]
	cp THUNDER_WAVE
	jr nz, .notThunderwave
    ld a, [wBattleMonType1]
	cp GROUND
	jr z, .discourage
	ld a, [wBattleMonType2]
	cp GROUND
	jr z, .discourage

.notThunderwave
; always use against Mewtwo or Arceus
    ld a, [wBattleMonSpecies]
    cp MEWTWO
    jr z, .encourage
    cp ARCEUS
    jr z, .encourage

; encourage if enemy is slower than player.
; 50% chance to discourage otherwise
	call AICompareSpeed
	jr c, .discourage50

.encourage
    dec [hl]
    dec [hl]
    dec [hl]
    ret
.discourage50
    call AI_50_50
    ret c
.discourage
    inc [hl]
    inc [hl]
    inc [hl]
    inc [hl]
    ret

AI_Smart_SpeedDownHit:
; Icy Wind

; Almost 90% chance to greatly encourage this move if the following conditions all meet:
; Enemy's HP is higher than 25%.
; It's the first turn of player's Pokemon.
; Player is faster than enemy.

	ld a, [wEnemyMoveStruct + MOVE_ANIM]
	cp ICY_WIND
	ret nz
	call AICheckEnemyQuarterHP
	ret nc
	ld a, [wPlayerTurnsTaken]
	and a
	ret nz
	call AICompareSpeed
	ret c
	call Random
	cp 12 percent
	ret c
	dec [hl]
	dec [hl]
	ret

AI_Smart_Substitute:
; Dismiss this move if enemy's HP is below 50%.

	call AICheckEnemyHalfHP
	ret c
	jp AIDiscourageMove

AI_Smart_HyperBeam:
	call AICheckEnemyHalfHP
	jr c, .discourage

; 50% chance to encourage this move if enemy's HP is below 25%.
	call AICheckEnemyQuarterHP
	ret c
	call AI_50_50
	ret c
	dec [hl]
	ret

.discourage
; If enemy's HP is above 50%, discourage this move at random
	call Random
	cp 16 percent
	ret c
	inc [hl]
	call AI_50_50
	ret c
	inc [hl]
	ret

AI_Smart_Mimic:
; Discourage this move if the player did not use any move last turn.
	ld a, [wLastPlayerCounterMove]
	and a
	jr z, .dismiss

	call AICheckEnemyHalfHP
	jr nc, .discourage

	push hl
	ld a, [wLastPlayerCounterMove]
	call AIGetEnemyMove

	ld a, 1
	ldh [hBattleTurn], a
	callfar BattleCheckTypeMatchup

	ld a, [wTypeMatchup]
	cp EFFECTIVE
	pop hl
	jr c, .discourage
	jr z, .skip_encourage

	call AI_50_50
	jr c, .skip_encourage

	dec [hl]

.skip_encourage
	ld a, [wLastPlayerCounterMove]
	push hl
	ld hl, UsefulMoves
	ld de, 1
	call IsInArray

	pop hl
	ret nc
	call AI_50_50
	ret c
	dec [hl]
	ret

.dismiss
; Dismiss this move if the enemy is faster than the player.
	call AICompareSpeed
	jp c, AIDiscourageMove

.discourage
	inc [hl]
	ret

AI_Smart_Counter:
	push hl
	ld hl, wPlayerUsedMoves
	ld c, NUM_MOVES
	ld b, 0

.playermoveloop
	ld a, [hli]
	and a
	jr z, .skipmove

	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .skipmove

	ld a, [wEnemyMoveStruct + MOVE_TYPE]
	cp SPECIAL
	jr nc, .skipmove

	inc b

.skipmove
	dec c
	jr nz, .playermoveloop

	pop hl
	ld a, b
	and a
	jr z, .discourage

	cp 3
	jr nc, .encourage

	ld a, [wLastPlayerCounterMove]
	and a
	jr z, .done

	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .done

	ld a, [wEnemyMoveStruct + MOVE_TYPE]
	cp SPECIAL
	jr nc, .done

.encourage
	call Random
	cp 39 percent + 1
	jr c, .done

	dec [hl]

.done
	ret

.discourage
	inc [hl]
	ret

AI_Smart_Encore:
	call AICompareSpeed
	jr nc, .discourage

	ld a, [wLastPlayerMove]
	and a
	jp z, AIDiscourageMove

	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .weakmove

	push hl
	ld a, [wEnemyMoveStruct + MOVE_TYPE]
	and TYPE_MASK
	ld hl, wEnemyMonType1
	predef CheckTypeMatchup

	pop hl
	ld a, [wTypeMatchup]
	cp EFFECTIVE
	jr nc, .weakmove

	and a
	ret nz
	jr .encourage

.weakmove
	push hl
	ld a, [wLastPlayerCounterMove]
	ld hl, EncoreMoves
	ld de, 1
	call IsInArray
	pop hl
	jr nc, .discourage

.encourage
	call Random
	cp 28 percent - 1
	ret c
	dec [hl]
	dec [hl]
	ret

.discourage
	inc [hl]
	inc [hl]
	inc [hl]
	ret

INCLUDE "data/battle/ai/encore_moves.asm"

AI_Smart_PainSplit:
; Discourage this move if [enemy's current HP * 2 > player's current HP].

	push hl
	ld hl, wEnemyMonHP
	ld b, [hl]
	inc hl
	ld c, [hl]
	sla c
	rl b
	ld hl, wBattleMonHP + 1
	ld a, [hld]
	cp c
	ld a, [hl]
	sbc b
	pop hl
	ret nc
	inc [hl]
	ret

AI_Smart_Snore:
AI_Smart_SleepTalk:
; Greatly encourage this move if enemy is fast asleep.
; Greatly discourage this move otherwise.

	ld a, [wEnemyMonStatus]
	and SLP
	cp 1
	jr z, .discourage

	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	ret

.discourage
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AI_Smart_Spite:
	ld a, [wLastPlayerCounterMove]
	and a
	jr nz, .usedmove

	call AICompareSpeed
	jp c, AIDiscourageMove

	call AI_50_50
	ret c
	inc [hl]
	ret

.usedmove
	push hl
	ld b, a
	ld c, NUM_MOVES
	ld hl, wBattleMonMoves
	ld de, wBattleMonPP

.moveloop
	ld a, [hli]
	cp b
	jr z, .foundmove

	inc de
	dec c
	jr nz, .moveloop

	pop hl
	ret

.foundmove
	pop hl
	ld a, [de]
	cp 6
	jr c, .encourage
	cp 15
	jr nc, .discourage

	call Random
	cp 39 percent + 1
	ret nc

.discourage
	inc [hl]
	ret

.encourage
	call Random
	cp 39 percent + 1
	ret c
	dec [hl]
	dec [hl]
	ret

.dismiss ; unreferenced
	jp AIDiscourageMove

AI_Smart_DestinyBond:
AI_Smart_Reversal:
; Discourage this move if enemy's HP is above 25%.

	call AICheckEnemyQuarterHP
	ret nc
	inc [hl]
	ret

AI_Smart_HealBell:
; Dismiss this move if none of the opponent's Pokemon is statused.
; Encourage this move if the enemy is statused.
; 50% chance to greatly encourage this move if the enemy is fast asleep or frozen.

	push hl
	ld a, [wOTPartyCount]
	ld b, a
	ld c, 0
	ld hl, wOTPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH

.loop
	push hl
	ld a, [hli]
	or [hl]
	jr z, .next

	; status
	dec hl
	dec hl
	dec hl
	ld a, [hl]
	or c
	ld c, a

.next
	pop hl
	add hl, de
	dec b
	jr nz, .loop

	pop hl
	ld a, c
	and a
	jr z, .no_status

	ld a, [wEnemyMonStatus]
	and a
	jr z, .ok
	dec [hl]
.ok
	and 1 << FRZ | SLP
	ret z
	call AI_50_50
	ret c
	dec [hl]
	dec [hl]
	ret

.no_status
	ld a, [wEnemyMonStatus]
	and a
	ret nz
	jp AIDiscourageMove


AI_Smart_PriorityHit:
; if faster than the player then do nothing
	call AICompareSpeed
	ret c

; Dismiss this move if the player is flying or underground.
	ld a, [wPlayerSubStatus3]
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	jp nz, AIDiscourageMove

; massive encourage if below half health and player is attacking
; this needs to overcome encouragement from other moves which do more damage and can KO
	call AICheckEnemyHalfHP
	jr c, .continue
	ld a, [wPlayerMoveStruct + MOVE_POWER]
	and a
	jr z, .continue
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]
	dec [hl]

.continue
; Greatly encourage this move if it will KO the player.
	ld a, 1
	ldh [hBattleTurn], a
	push hl
	callfar EnemyAttackDamage
	callfar BattleCommand_DamageCalc
	callfar BattleCommand_Stab
	pop hl
	ld a, [wCurDamage + 1]
	ld c, a
	ld a, [wCurDamage]
	ld b, a
	ld a, [wBattleMonHP + 1]
	cp c
	ld a, [wBattleMonHP]
	sbc b
	ret nc
	dec [hl]
	dec [hl]
	dec [hl]
	ret

AI_Smart_Disable:
	call AICompareSpeed
	jr nc, .discourage

	push hl
	ld a, [wLastPlayerCounterMove]
	ld hl, UsefulMoves
	ld de, 1
	call IsInArray

	pop hl
	jr nc, .notencourage

	call Random
	cp 39 percent + 1
	ret c
	dec [hl]
	ret

.notencourage
	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	ret nz

.discourage
	call Random
	cp 8 percent
	ret c
	inc [hl]
	ret

AI_Smart_MeanLook:
	call AICheckEnemyHalfHP
	jr nc, .discourage

	push hl
	call AICheckLastPlayerMon
	pop hl
	jp z, AIDiscourageMove

; 80% chance to greatly encourage this move if the enemy is badly poisoned (buggy).
; Should check wPlayerSubStatus5 instead.
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .encourage

; 80% chance to greatly encourage this move if the player is either
; in love, identified, stuck in Rollout, or has a Nightmare.
	ld a, [wPlayerSubStatus1]
	and 1 << SUBSTATUS_IN_LOVE | 1 << SUBSTATUS_ROLLOUT | 1 << SUBSTATUS_IDENTIFIED | 1 << SUBSTATUS_NIGHTMARE
	jr nz, .encourage

; Otherwise, discourage this move unless the player only has not very effective moves against the enemy.
	push hl
	callfar CheckPlayerMoveTypeMatchups
	ld a, [wEnemyAISwitchScore]
	cp BASE_AI_SWITCH_SCORE + 1 ; not very effective
	pop hl
	ret nc

.discourage
	inc [hl]
	ret

.encourage
	call AI_80_20
	ret c
	dec [hl]
	dec [hl]
	dec [hl]
	ret

AICheckLastPlayerMon:
	ld a, [wPartyCount]
	ld b, a
	ld c, 0
	ld hl, wPartyMon1HP
	ld de, PARTYMON_STRUCT_LENGTH

.loop
	ld a, [wCurBattleMon]
	cp c
	jr z, .skip

	ld a, [hli]
	or [hl]
	ret nz
	dec hl

.skip
	add hl, de
	inc c
	dec b
	jr nz, .loop

	ret

AI_Smart_Nightmare:
; 50% chance to encourage this move.
; The AI_Basic layer will make sure that
; Dream Eater is only used against sleeping targets.

	call AI_50_50
	ret c
	dec [hl]
	ret

AI_Smart_FlameWheel:
; Use this move if the enemy is frozen.

	ld a, [wEnemyMonStatus]
	bit FRZ, a
	ret z
rept 5
	dec [hl]
endr
	ret

AI_Smart_Curse:
	ld a, [wEnemyMonType1]
	cp GHOST
	jp z, .ghost_curse
	ld a, [wEnemyMonType2]
	cp GHOST
	jr z, .ghost_curse

; don't go past +4
    ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 4
	jr c, .continue
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 4
	jr nc, .discourage

.continue
; don't use if we are at risk of being KOd by boosted player, just attack them
; physical
    call AICompareSpeed
    jr nc, .slower
; does player have boosted attack
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 4
	jr c, .special
	jr .checkDef
.slower
; does player have boosted attack
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .special
.checkDef
; does enemy have non-boosted defense
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .special
    jr .dontBoost
.special
; does player have boosted special attack
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .continue2
; does enemy have non-boosted special defense
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .continue2
.dontBoost
; is player SLP or FRZ
	ld a, [wBattleMonStatus]
	and SLP
	jr nz, .continue2
	bit FRZ, a
	jr nz, .continue2
; is the player behind a sub
    ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a	;check for substitute bit
	jr nz, .discourage
; is player attacking
	ld a, [wPlayerMoveStruct + MOVE_POWER]
	and a
	jr nz, .discourage

.continue2
; encourage to +1, strongly encourage if player has boosted Atk
    ld a, [wEnemyAtkLevel]
    cp BASE_STAT_LEVEL + 1
    jr nc, .checkToxic ;
	ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .greatly_encourage
	jr .encourage

; discourage after +1 if afflicted with toxic
.checkToxic
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr nz, .discourage

; discourage after +1 if player has boosted special attack
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .discourage

    ret

.approve
	dec [hl]
	dec [hl]
.greatly_encourage
	dec [hl]
.encourage
	dec [hl]
	ret
.discourage
    inc [hl]
    inc [hl]
    inc [hl]
    inc [hl]
    ret

.ghost_curse
	ld a, [wPlayerSubStatus1]
	bit SUBSTATUS_CURSE, a
	jp nz, AIDiscourageMove

	push hl
	farcall FindAliveEnemyMons
	pop hl
	jr nc, .notlastmon

	push hl
	call AICheckLastPlayerMon
	pop hl
	jr nz, .approve

	jr .ghost_continue

.notlastmon
	push hl
	call AICheckLastPlayerMon
	pop hl
	jr z, .maybe_greatly_encourage

.ghost_continue
	call AICheckEnemyQuarterHP
	jp nc, .approve

	call AICheckEnemyHalfHP
	jr nc, .greatly_encourage

	call AICheckEnemyMaxHP
	ret nc

	ld a, [wPlayerTurnsTaken]
	and a
	ret nz

.maybe_greatly_encourage
	call AI_50_50
	ret c

	dec [hl]
	dec [hl]
	ret

AI_Smart_Protect:
; Greatly discourage this move if the enemy already used Protect.
	ld a, [wEnemyProtectCount]
	and a
	jr nz, .greatly_discourage

; Discourage this move if the player is locked on.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_LOCK_ON, a
	jr nz, .discourage

; Encourage this move if the player's Fury Cutter is boosted enough.
	ld a, [wPlayerFuryCutterCount]
	cp 3
	jr nc, .encourage

; Encourage this move if the player has charged a two-turn move.
	ld a, [wPlayerSubStatus3]
	bit SUBSTATUS_CHARGED, a
	jr nz, .encourage

; Encourage this move if the player is affected by Toxic, Leech Seed, or Curse.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .encourage
	ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_LEECH_SEED, a
	jr nz, .encourage
	ld a, [wPlayerSubStatus1]
	bit SUBSTATUS_CURSE, a
	jr nz, .encourage

; Discourage this move if the player's Rollout count is not boosted enough.
	bit SUBSTATUS_ROLLOUT, a
	jr z, .discourage
	ld a, [wPlayerRolloutCount]
	cp 3
	jr c, .discourage

; 80% chance to encourage this move otherwise.
.encourage
	call AI_80_20
	ret c

	dec [hl]
	ret

.greatly_discourage
	inc [hl]

.discourage
	call Random
	cp 8 percent
	ret c

	inc [hl]
	inc [hl]
	ret

AI_Smart_Foresight:
; 60% chance to encourage this move if the enemy's accuracy is sharply lowered.
	ld a, [wEnemyAccLevel]
	cp BASE_STAT_LEVEL - 2
	jr c, .encourage

; 60% chance to encourage this move if the player's evasion is sharply raised.
	ld a, [wPlayerEvaLevel]
	cp BASE_STAT_LEVEL + 3
	jr nc, .encourage

; 60% chance to encourage this move if the player is a Ghost type.
	ld a, [wBattleMonType1]
	cp GHOST
	jr z, .encourage
	ld a, [wBattleMonType2]
	cp GHOST
	jr z, .encourage

; 92% chance to discourage this move otherwise.
	call Random
	cp 8 percent
	ret c

	inc [hl]
	ret

.encourage
	call Random
	cp 39 percent + 1
	ret c

	dec [hl]
	dec [hl]
	ret

AI_Smart_PerishSong:
	push hl
	callfar FindAliveEnemyMons
	pop hl
	jr c, .no

	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_CANT_RUN, a
	jr nz, .yes

	push hl
	callfar CheckPlayerMoveTypeMatchups
	ld a, [wEnemyAISwitchScore]
	cp BASE_AI_SWITCH_SCORE
	pop hl
	ret c

	call AI_50_50
	ret c

	inc [hl]
	ret

.yes
	call AI_50_50
	ret c

	dec [hl]
	ret

.no
	ld a, [hl]
	add 5
	ld [hl], a
	ret

AI_Smart_Sandstorm:
; Greatly discourage this move if the player is immune to Sandstorm damage.
	ld a, [wBattleMonType1]
	push hl
	ld hl, .SandstormImmuneTypes
	ld de, 1
	call IsInArray
	pop hl
	jr c, .greatly_discourage

	ld a, [wBattleMonType2]
	push hl
	ld hl, .SandstormImmuneTypes
	ld de, 1
	call IsInArray
	pop hl
	jr c, .greatly_discourage

; Discourage this move if player's HP is below 50%.
	call AICheckPlayerHalfHP
	jr nc, .discourage

; 50% chance to encourage this move otherwise.
	call AI_50_50
	ret c

	dec [hl]
	ret

.greatly_discourage
	inc [hl]
.discourage
	inc [hl]
	ret

.SandstormImmuneTypes:
	db ROCK
	db GROUND
	db STEEL
	db -1 ; end

AI_Smart_Endure:
; Greatly discourage this move if the enemy already used Protect.
	ld a, [wEnemyProtectCount]
	and a
	jr nz, .greatly_discourage

; Greatly discourage this move if the enemy's HP is full.
	call AICheckEnemyMaxHP
	jr c, .greatly_discourage

; Discourage this move if the enemy's HP is at least 25%.
	call AICheckEnemyQuarterHP
	jr c, .discourage

; If the enemy has Reversal...
	ld b, EFFECT_REVERSAL
	call AIHasMoveEffect
	jr nc, .no_reversal

; ...80% chance to greatly encourage this move.
	call AI_80_20
	ret c

	dec [hl]
	dec [hl]
	dec [hl]
	ret

.no_reversal
; If the enemy is not locked on, do nothing.
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_LOCK_ON, a
	ret z

; 50% chance to greatly encourage this move.
	call AI_50_50
	ret c

	dec [hl]
	dec [hl]
	ret

.greatly_discourage
	inc [hl]
.discourage
	inc [hl]
	ret

AI_Smart_FuryCutter:
; Encourage this move based on Fury Cutter's count.

	ld a, [wEnemyFuryCutterCount]
	and a
	jr z, AI_Smart_Rollout
	dec [hl]

	cp 2
	jr c, AI_Smart_Rollout
	dec [hl]
	dec [hl]

	cp 3
	jr c, AI_Smart_Rollout
	dec [hl]
	dec [hl]
	dec [hl]

	; fallthrough

AI_Smart_Rollout:
; Rollout, Fury Cutter

; 80% chance to discourage this move if the enemy is in love, confused, or paralyzed.
	ld a, [wEnemySubStatus1]
	bit SUBSTATUS_IN_LOVE, a
	jr nz, .maybe_discourage

	ld a, [wEnemySubStatus3]
	bit SUBSTATUS_CONFUSED, a
	jr nz, .maybe_discourage

	ld a, [wEnemyMonStatus]
	bit PAR, a
	jr nz, .maybe_discourage

; 80% chance to discourage this move if the enemy's HP is below 25%,
; or if accuracy or evasion modifiers favour the player.
	call AICheckEnemyQuarterHP
	jr nc, .maybe_discourage

	ld a, [wEnemyAccLevel]
	cp BASE_STAT_LEVEL
	jr c, .maybe_discourage
	ld a, [wPlayerEvaLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .maybe_discourage

; 80% chance to greatly encourage this move otherwise.
	call Random
	cp 79 percent - 1
	ret nc
	dec [hl]
	dec [hl]
	ret

.maybe_discourage
	call AI_80_20
	ret c
	inc [hl]
	ret

AI_Smart_Swagger:
AI_Smart_Attract:
; 80% chance to encourage this move during the first turn of player's Pokemon.
; 80% chance to discourage this move otherwise.

	ld a, [wPlayerTurnsTaken]
	and a
	jr z, .first_turn

	call AI_80_20
	ret c
	inc [hl]
	ret

.first_turn
	call Random
	cp 79 percent - 1
	ret nc
	dec [hl]
	ret

AI_Smart_Safeguard:
; 80% chance to discourage this move if player's HP is below 50%.

	call AICheckPlayerHalfHP
	ret c
	call AI_80_20
	ret c
	inc [hl]
	ret

AI_Smart_Magnitude:
AI_Smart_Earthquake:
; Greatly encourage this move if the player is underground and the enemy is faster.
	ld a, [wLastPlayerCounterMove]
	cp DIG
	ret nz

	ld a, [wPlayerSubStatus3]
	bit SUBSTATUS_UNDERGROUND, a
	jr z, .could_dig

	call AICompareSpeed
	ret nc
	dec [hl]
	dec [hl]
	ret

.could_dig
	; Try to predict if the player will use Dig this turn.

	; 50% chance to encourage this move if the enemy is slower than the player.
	call AICompareSpeed
	ret c

	call AI_50_50
	ret c

	dec [hl]
	ret

AI_Smart_BatonPass:
; Discourage this move if the player hasn't shown super-effective moves against the enemy.
; Consider player's type(s) if its moves are unknown.

	push hl
	callfar CheckPlayerMoveTypeMatchups
	ld a, [wEnemyAISwitchScore]
	cp BASE_AI_SWITCH_SCORE
	pop hl
	ret c
	inc [hl]
	ret

AI_Smart_Pursuit:
; 50% chance to greatly encourage this move if player's HP is below 25%.
; 80% chance to discourage this move otherwise.

	call AICheckPlayerQuarterHP
	jr nc, .encourage
	call AI_80_20
	ret c
	inc [hl]
	ret

.encourage
	call AI_50_50
	ret c
	dec [hl]
	dec [hl]
	ret

AI_Smart_RapidSpin:
; 80% chance to greatly encourage this move if the enemy is
; trapped (Bind effect), seeded, or scattered with spikes.

	ld a, [wEnemyWrapCount]
	and a
	jr nz, .encourage

	ld a, [wEnemySubStatus4]
	bit SUBSTATUS_LEECH_SEED, a
	jr nz, .encourage

	ld a, [wEnemyScreens]
	bit SCREENS_SPIKES, a
	ret z

.encourage
	call AI_80_20
	ret c

	dec [hl]
	dec [hl]
	ret

AI_Smart_HiddenPower:
	push hl
	ld a, 1
	ldh [hBattleTurn], a

; Calculate Hidden Power's type and base power based on enemy's DVs.
	callfar HiddenPowerDamage
	callfar BattleCheckTypeMatchup
	pop hl

; Discourage Hidden Power if not very effective.
	ld a, [wTypeMatchup]
	cp EFFECTIVE
	jr c, .bad

; Discourage Hidden Power if its base power	is lower than 50.
	ld a, d
	cp 50
	jr c, .bad

; Encourage Hidden Power if super-effective.
	ld a, [wTypeMatchup]
	cp EFFECTIVE + 1
	jr nc, .good

; Encourage Hidden Power if its base power is 70.
	ld a, d
	cp 70
	ret c

.good
	dec [hl]
	ret

.bad
	inc [hl]
	ret

AI_Smart_RainDance:
; Greatly discourage this move if it would favour the player type-wise.
; Particularly, if the player is a Water-type.
	ld a, [wBattleMonType1]
	cp WATER
	jr z, AIBadWeatherType
	cp FIRE
	jr z, AIGoodWeatherType

	ld a, [wBattleMonType2]
	cp WATER
	jr z, AIBadWeatherType
	cp FIRE
	jr z, AIGoodWeatherType

	push hl
	ld hl, RainDanceMoves
	jr AI_Smart_WeatherMove

INCLUDE "data/battle/ai/rain_dance_moves.asm"

AI_Smart_SunnyDay:
; Greatly discourage this move if it would favour the player type-wise.
; Particularly, if the player is a Fire-type.
	ld a, [wBattleMonType1]
	cp FIRE
	jr z, AIBadWeatherType
	cp WATER
	jr z, AIGoodWeatherType

	ld a, [wBattleMonType2]
	cp FIRE
	jr z, AIBadWeatherType
	cp WATER
	jr z, AIGoodWeatherType

	push hl
	ld hl, SunnyDayMoves

	; fallthrough

AI_Smart_WeatherMove:
; Rain Dance, Sunny Day

; Greatly discourage this move if the enemy doesn't have
; one of the useful Rain Dance or Sunny Day moves.
	call AIHasMoveInArray
	pop hl
	jr nc, AIBadWeatherType

; Greatly discourage this move if player's HP is below 50%.
	call AICheckPlayerHalfHP
	jr nc, AIBadWeatherType

; 50% chance to encourage this move otherwise.
	call AI_50_50
	ret c

	dec [hl]
	ret

AIBadWeatherType:
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AIGoodWeatherType:
; Rain Dance, Sunny Day

; Greatly encourage this move if it would disfavour the player type-wise and player's HP is above 50%...
	call AICheckPlayerHalfHP
	ret nc

; ...as long as one of the following conditions meet:
; It's the first turn of the player's Pokemon.
	ld a, [wPlayerTurnsTaken]
	and a
	jr z, .good

; Or it's the first turn of the enemy's Pokemon.
	ld a, [wEnemyTurnsTaken]
	and a
	ret nz

.good
	dec [hl]
	dec [hl]
	ret

INCLUDE "data/battle/ai/sunny_day_moves.asm"

AI_Smart_BellyDrum:
; Dismiss this move if enemy's attack is higher than +2 or if enemy's HP is below 50%.
; Else, discourage this move if enemy's HP is not full.

	ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 3
	jr nc, .discourage

	call AICheckEnemyMaxHP
	ret c

	inc [hl]

	call AICheckEnemyHalfHP
	ret c

.discourage
	ld a, [hl]
	add 5
	ld [hl], a
	ret

AI_Smart_PsychUp:
	push hl
	ld hl, wEnemyAtkLevel
	ld b, NUM_LEVEL_STATS
	ld c, 100

; Calculate the sum of all enemy's stat level modifiers. Add 100 first to prevent underflow.
; Put the result in c. c will range between 58 and 142.
.enemy_loop
	ld a, [hli]
	sub BASE_STAT_LEVEL
	add c
	ld c, a
	dec b
	jr nz, .enemy_loop

; Calculate the sum of all player's stat level modifiers. Add 100 first to prevent underflow.
; Put the result in d. d will range between 58 and 142.
	ld hl, wPlayerAtkLevel
	ld b, NUM_LEVEL_STATS
	ld d, 100

.player_loop
	ld a, [hli]
	sub BASE_STAT_LEVEL
	add d
	ld d, a
	dec b
	jr nz, .player_loop

; Greatly discourage this move if enemy's stat levels are higher than player's (if c>=d).
	ld a, c
	sub d
	pop hl
	jr nc, .discourage

; Else, 80% chance to encourage this move unless player's accuracy level is lower than -1...
	ld a, [wPlayerAccLevel]
	cp BASE_STAT_LEVEL - 1
	ret c

; ...or enemy's evasion level is higher than +0.
	ld a, [wEnemyEvaLevel]
	cp BASE_STAT_LEVEL + 1
	ret nc

	call AI_80_20
	ret c

	dec [hl]
	ret

.discourage
	inc [hl]
	inc [hl]
	ret

AI_Smart_MirrorCoat:
	push hl
	ld hl, wPlayerUsedMoves
	ld c, NUM_MOVES
	ld b, 0

.playermoveloop
	ld a, [hli]
	and a
	jr z, .skipmove

	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .skipmove

	ld a, [wEnemyMoveStruct + MOVE_TYPE]
	cp SPECIAL
	jr c, .skipmove

	inc b

.skipmove
	dec c
	jr nz, .playermoveloop

	pop hl
	ld a, b
	and a
	jr z, .discourage

	cp 3
	jr nc, .encourage

	ld a, [wLastPlayerCounterMove]
	and a
	jr z, .done

	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .done

	ld a, [wEnemyMoveStruct + MOVE_TYPE]
	cp SPECIAL
	jr c, .done

.encourage
	call Random
	cp 39 percent + 1
	jr c, .done
	dec [hl]

.done
	ret

.discourage
	inc [hl]
	ret

AI_Smart_Twister:
AI_Smart_Gust:
; Greatly encourage this move if the player is flying and the enemy is faster.
	ld a, [wLastPlayerCounterMove]
	cp FLY
	ret nz
	cp SKY_CLEAVE
	ret nz

	ld a, [wPlayerSubStatus3]
	bit SUBSTATUS_FLYING, a
	jr z, .couldFly

	call AICompareSpeed
	ret nc

	dec [hl]
	dec [hl]
	ret

; Try to predict if the player will use Fly this turn.
.couldFly

; 50% chance to encourage this move if the enemy is slower than the player.
	call AICompareSpeed
	ret c
	call AI_50_50
	ret c
	dec [hl]
	ret

AI_Smart_FutureSight:
; Greatly encourage this move if the player is
; flying or underground, and slower than the enemy.

	call AICompareSpeed
	ret nc

	ld a, [wPlayerSubStatus3]
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	ret z

	dec [hl]
	dec [hl]
	ret

AI_Smart_Stomp:
; 80% chance to encourage this move if the player has used Minimize.

	ld a, [wPlayerMinimized]
	and a
	ret z

	call AI_80_20
	ret c

	dec [hl]
	ret

AI_Smart_Solarbeam:
; 80% chance to encourage this move when it's sunny.
; 90% chance to discourage this move when it's raining.

	ld a, [wBattleWeather]
	cp WEATHER_SUN
	jr z, .encourage

	cp WEATHER_RAIN
	ret nz

	call Random
	cp 10 percent
	ret c

	inc [hl]
	inc [hl]
	ret

.encourage
	call AI_80_20
	ret c

	dec [hl]
	dec [hl]
	ret

AI_Smart_Thunder:
; 90% chance to discourage this move when it's sunny.

	ld a, [wBattleWeather]
	cp WEATHER_SUN
	ret nz

	call Random
	cp 10 percent
	ret c

	inc [hl]
	ret

AI_Smart_HolyArmour:
; don't go past +3
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 3
	jr nc, .discourage

; discourage if afflicted with toxic
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr nz, .discourage

; strongly encourage to +2
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .strongEncourage
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .strongEncourage

; strongly encourage if player has boosted offenses
	ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .strongEncourage
	ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .strongEncourage

; otherwise encourage to +3
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 3
	jr c, .encourage

.strongEncourage
    dec [hl]
    dec [hl]
.encourage
	dec [hl]
	ret
.discourage
	inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AI_Smart_FuriousWill:
; don't go past +4
    ld a, [wEnemySAtkLevel]
	cp BASE_STAT_LEVEL + 4
	jr nc, .discourage

; strongly encourage if player has boosted SpAtk
	ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .strongEncourage

; encourage to +2
    ld a, [wEnemySAtkLevel]
    cp BASE_STAT_LEVEL + 2
    jr c, .encourage
	ld a, [wEnemySDefLevel]
    cp BASE_STAT_LEVEL + 2
    jr c, .encourage

; discourage after +2 if afflicted with toxic
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr nz, .discourage

    ret

.strongEncourage
    dec [hl]
.encourage
    dec [hl]
	dec [hl]
	ret
.discourage
    inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AI_Smart_QuiverDance:
AI_Smart_CalmMind:
; don't go past +4
    ld a, [wEnemySAtkLevel]
	cp BASE_STAT_LEVEL + 4
	jr c, .continue
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 4
	jp nc, .discourage

.continue
; don't use if we are at risk of being KOd by boosted player, just attack them
; does player have boosted attack
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr c, .special
; does enemy have non-boosted defense
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .special
    jr .dontBoost
.special
    call AICompareSpeed
    jr nc, .slower
; does player have boosted special attack and enemy faster
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 4
	jr c, .continue2
	jr .checkSDef
.slower
; does player have boosted special attack and enemy slower
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .continue2
.checkSDef
; does enemy have non-boosted special defense
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .continue2
.dontBoost
; is player SLP or FRZ
	ld a, [wBattleMonStatus]
	and SLP
	jr nz, .continue2
	bit FRZ, a
	jr nz, .continue2
; is the player behind a sub
    ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a	;check for substitute bit
	jr nz, .discourage
; is player attacking
	ld a, [wPlayerMoveStruct + MOVE_POWER]
	and a
	jr nz, .discourage

.continue2
; encourage to +1, strongly encourage if player has boosted SpAtk
    ld a, [wEnemySAtkLevel]
    cp BASE_STAT_LEVEL + 1
    jr nc, .checkToxic ;
	ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .strongEncourage
	jr .encourage

; discourage after +1 if afflicted with toxic
.checkToxic
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr nz, .discourage

; discourage after +1 if player has boosted attack
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .discourage

    ret

.strongEncourage
    dec [hl]
.encourage
    dec [hl]
	dec [hl]
	ret
.discourage
    inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	ret

;CanPlayerKO:
;    ld de, wEnemyMonMoves
;	ld b, NUM_MOVES + 1
;.checkmove
;	dec b ; b is num moves on 1st pass
;	ret z ; if b os 0 return we are done
;	ld a, [de] ; load the move struct
;	and a
;	ret z ; return if no move
;	inc de ; increment to next move
;	call AIGetEnemyMove
;	ld a, [wPlayerMoveStruct + MOVE_POWER]
;	and a
;	jr z, .checkmove
;   ld a, 0
;	ldh [hBattleTurn], a
;	push hl
;	push de
;	push bc
;	callfar PlayerAttackDamage
;	callfar BattleCommand_DamageCalc
;	callfar BattleCommand_Stab
;	ld a, [wCurDamage + 1]
;	ld c, a ; c is curDamage upper
;	ld a, [wCurDamage]
;	ld b, a ; b is curDamage lower
;	ld a, [wEnemyMonHP + 1]
;	cp c ; compare upper
;	ld a, [wEnemyMonHP]
;	sbc b ; compare lower and set flag
;	pop bc
;	pop de
;	pop hl
;   jp nc, .checkmove
;   ret

AI_Smart_DragonDance:
AI_Smart_SwordsDance:
; don't go past +4
	ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 4
	jr nc, .discourage

; don't use if we are at risk of being KOd by boosted player, just attack them
; physical
; does player have boosted  attack
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .special
; does enemy have non-boosted defense
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .special
    jr .dontBoost
.special
; does player have boosted special attack
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .continue
; does enemy have non-boosted special defense
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .continue
.dontBoost
; is player SLP or FRZ
	ld a, [wBattleMonStatus]
	and SLP
	jr nz, .continue
	bit FRZ, a
	jr nz, .continue
; is player attacking
	ld a, [wPlayerMoveStruct + MOVE_POWER]
	and a
	jr nz, .discourage
; is the player behind a sub
    ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a	;check for substitute bit
	jr nz, .discourage
; if already at +2, 80% chance to discourage
    ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr nc, .discourage80

.continue
; if already at +2 and player is faster, 80% chance to discourage, unless Arceus
    ld a, [wEnemyMonSpecies]
    cp ARCEUS
    jr z, .continue2
    call AICompareSpeed
    jr c, .continue2
    ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .discourage80

.continue2
; encourage to get to +1
	ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr c, .encourage

; discourage after +1 if afflicted with toxic
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr nz, .discourage

    ret

.encourage
	dec [hl]
	dec [hl]
	ret
.discourage80
    call AI_80_20
    ret c
.discourage
	inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AI_Smart_Barrier:
; don't go past +4
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 4
	jr nc, .discourage

; discourage if player has boosted SpAtk
	ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr nc, .discourage

; discourage if afflicted with toxic
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr nz, .discourage

; strongly encourage if player has boosted attack
	ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .strongEncourage

; strongly encourage to +2 if player mon has higher attack than special attack
; otherwise discourage
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 2
	ret nc
	push hl
	push bc
	push de
; Get the pointer for the player's Pokémon's base Attack
	ld a, [wBattleMonSpecies]
	ld hl, BaseData + BASE_ATK
	ld bc, BASE_DATA_SIZE
	call AddNTimes
; Get the Pokémon's base Attack
	ld a, BANK(BaseData)
	call GetFarByte
	ld d, a
; Get the pointer for the player's Pokémon's base Special Attack
	ld bc, BASE_SAT - BASE_ATK
	add hl, bc
; Get the Pokémon's base Special Attack
	ld a, BANK(BaseData)
	call GetFarByte
	pop de
	pop bc
	pop hl
; If its base Attack is not greater than its base Special Attack, discourage.
	cp d
	jr nc, .discourage

.strongEncourage
    dec [hl]
    dec [hl]
.encourage
	dec [hl]
	ret
.discourage
	inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AI_Smart_Geomancy:
AI_Smart_NastyPlot:
; don't go past +4
    ld a, [wEnemySAtkLevel]
	cp BASE_STAT_LEVEL + 4
	jr nc, .discourage

; deoxys should always boost once and no more, unless player has sub
    ld a, [wEnemyMonSpecies]
    cp DEOXYS
    jr nz, .notDeoxys
; is the player behind a sub
    ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a	;check for substitute bit
	jr nz, .discourage
; encourage to get to +2 and discourage thereafter
    ld a, [wEnemySAtkLevel]
    cp BASE_STAT_LEVEL + 2
    jr c, .encourage
    jr .discourage

.notDeoxys
; don't use if we are at risk of being KOd by boosted player, just attack them
; physical
; does player have boosted attack
    ld a, [wPlayerAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .special
; does enemy have non-boosted defense
    ld a, [wEnemyDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .special
    jr .dontBoost
.special
; does player have boosted special attack
    ld a, [wPlayerSAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .continue
; does enemy have non-boosted special defense
    ld a, [wEnemySDefLevel]
	cp BASE_STAT_LEVEL + 1
	jr nc, .continue
.dontBoost
; is player SLP or FRZ
	ld a, [wBattleMonStatus]
	and SLP
	jr nz, .continue
	bit FRZ, a
	jr nz, .continue
; is the player behind a sub
    ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a	;check for substitute bit
	jr nz, .discourage
; is player attacking
	ld a, [wPlayerMoveStruct + MOVE_POWER]
	and a
	jr nz, .discourage
; if already at +2, 80% chance to discourage
    ld a, [wEnemySAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr nc, .discourage80

.continue
; if already at +2 and player is faster, 80% chance to discourage
    call AICompareSpeed
    jr c, .continue2
    ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr nc, .discourage80

.continue2
; encourage to get to +2
    ld a, [wEnemySAtkLevel]
	cp BASE_STAT_LEVEL + 2
	jr c, .encourage

; discourage after +2 if afflicted with toxic
.checkToxic
    ld a, BATTLE_VARS_SUBSTATUS5
	call GetBattleVar
	bit SUBSTATUS_TOXIC, a
    jr nz, .discourage

    ret
.encourage
    dec [hl]
	dec [hl]
	ret
.discourage80
    call AI_80_20
    ret c
.discourage
    inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AI_Smart_DynamicPunch:
; encourage dynamic punch for machamp
    ld a, [wEnemyMonSpecies]
    cp MACHAMP
    ret nz
	ld a, [wPlayerSubStatus3]
	bit SUBSTATUS_CONFUSED, a
	ret nz ; don't encourage if already confused
    dec [hl]
    dec [hl]
    ret

AICompareSpeed:
; Return carry if enemy is faster than player.

	push bc
	ld a, [wEnemyMonSpeed + 1]
	ld b, a
	ld a, [wBattleMonSpeed + 1]
	cp b
	ld a, [wEnemyMonSpeed]
	ld b, a
	ld a, [wBattleMonSpeed]
	sbc b
	pop bc
	ret

AICheckPlayerMaxHP:
	push hl
	push de
	push bc
	ld de, wBattleMonHP
	ld hl, wBattleMonMaxHP
	jr AICheckMaxHP

AICheckEnemyMaxHP:
	push hl
	push de
	push bc
	ld de, wEnemyMonHP
	ld hl, wEnemyMonMaxHP
	; fallthrough

AICheckMaxHP:
; Return carry if hp at de matches max hp at hl.

	ld a, [de]
	inc de
	cp [hl]
	jr nz, .not_max

	inc hl
	ld a, [de]
	cp [hl]
	jr nz, .not_max

	pop bc
	pop de
	pop hl
	scf
	ret

.not_max
	pop bc
	pop de
	pop hl
	and a
	ret

AICheckPlayerHalfHP:
	push hl
	ld hl, wBattleMonHP
	ld b, [hl]
	inc hl
	ld c, [hl]
	sla c
	rl b
	inc hl
	inc hl
	ld a, [hld]
	cp c
	ld a, [hl]
	sbc b
	pop hl
	ret

AICheckEnemyHalfHP:
	push hl
	push de
	push bc
	ld hl, wEnemyMonHP
	ld b, [hl]
	inc hl
	ld c, [hl]
	sla c
	rl b
	inc hl
	inc hl
	ld a, [hld]
	cp c
	ld a, [hl]
	sbc b
	pop bc
	pop de
	pop hl
	ret

AICheckEnemyQuarterHP:
	push hl
	push de
	push bc
	ld hl, wEnemyMonHP
	ld b, [hl]
	inc hl
	ld c, [hl]
	sla c
	rl b
	sla c
	rl b
	inc hl
	inc hl
	ld a, [hld]
	cp c
	ld a, [hl]
	sbc b
	pop bc
	pop de
	pop hl
	ret

AICheckPlayerQuarterHP:
	push hl
	ld hl, wBattleMonHP
	ld b, [hl]
	inc hl
	ld c, [hl]
	sla c
	rl b
	sla c
	rl b
	inc hl
	inc hl
	ld a, [hld]
	cp c
	ld a, [hl]
	sbc b
	pop hl
	ret

AIHasMoveEffect:
; Return carry if the enemy has move b.

	push hl
	ld hl, wEnemyMonMoves
	ld c, NUM_MOVES

.checkmove
	ld a, [hli]
	and a
	jr z, .no

	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp b
	jr z, .yes

	dec c
	jr nz, .checkmove

.no
	pop hl
	and a
	ret

.yes
	pop hl
	scf
	ret

AIHasMoveInArray:
; Return carry if the enemy has a move in array hl.

	push hl
	push de
	push bc

.next
	ld a, [hli]
	cp -1
	jr z, .done

	ld b, a
	ld c, NUM_MOVES + 1
	ld de, wEnemyMonMoves

.check
	dec c
	jr z, .next

	ld a, [de]
	inc de
	cp b
	jr nz, .check

	scf

.done
	pop bc
	pop de
	pop hl
	ret

INCLUDE "data/battle/ai/useful_moves.asm"

AI_Opportunist:
; Discourage stall moves if enemy's HP is below 1/2.
    call AICheckEnemyHalfHP
	jr nc, .lowhp

	ret

.lowhp
	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld c, NUM_MOVES + 1
.checkmove
	inc hl
	dec c
	jr z, .done

	ld a, [de]
	inc de
	and a
	jr z, .done

	push hl
	push de
	push bc
	ld hl, StallMoves
	ld de, 1
	call IsInArray

	pop bc
	pop de
	pop hl
	jr nc, .checkmove

	inc [hl]
	inc [hl]
	inc [hl]
	inc [hl]
	jr .checkmove

.done
	ret

INCLUDE "data/battle/ai/stall_moves.asm"


AI_Aggressive:
; discourage all damaging moves except the one that deals the most damage

; Figure out which attack does the most damage and put it in c.
	ld hl, wEnemyMonMoves
	ld bc, 0
	ld de, 0
.checkmove
	inc b
	ld a, b
	cp NUM_MOVES + 1
	jr z, .gotstrongestmove

	ld a, [hli]
	and a
	jr z, .gotstrongestmove

	push hl
	push de
	push bc
	call AIGetEnemyMove
	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .nodamage
	call AIDamageCalc
	pop bc
	pop de
	pop hl

; Update current move if damage is highest so far
; don't encourage explosion
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_SELFDESTRUCT
	jr z, .checkmove

	ld a, [wCurDamage + 1]
	cp e
	ld a, [wCurDamage]
	sbc d
	jr c, .checkmove

	ld a, [wCurDamage + 1]
	ld e, a
	ld a, [wCurDamage]
	ld d, a
	ld c, b
	jr .checkmove

.nodamage
	pop bc
	pop de
	pop hl
	jr .checkmove

.gotstrongestmove
; Nothing we can do if no attacks did damage.
	ld a, c
	and a
	jr z, .done

; Discourage moves that do less damage unless they're reckless too.
	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld b, 0
.checkmove2
	inc b
	ld a, b
	cp NUM_MOVES + 1
	jr z, .done

; Ignore this move if it is the highest damaging one.
	cp c
	ld a, [de]
	inc de
	inc hl
	jr z, .checkmove2

	call AIGetEnemyMove

; Ignore this move if its power is 0 or 1.
; Moves such as Seismic Toss, Hidden Power,
; Counter and Fissure have a base power of 1.
	ld a, [wEnemyMoveStruct + MOVE_POWER]
	cp 2
	jr c, .checkmove2

; Ignore this move if it is reckless.
	;push hl
	;push de
	;push bc
	;ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	;ld hl, RecklessMoves
	;ld de, 1
	;call IsInArray
	;pop bc
	;pop de
	;pop hl
	;jr c, .checkmove2

; If we made it this far, discourage this move.
	inc [hl]
	jr .checkmove2

.done
	ret

INCLUDE "data/battle/ai/reckless_moves.asm"

AIDamageCalc:
	ld a, 1
	ldh [hBattleTurn], a
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	ld de, 1
	ld hl, ConstantDamageEffects
	call IsInArray
	jr nc, .notconstant
	callfar BattleCommand_ConstantDamage
	ret

.notconstant
	callfar EnemyAttackDamage
	callfar BattleCommand_DamageCalc
	callfar BattleCommand_Stab
	ret

INCLUDE "data/battle/ai/constant_damage_effects.asm"

AI_Cautious:
; 90% chance to discourage moves with residual effects after the first turn.

	ld a, [wEnemyTurnsTaken]
	and a
	ret z

	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld c, NUM_MOVES + 1
.loop
	inc hl
	dec c
	ret z

	ld a, [de]
	inc de
	and a
	ret z

	push hl
	push de
	push bc
	ld hl, ResidualMoves
	ld de, 1
	call IsInArray

	pop bc
	pop de
	pop hl
	jr nc, .loop

	call Random
	cp 90 percent + 1
	ret nc

	inc [hl]
	jr .loop

INCLUDE "data/battle/ai/residual_moves.asm"


AI_Status:
; Dismiss status moves that don't affect the player.

	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b
	ret z

	inc hl
	ld a, [de]
	and a
	ret z

	inc de
	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_TOXIC
	jr z, .poisonimmunity
	cp EFFECT_POISON
	jr z, .poisonimmunity
	cp EFFECT_SLEEP
	jr z, .typeimmunity
	cp EFFECT_PARALYZE
	jr z, .typeimmunity

	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .checkmove

	jr .typeimmunity

.poisonimmunity
	ld a, [wBattleMonType1]
	cp POISON
	jr z, .immune
	ld a, [wBattleMonType2]
	cp POISON
	jr z, .immune

.typeimmunity
	push hl
	push bc
	push de
	ld a, 1
	ldh [hBattleTurn], a
	callfar BattleCheckTypeMatchup
	pop de
	pop bc
	pop hl

	ld a, [wTypeMatchup]
	and a
	jr nz, .checkmove

.immune
	call AIDiscourageMove
	jr .checkmove


AI_Risky:
; Use any move that will KO the target.
; Risky moves will often be an exception (see below).

	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld c, NUM_MOVES + 1
.checkmove
	inc hl
	dec c
	ret z

	ld a, [de]
	inc de
	and a
	ret z

	push de
	push bc
	push hl
	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .nextmove

; Don't use risky moves at max hp.
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	ld de, 1
	ld hl, RiskyEffects
	call IsInArray
	jr nc, .checkko

	call AICheckEnemyMaxHP
	jr c, .nextmove

; Else, 80% chance to exclude them.
	call Random
	cp 79 percent - 1
	jr c, .nextmove

.checkko
	call AIDamageCalc

	ld a, [wCurDamage + 1]
	ld e, a
	ld a, [wCurDamage]
	ld d, a
	ld a, [wBattleMonHP + 1]
	cp e
	ld a, [wBattleMonHP]
	sbc d
	jr nc, .nextmove

	pop hl
rept 5
	dec [hl]
endr
	push hl

.nextmove
	pop hl
	pop bc
	pop de
	jr .checkmove

INCLUDE "data/battle/ai/risky_effects.asm"


AI_None:
	ret

AIDiscourageMove:
	ld a, [hl]
	add 10
	ld [hl], a
	ret

AIGetEnemyMove:
; Load attributes of move a into ram

	push hl
	push de
	push bc
	dec a
	ld hl, Moves
	ld bc, MOVE_LENGTH
	call AddNTimes

	ld de, wEnemyMoveStruct
	ld a, BANK(Moves)
	call FarCopyBytes

	pop bc
	pop de
	pop hl
	ret

AI_80_20:
	call Random
	cp 20 percent - 1
	ret

AI_50_50:
	call Random
	cp 50 percent + 1
	ret
