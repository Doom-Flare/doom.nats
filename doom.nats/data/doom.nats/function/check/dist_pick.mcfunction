# doom.nats:check/dist_pick [MACRO] —— 按类别取 despawnDistance 上界
#
# 原版 MobCategory 第 5 个构造参数：WATER_AMBIENT = 64，其余 6 类 = 128。
# 值来自 $cfg.dist_<cat>（cfg/apply 从 cfg_defaults.distance 拷入，可被 config.distance 覆盖）。
# 未知类别或配置缺失（持有者无分）时保持调用方预置的 128。
# 用法：function doom.nats:check/dist_pick with storage doom.nats:sel
$execute if score $cfg.dist_$(cat) doom.nats matches 1.. run scoreboard players operation $chk.dist doom.nats = $cfg.dist_$(cat) doom.nats
