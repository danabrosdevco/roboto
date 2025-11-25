extends Node
class_name Enums


# CHARACTER INF #
enum Factions{PLAYER, ENEMY, THIRD}
enum ScanModes{RECTANGLE, TOP_DOWN}

enum WorldStates {RUNNING, LOADING, PAUSED}
enum FireModes {SEMI, FULL, MANUAL}
enum AIWeaponTypes {MELEE, HITSCAN, PROJECTILE}
# WORLD OBJECT INF #
enum WorldObjectTypes {CHAR_SPAWN, AI_SPAWN, LEVEL_EXIT, PICKUP, INTERACTIBLE, AI, STATIC_TARGET}
enum PickUpTypes {HEALTH, SHARDS}
enum InteractTypes {HEALTH, SHARDS, BONFIRE}
