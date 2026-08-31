//+------------------------------------------------------------------+
//|                                                    DomPanion.mq5 |
//| Copyright 2026, Dominik Fischer                                  |
//| Companion EA for high-leverage, low-balance discretionary trading|
//|                                                                  |
//| Layout (required for compile):                                   |
//|   DomPanion.mq5                                                  |
//|   Include/*.mqh                                                  |
//| Copy this folder to MQL5/Experts/DomPanion/ and compile.         |
//| The compiled .ex5 is standalone; Include/ is compile-time only.  |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Dominik Fischer"
#property link        "https://github.com/domsendotnet/MT5-DomPanion"
#property version     "1.13"
#property description "DomPanion — session clock, lot cap, money TP/SL with breathing room, scale-in block, daily start floor."
#property description "Does not open trades. Attach to the chart you trade."

#include "Include/Types.mqh"
#include "Include/Engine.mqh"

//+------------------------------------------------------------------+
// Inputs: the // text is what you see in MT5. Everyday knobs first,
// rare ones at the bottom under Advanced.
//+------------------------------------------------------------------+
input group "— On / off —"
input bool              InpDryRun            = false; // Practice mode: show what would close, but do not close
input bool              InpShowDashboard     = true;  // Show the panel on the chart
input bool              InpAlertOnClose      = true;  // Pop-up when DomPanion closes a trade
input bool              InpNotifyOnClose     = false; // Phone push when DomPanion closes a trade

input group "— Panel —"
input ENUM_DP_CORNER    InpCorner            = DP_CORNER_RIGHT_TOP; // Where to put the panel
input ENUM_DP_THEME     InpTheme             = DP_THEME_DARK;       // Look

input group "— 1. Clock (your win / lose hours) —"
input bool              InpEnableTimeAnalysis= true;  // Show the hour clock from past trades
input bool              InpBlockLosingHours  = false; // Close trades I open in a losing hour (leave off until you trust the clock)
input string            InpManualLosingHours = "";    // Always-losing hours, e.g. 0-6,16,22-23
input string            InpForceSafeHours    = "";    // Never-block hours, e.g. 9-11

input group "— 2. Lot size —"
input bool              InpEnableLotGuard    = true;    // Stop me opening too much size
input double            InpBalancePer001     = 2000.0;  // Account money needed for 0.01 lot  (2300 with 2000 → max 0.01)

input group "— 3. Take profit and hard stop —"
input bool              InpEnableMoneyGuard  = true;  // Turn on money TP + breathing hard stop
input double            InpTpPer001          = 2.0;   // Take profit in money, per 0.01 lot     (0.10 lot → 20)
input double            InpSlPer001          = 2.0;   // 1R in money, per 0.01 lot               (warning zone)
input double            InpBreathMultiplier  = 3.0;   // Hard close at this × 1R                (3 → 0.01 lot dies at -6)
input bool              InpSetBrokerHardSl   = true;  // Also set broker SL at the hard close (if terminal dies)
input bool              InpSetBrokerTp       = true;  // Also set broker TP at the take profit

input group "— 4. One trade only —"
input bool              InpEnableOneTrade    = true;  // Close a 2nd/3rd trade (stops scaling into losers)

input group "— 5. Daily goal —"
input bool              InpEnableDailyLock   = false;  // Turn on
input double            InpDailyLockMoney    = 400.0;  // After today is up this much, block new trades  (0 = skip)
input bool              InpDailyLockFlatten  = false;  // Also close the open trade when the goal hits
input double            InpDailyMaxLoss      = 0.0;    // Flatten if today is down this much             (0 = skip)

input group "— 6. Protect starting balance —"
input bool              InpEnableDailyFloor  = false;  // Turn on
input double            InpDailyStartBalance = 600.0;  // Today's seed, e.g. 600 or 6000
input double            InpDailyFloorArmPct    = 5.0;  // Stay off until equity has reached seed + this %   (600→630)
input double            InpDailyFloorBufferPct = 3.0;  // Then flatten if equity falls to seed + this %     (600→618)

input group "— Advanced (leave alone unless you need it) —"
input ENUM_DP_SCOPE     InpManageScope       = DP_SCOPE_CHART_SYMBOL; // Watch this chart or the whole account
input ENUM_DP_SCOPE     InpOneTradeScope     = DP_SCOPE_CHART_SYMBOL; // One-trade rule: this chart or whole account
input long              InpMagicFilter       = -1;     // -1 = every trade, 0 = manual only
input bool              InpEnforceOnStart    = true;   // Apply rules to trades already open when I attach
input int               InpSlippagePoints    = 40;     // Close slippage (points)
input int               InpLogLevel          = 1;      // Journal: 0 = errors, 1 = closes, 2 = everything
input int               InpOffsetX           = 12;     // Panel gap from the side
input int               InpOffsetY           = 12;     // Panel gap from the top/bottom
input int               InpPanelWidth        = 380;    // Panel width
input int               InpFontSize          = 12;     // Panel text size
input double            InpPanelScale        = 1.0;    // Panel size multiplier
input int               InpRightClearance    = 58;     // Extra gap so the panel misses the price scale
input int               InpBottomClearance   = 22;     // Extra gap so the panel misses the status bar
input int               InpHistoryDays       = 90;     // Clock: days of history
input int               InpMinTradesPerHour  = 8;      // Clock: min trades before an hour counts as losing
input double            InpLosingWinRatePct  = 50.0;   // Clock: losing if win rate is below this %
input bool              InpLoseOnNegativeNet = true;   // Clock: also losing if that hour's net is negative
input ENUM_DP_TIMEBASE  InpTimeBase          = DP_TIME_SERVER; // Clock: whose clock
input int               InpUtcOffsetHours    = 0;      // Clock: extra hours if "UTC + offset"
input double            InpLotUnit           = 0.01;   // Lot step to count (keep 0.01)
input ENUM_DP_LOT_REF   InpLotReference      = DP_LOT_BALANCE; // Lot cap uses balance or equity
input int               InpAmberMaxSeconds   = 0;      // Close if stuck between 1R and hard stop this many seconds (0 = off)
input bool              InpEnableProfitLock  = false;  // After a run-up, raise the hard stop
input double            InpLockTriggerPct    = 80.0;   // Raise it when peak profit is this % of TP
input double            InpLockToR           = 0.0;    // New floor in R (0 = breakeven)

//+------------------------------------------------------------------+
CDomEngine g_engine;

void DpFillConfig(SDpConfig &cfg)
  {
   ZeroMemory(cfg);
   cfg.symbol             = _Symbol;
   cfg.chartId            = ChartID();
   cfg.dryRun             = InpDryRun;
   cfg.logLevel           = InpLogLevel;
   cfg.slippagePoints     = InpSlippagePoints;
   cfg.manageScope        = InpManageScope;
   cfg.magicFilter        = InpMagicFilter;
   cfg.enforceOnStart     = InpEnforceOnStart;

   cfg.showDashboard      = InpShowDashboard;
   cfg.corner             = InpCorner;
   cfg.theme              = InpTheme;
   cfg.offsetX            = InpOffsetX;
   cfg.offsetY            = InpOffsetY;
   cfg.panelWidth         = InpPanelWidth;
   cfg.fontSize           = InpFontSize;
   cfg.panelScale         = InpPanelScale;
   cfg.rightClearance     = InpRightClearance;
   cfg.bottomClearance    = InpBottomClearance;

   cfg.enableTimeAnalysis = InpEnableTimeAnalysis;
   cfg.historyDays        = InpHistoryDays;
   cfg.minTradesPerHour   = InpMinTradesPerHour;
   cfg.losingWinRatePct   = InpLosingWinRatePct;
   cfg.loseOnNegativeNet  = InpLoseOnNegativeNet;
   cfg.blockLosingHours   = InpBlockLosingHours;
   cfg.timeBase           = InpTimeBase;
   cfg.utcOffsetHours     = InpUtcOffsetHours;
   cfg.manualLosingHours  = InpManualLosingHours;
   cfg.forceSafeHours     = InpForceSafeHours;

   cfg.enableLotGuard     = InpEnableLotGuard;
   cfg.balancePer001      = InpBalancePer001;
   cfg.lotUnit            = InpLotUnit;
   cfg.lotReference       = InpLotReference;

   cfg.enableMoneyGuard   = InpEnableMoneyGuard;
   cfg.tpPer001           = InpTpPer001;
   cfg.slPer001           = InpSlPer001;
   cfg.breathMultiplier   = InpBreathMultiplier;
   cfg.amberMaxSeconds    = InpAmberMaxSeconds;
   cfg.setBrokerHardSl    = InpSetBrokerHardSl;
   cfg.setBrokerTp        = InpSetBrokerTp;
   cfg.enableProfitLock   = InpEnableProfitLock;
   cfg.lockTriggerPct     = InpLockTriggerPct;
   cfg.lockToR            = InpLockToR;

   cfg.enableOneTrade     = InpEnableOneTrade;
   cfg.oneTradeScope      = InpOneTradeScope;

   cfg.enableDailyLock    = InpEnableDailyLock;
   cfg.dailyLockMoney     = InpDailyLockMoney;
   cfg.dailyLockFlatten   = InpDailyLockFlatten;
   cfg.dailyMaxLoss       = InpDailyMaxLoss;

   cfg.enableDailyFloor   = InpEnableDailyFloor;
   cfg.dailyStartBalance  = InpDailyStartBalance;
   cfg.dailyFloorBufferPct= InpDailyFloorBufferPct;
   cfg.dailyFloorArmPct   = InpDailyFloorArmPct;

   cfg.alertOnClose       = InpAlertOnClose;
   cfg.notifyOnClose      = InpNotifyOnClose;
  }

int OnInit()
  {
   ChartSetInteger(0, CHART_FOREGROUND, false);
   SymbolSelect(_Symbol, true);

   SDpConfig cfg;
   DpFillConfig(cfg);
   if(!g_engine.Init(cfg))
      return INIT_FAILED;
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   g_engine.Deinit(reason);
  }

void OnTick()
  {
   g_engine.OnTick();
  }

void OnTimer()
  {
   g_engine.OnTimer();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   g_engine.OnTradeTransaction(trans);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   g_engine.OnChartEvent(id);
  }

//+------------------------------------------------------------------+
