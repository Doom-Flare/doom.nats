# doom.nats:check/distance —— 距离判定（reason=1 / 2 / 10）
# 24 格球内不得有玩家（源码：distSq <= 576 拒）
execute if entity @a[gamemode=!spectator,distance=..24] run function doom.nats:check/fail {reason:1}
# despawnDistance 上界（源码：!canSpawnFarFromPlayer() && d² > despawnDistance² ⇒ 拒）
#   canSpawnFarFromPlayer = (category == CREATURE || MISC)（EntityType.Builder:1655）
#   ⇒ **creature 整条豁免**：原版牛/羊/猪/鸡在 260 格外照样生成，这里同样不设上界。
#   其余类别按各自 despawnDistance 判（water_ambient=64，其他=128），取 $cfg.dist_<cat>。
#   v4.31 前这里是硬编码 distance=..128 且不分类别 ⇒ 玩家离地 128 格后地表候选点全被拒（空中零生成）。
scoreboard players set $chk.dist doom.nats 128
execute if score $chk.ok doom.nats matches 1 run function doom.nats:check/dist_pick with storage doom.nats:sel
execute if score $chk.ok doom.nats matches 1 if score $chk.dist doom.nats matches 1.. unless data storage doom.nats:sel {cat:"creature"} run execute store result storage doom.nats:dg dist int 1 run scoreboard players get $chk.dist doom.nats
execute if score $chk.ok doom.nats matches 1 if score $chk.dist doom.nats matches 1.. unless data storage doom.nats:sel {cat:"creature"} run function doom.nats:check/dist_gate with storage doom.nats:dg
data remove storage doom.nats:dg dist
# 世界出生点 24 格内同样不得生成（源码同一条 if 的第二个分支；$cfg.spawn24≥1 且作者声明了坐标才生效）
execute if score $chk.ok doom.nats matches 1 if score $cfg.spawn24 doom.nats matches 1.. run function doom.nats:check/spawn24
