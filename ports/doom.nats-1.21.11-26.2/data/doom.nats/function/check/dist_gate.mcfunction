# doom.nats:check/dist_gate [MACRO] —— despawnDistance 上界（reason=2）
#
# 语义同原版 NaturalSpawner.isValidSpawnPostitionForType 的第 2 个分支：
#   !canSpawnFarFromPlayer() && nearestPlayerDistanceSqr > despawnDistance² ⇒ 拒
# 参数 $(dist) 由 check/distance 按类别取好后经 storage doom.nats:dg 传入。
# 用法：function doom.nats:check/dist_gate with storage doom.nats:dg
$execute unless entity @a[gamemode=!spectator,distance=..$(dist)] run function doom.nats:check/fail {reason:2}
