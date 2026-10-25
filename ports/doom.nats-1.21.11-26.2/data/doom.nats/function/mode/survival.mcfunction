# doom.nats:mode/survival —— 生存直用：接管原版自然生成（装载时默认执行）
gamerule spawn_mobs false
scoreboard players set $mode.manual doom.nats 0
# 解除退场锁（core/tick 靠 $mode.off 整函数 return）
scoreboard players set $mode.off doom.nats 0
function doom.nats:circ/snapshot
say [nats] mode/survival —— 已接管自然生成（spawn_mobs=false）
