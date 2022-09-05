	db IGGLYBUFF ; 174

	db  60,  55,  90,  80,  145,  90
	;   hp  atk  def  spd  sat  sdf

	db GHOST, FIRE ; type
	db 45 ; catch rate
	db 234 ; base exp
	db NO_ITEM, NO_ITEM ; items
	db GENDER_F50 ; gender ratio
	db 100 ; unknown 1
	db 10 ; step cycles to hatch
	db 5 ; unknown 2
	INCBIN "gfx/pokemon/igglybuff/front.dimensions"
	dw NULL, NULL ; unused (beta front/back pics)
	db GROWTH_MEDIUM_SLOW ; growth rate
	dn EGG_INDETERMINATE, EGG_INDETERMINATE ; egg groups

    ; tm/hm learnset
	tmhm CURSE, TOXIC, PSYCH_UP, HIDDEN_POWER, SUNNY_DAY, PROTECT, GIGA_DRAIN, FRUSTRATION, RETURN, SHADOW_BALL, SWAGGER, SLEEP_TALK, DREAM_EATER, REST, ATTRACT, NIGHTMARE, FIRE_BLAST
	; end
