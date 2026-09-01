# DomPanion

Copyright © 2026 Dominik Fischer

Companion Expert Advisor for MetaTrader 5. It does **not** open trades. It watches yours and closes anything that breaks the rules you set — lot size, extra positions, money TP/SL, losing hours, daily start-balance floor.

Built for high-leverage, low-balance discretionary trading: the pattern of making a few hundred / a few thousand and then giving it back by scaling into losers and oversizing.

## Disclaimer — read this first

**Trading is risky.** You can lose some or all of your capital, including on high-leverage accounts. This software is a companion tool, not financial advice, not a trading system, and not a guarantee of anything.

**Use it entirely at your own risk.** The author (Dominik Fischer) and contributors take **no responsibility and no liability** for any loss, damage, missed trade, failed close, software bug, broker behaviour, or other outcome from using, misconfiguring, or relying on DomPanion — including after you have tested it.

**Test extensively on demo accounts** before even considering a live account. Demo results do not prove the tool is safe or correct on live. Even after thorough demo testing, **you still use it at your own risk; we still accept no responsibility or liability.**

If you cannot afford to lose the money, do not trade, and do not use this tool.

## Install

Copy this folder to:

```
[MT5 data folder]/MQL5/Experts/DomPanion/
```

so the layout is:

```
MQL5/Experts/DomPanion/DomPanion.mq5
MQL5/Experts/DomPanion/Include/*.mqh
```

Open `DomPanion.mq5` in MetaEditor and compile. Attach the EA to the chart you trade. Turn **Algo Trading** on.

The compiled `.ex5` is standalone. `Include/` is only needed at compile time.

## What it does

1. **Time intelligence** — Groups closed trades by **entry hour**. The CLOCK heatmap shows where you typically win and lose. Optional: immediately close anything opened in a losing hour.
2. **Lot cap** — Example: 2000 account currency required per 0.01 lot. With 2300 on the account, 0.02 is closed at once.
3. **Money TP / breathing SL** — Take-profit and stop are in money per 0.01, scaled by volume. A 3× breath multiplier lets a trade go 2–3× the target against you before it is killed. That is the room you use to recover, with a hard ceiling so one failure cannot wipe the account.
4. **Scale-in block** — If one position is open, a 2nd/3rd is closed (hedging). On netting, an add is cut back to the previous volume. Matching pending orders are deleted.
5. **Daily goal lock (optional)** — After today’s P/L hits a money target (e.g. 400), new trades are blocked. Optional flatten. Optional daily max loss.
6. **Daily start floor (optional)** — You set a seed for the day (e.g. 600). If **account equity** comes within a buffer of that seed (default 3% → trigger at 618), every matching trade is closed and any new trade is closed for the rest of the broker day. The lock resets at midnight; the seed value stays what you configured.

## How it works

All decisions go through one evaluation loop (`OnTick` / `OnTimer` / `OnTradeTransaction`) and **one close queue**. Reentry from `PositionClose` is ignored and replayed once. Filling mode falls back IOC → FOK → RETURN.

Money P/L includes floating profit, swap, commission, fee, and realized partials.

If the terminal dies, optional **broker SL at the hard kill** and **broker TP at the money TP** are the offline safety net. Virtual checks still run while the EA is attached.

**Breathing band** (defaults: 2 / 2 / 3× per 0.01 lot):

| Zone | At 0.01 | Action |
|---|---|---|
| TARGET | ≥ +2 | Close |
| BREATH | 0 to −2 | Leave it |
| AMBER | −2 to −6 | Still allowed (optional timer) |
| KILL | ≤ −6 | Close |

On 0.10 lots that is +20 / −20 / −60.

STATS on the panel: **Mo–Su** (best days) and **00–23** (best hours). Green = you made money, red = you lost. **Play** / **Skip** is the short version. Hours are by **entry time**. Block is off by default until you trust it.

As soon as a **second** same-way trade is open, SL and TP on those trades are removed. One leg taking profit while the other is a loser does not make sense. The basket then exits together (add-to-losers BE, or your money TP if you only have one ticket).

## Settings

MT5 → Inputs. Nine groups. Read the left column; the right column is the value.

| Group | What you set |
|---|---|
| **1 Practice** | Don't close — just show |
| **2 Screen** | Panel, corner, pop-up, phone |
| **3 Lots** | Money for 0.01 lot |
| **4 Profit** | Win per 0.01, room per 0.01, close after this many rooms |
| **5 Trades** | Only 1 trade |
| **6 Hours** | Show stats. Kill bad-hour trades (leave off at first). Bad hours / good hours |
| **7 Today** | Win goal. Max loss (`0` = off) |
| **8 Start money** | I started with. Wait until up %. Close if only up % |
| **9 Add to losers** | After you add a 2nd trade the same way, it keeps adding at 2x, 3x, 4x that gap. Closes all at break-even + extra profit % of balance. Max trades. Lot per add (`0` = same as your 2nd). |
| **10 Extra** | Leave it |

Example for start money `600`: wait until up `5` (630), then close if only up `3` (618). Wait % must be bigger than close %.

**Add to losers:** You open a trade, it goes against you, you add a second the same way. Gap is locked. Further adds at 2×, 3×, 4×… of that gap. Combined profit ≥ extra % of balance → close the basket.

How the rules stack (highest first):

1. Start-money floor / daily max loss — flatten everything, including a grid.
2. Add-to-losers BE — close that basket only.
3. Daily win goal — if flatten is on, flatten everything; if not, keep the grid but **no new adds**.
4. Bad hours — no new trades and no new grid adds; an already-running grid is left for BE or the floor.
5. Lot cap — a **single** ticket bigger than max is always closed; the grid will not add if total size would exceed max.
6. Only 1 trade — still kills the other direction / other symbols. Same-way adds are allowed while add-to-losers is on.
7. Money TP/SL — on a **single** trade. The moment a second same-way trade exists, SL/TP are cleared and per-trade exits stay off (the basket exits together).

Off by default. High risk. Demo first.

## Live (v1.22)

This is the current public cut. Copy the folder to `MQL5/Experts/DomPanion/`, compile `DomPanion.mq5`, attach, **Algo Trading on**. Test on demo first. Live use is your own risk; see the disclaimer above.

1. **Practice** on for a session if you want. Then off.
2. **Hours → Kill bad-hour trades** leave off until the clock looks right.
3. Lots, profit, and only-1-trade are already on.
4. **Start money**: set **I started with** to today’s real start. Wait until up % must be bigger than close if only up %.
5. **Add to losers** is off. Turn it on only if you understand the grid. **Only 1 trade** can stay on; same-direction adds are allowed, extras the other way are not.

## License

MIT. Copyright © 2026 Dominik Fischer.

The MIT licence’s “as is” / no-warranty terms apply. In addition: trading is risky; this tool is used at your own risk; the author accepts no responsibility or liability for its use, including after demo testing.
