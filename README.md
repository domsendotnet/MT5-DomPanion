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

Losing hours are classified from **entry time**, not the current clock. Block is off by default so you can read the heatmap first.

## Settings

Grouped in the EA Inputs. Each line is a switch or a number — nothing is buried in code.

### 0. General

| Input | Meaning |
|---|---|
| Dry run | Log and paint what would close, without sending orders |
| Manage scope | This chart’s symbol, or every symbol on the account |
| Magic filter | `-1` all, `0` manual only, or a specific magic |
| Enforce on start | Apply rules to positions already open when you attach |
| Close slippage | Points allowed on a market close |
| Log | `0` errors, `1` actions, `2` verbose |

If two instances use “entire account”, the second stands by.

### Dashboard

Corner (top-left / top-right / bottom-left / bottom-right), theme, offsets, width, font, extra scale, and extra gaps so the panel does not cover the price scale or status bar. Size follows DPI and window height.

### 1. Time Intelligence

| Input | Meaning |
|---|---|
| Analyse closed trades | Build the CLOCK from history |
| History window | Days of closed trades (entry hour) |
| Min trades per hour | Sample size before auto-classification |
| Losing win rate | Hour is auto-losing below this % |
| Also losing if net < 0 | Extra auto-losing rule |
| Close trades in losing hours | **Off by default.** Turn on after you trust the CLOCK |
| Hour clock | Server / local / UTC / UTC+offset |
| Force-losing hours | e.g. `0-6,16,22-23` |
| Never-block hours | e.g. `9-11` (wins over auto and force-losing) |

### 2. Lot Size Guard

| Input | Meaning |
|---|---|
| Enable | On/off |
| Balance needed per 0.01 | `floor(balance / this) × 0.01` is the max |
| Lot unit | Keep `0.01` unless the symbol steps differ |
| Cap against | Balance or equity |

### 3. Money TP / SL / Breath

| Input | Meaning |
|---|---|
| Enable | On/off |
| Take profit per 0.01 | Money target |
| 1R stop per 0.01 | Soft (warning) distance |
| Breath multiplier | Hard kill = this × 1R (default 3) |
| Amber timeout | Seconds stuck in 1R–NR before close (`0` = off) |
| Broker hard SL / money TP | Offline safety net |
| Profit lock | After peak hits a % of TP, raise the kill floor (default off) |
| Lock floor in R | `0` = breakeven |

### 4. Scale-in Block

| Input | Meaning |
|---|---|
| Kill 2nd/3rd | Keep the oldest position |
| Scope | This symbol or the whole account |

### 5. Daily Goal Lock

| Input | Meaning |
|---|---|
| Enable | Off by default |
| Daily target | Block new trades once today ≥ this (`0` = off) |
| Flatten | Also close the open trade when the goal hits |
| Daily max loss | Flatten and block if today ≤ −this (`0` = off) |

Resets at broker midnight.

### 6. Daily Start Floor

Protects the day’s seed so a drawdown cannot chew through it — but **not from bar one**.

Example: start **600**, arm **5%**, buffer **3%**.

1. Until peak equity has reached `600 × 1.05 = 630`, the floor is **inactive**. You can open trades from 600 without being flattened.
2. Once equity has printed 630 (sticky for the day), the floor **arms**.
3. After that, if equity falls to `600 × 1.03 = 618` or below, everything is flattened and new trades are closed for the rest of the broker day.

Arm % must be greater than Buffer % (otherwise it would lock the instant it arms).

| Input | Meaning |
|---|---|
| Enable | Off by default |
| Starting balance | Seed for the day (e.g. 600). You set this; it does not auto-snapshot account balance |
| Buffer % | Once armed, flatten when equity ≤ start × (1 + this/100) |
| Arm % | Inactive until peak equity ≥ start × (1 + this/100). Default 5 |

Uses **account equity** (floating counts). Arming is sticky on **peak equity** for that broker day, so a drawdown after 630 is still protected. Flatten ignores “enforce on start” grandfathering and closes every position/pending that matches the magic filter, on every symbol. After the trip, new trades stay blocked until midnight even if equity recovers.

Dashboard: `wait arm at 630` → `armed kill 618` → `LOCKED`.

### Alerts

Terminal alert and/or push notification on a guard close.

## Live (v1.11)

This is the current public cut. Copy the folder to `MQL5/Experts/DomPanion/`, compile `DomPanion.mq5`, attach, **Algo Trading on**. Test on demo first. Live use is your own risk; see the disclaimer above.

1. Leave **Close trades in losing hours** off until the CLOCK looks right.
2. Optional: **Dry run** for one session before it can close anything.
3. Defaults already cap lots, enforce the money band, and block scale-in.
4. Daily goal lock: only if you want to freeze a winning day.
5. **Daily Start Floor**: set the seed to what you actually started with (600, 6000, …). It stays idle until you are 5% up, then protects the 3% cushion above the seed. If you attach with the seed still at 600 on a larger account, update it first.

## License

MIT. Copyright © 2026 Dominik Fischer.

The MIT licence’s “as is” / no-warranty terms apply. In addition: trading is risky; this tool is used at your own risk; the author accepts no responsibility or liability for its use, including after demo testing.
