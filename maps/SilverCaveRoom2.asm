	object_const_def
	const SILVERCAVEROOM2_POKE_BALL1
	const SILVERCAVEROOM2_POKE_BALL2
	const SILVERCAVEROOM2_POKE_BALL3

SilverCaveRoom2_MapScripts:
	def_scene_scripts

	def_callbacks

SilverCaveRoom2Calcium:
	itemball CALCIUM

SilverCaveRoom2UltraBall:
	itemball ULTRA_BALL

SilverCaveRoom2PPUp:
	itemball PP_UP

SilverCaveRoom2HiddenMaxPotion:
	hiddenitem MAX_POTION, EVENT_SILVER_CAVE_ROOM_2_HIDDEN_MAX_POTION

SilverCaveRoom2_MapEvents:
	db 0, 0 ; filler

	def_warp_events
	warp_event 17, 55, SILVER_CAVE_ROOM_1, 2
	warp_event 11,  1, SILVER_CAVE_ROOM_3, 1
	warp_event 13, 45, SILVER_CAVE_ITEM_ROOMS, 2
	warp_event 23, 27, SILVER_CAVE_ITEM_ROOMS, 1

	def_coord_events

	def_bg_events
	bg_event 14, 55, BGEVENT_ITEM, SilverCaveRoom2HiddenMaxPotion

	def_object_events
	object_event 24, 34, SPRITE_POKE_BALL, SPRITEMOVEDATA_STILL, 0, 0, -1, -1, 0, OBJECTTYPE_ITEMBALL, 0, SilverCaveRoom2Calcium, EVENT_SILVER_CAVE_ROOM_2_CALCIUM
	object_event 22, 48, SPRITE_POKE_BALL, SPRITEMOVEDATA_STILL, 0, 0, -1, -1, 0, OBJECTTYPE_ITEMBALL, 0, SilverCaveRoom2UltraBall, EVENT_SILVER_CAVE_ROOM_2_ULTRA_BALL
	object_event  4, 44, SPRITE_POKE_BALL, SPRITEMOVEDATA_STILL, 0, 0, -1, -1, 0, OBJECTTYPE_ITEMBALL, 0, SilverCaveRoom2PPUp, EVENT_SILVER_CAVE_ROOM_2_PP_UP
