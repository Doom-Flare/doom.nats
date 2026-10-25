# doom.nats:pos/band_surface_at —— 在 heightmap 定位好的执行位置上读回地表 y，再决定是否接管
#
# 执行位置由 pos/band_surface 的 positioned over 定为「该列最高的 motion_blocking_no_leaves 方块之上一格」，
#   与 chunk.getHeight(WORLD_SURFACE, x, z) 同值（真机实测：草方块在 -61 的一列取到 -60）。
# 读回绝对 y 只能借一个临时 marker：命令没有「把执行位置写进记分板」的形式，
#   而 data get entity @s Pos[1] 读的始终是实体位置（@s 仍是玩家，不是执行位置）。
# 先垫 2147483647 再读：万一 marker 没生成，store result 不落笔，sy 保持极大值 ⇒ 下面的 < 判定不成立 ⇒ 干净跳过。
scoreboard players set $band.sy doom.nats 2147483647
summon minecraft:marker ~ ~ ~ {Tags:["doom.nats.hm"]}
execute as @e[type=minecraft:marker,tag=doom.nats.hm,limit=1,sort=nearest] store result score $band.sy doom.nats run data get entity @s Pos[1]
kill @e[type=minecraft:marker,tag=doom.nats.hm]
# 地表低于玩家层才接管；玩家在洞穴里（地表在头顶）跳过，保持 v4.30 的整列回退
execute if score $band.sy doom.nats < $py doom.nats run function doom.nats:pos/band_surface_scan
