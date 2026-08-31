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

In MT5: right-click the chart → Expert Advisors → Properties → **Inputs**. Each line’s label is the full meaning. Everyday switches are at the top; **Advanced** is at the bottom — leave it unless you need it.

**On / off** — Practice mode (shows what would close, does not close). Panel. Pop-up / phone alert.

**Panel** — Corner and dark/light.

**1. Clock** — Builds the hour heatmap from past trades. “Close trades I open in a losing hour” stays **off** until you trust it. Optional: type hours like `0-6,16` or never-block `9-11`.

**2. Lot size** — e.g. 2000 needed per 0.01. With 2300 on the account, 0.02 is closed.

**3. Take profit and hard stop** — Money per 0.01 lot. Default: take 2, 1R is 2, hard close at 3× (so 0.01 dies at −6, 0.10 at −60). Optional broker SL/TP if the terminal dies.

**4. One trade only** — A 2nd/3rd position is closed. Stops scaling into losers.

**5. Daily goal** — Optional. After today is up X, block new trades. Optional flatten. Optional max loss.

**6. Protect starting balance** — Optional. Set today’s seed (600, 6000, …). Stays **off** until equity has reached seed + 5% (630 on 600). After that, flatten if equity falls to seed + 3% (618). Arm % must be greater than the kill %. Dashboard: `wait arm at 630` → `armed kill 618` → `LOCKED`.

**Advanced** — Whole-account vs this chart, magic filter, slippage, panel size, clock sample size, profit lock, amber timeout. Defaults are fine.

If two copies use “whole account”, the second stands by.

## Live (v1.13)

This is the current public cut. Copy the folder to `MQL5/Experts/DomPanion/`, compile `DomPanion.mq5`, attach, **Algo Trading on**. Test on demo first. Live use is your own risk; see the disclaimer above.

1. Leave **Close trades in losing hours** off until the CLOCK looks right.
2. Optional: **Dry run** for one session before it can close anything.
3. Defaults already cap lots, enforce the money band, and block scale-in.
4. Daily goal lock: only if you want to freeze a winning day.
5. **Daily Start Floor**: set the seed to what you actually started with (600, 6000, …). It stays idle until you are 5% up, then protects the 3% cushion above the seed. If you attach with the seed still at 600 on a larger account, update it first.

## License

MIT. Copyright © 2026 Dominik Fischer.

The MIT licence’s “as is” / no-warranty terms apply. In addition: trading is risky; this tool is used at your own risk; the author accepts no responsibility or liability for its use, including after demo testing.
