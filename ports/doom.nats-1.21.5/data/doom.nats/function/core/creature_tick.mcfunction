# doom.nats:core/creature_tick —— 被动生物的 400 tick 节拍（原版 getGameTime() % 400）
#
# v4.31 P0 修：旧版只在 circ/snapshot（每 20 tick）里采样一次 gametime ⇒ $gt 与 $t 的相位一旦错开，
#   `gametime % 400` 就永远取不到 0（真机实测 $gt 恒落在 {17,37,57,…,397}，一辈子不进 0）
#   ⇒ 被动生物（牛/羊/猪/鸡…）一条都不生成，且只在 1/20 的世界里才会「碰巧」正常。
#   现在改由 core/tick **每 tick** 调用。
# 另：即便每 tick 采样，`gametime % 400 == 0` 也有且只有 1 tick，与 $eff.period 的生成拍不一定重合
#   ⇒ 把门做成 $eff.period 宽的窗口，保证「每 400 tick 有且只有一拍」看到门开（对齐原版语义）。
# $gt = 0 门开 / 1 门关；下游 76 个 mob/biome/*.mcfunction 只判 `matches 0`，语义不变。
#
# ★ 这两行的顺序不能换：窗口内的 $gt 会被算成负数，先归 0 之后又落进 `matches 0..` 被判成门关，
#   真机实测 $gt 恒为 1（门永不开）。必须先判「关门」（>=0 → 1），再判「开门」（<0 → 0）。
execute store result score $gt.now doom.nats run time query gametime
scoreboard players operation $gt.now doom.nats %= $cfg.creature_gate doom.nats
scoreboard players operation $gt doom.nats = $gt.now doom.nats
scoreboard players operation $gt doom.nats -= $eff.period doom.nats
execute if score $gt doom.nats matches 0.. run scoreboard players set $gt doom.nats 1
execute if score $gt doom.nats matches ..-1 run scoreboard players set $gt doom.nats 0
