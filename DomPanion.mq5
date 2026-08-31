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
#property version     "1.03"
#property description "DomPanion — session clock, lot cap, money TP/SL with breathing room, scale-in block, daily start floor."
#property description "Does not open trades. Attach to the chart you trade."

#include "Include/Types.mqh"
#include "Include/Engine.mqh"

//+------------------------------------------------------------------+
input group "0. General"
input bool              InpDryRun            = false;           // Dry run (log + dashboard, do not close)
input ENUM_DP_SCOPE     InpManageScope       = DP_SCOPE_CHART_SYMBOL; // Manage scope
input long              InpMagicFilter       = -1;              // Magic filter (-1 = all, 0 = manual)
input bool              InpEnforceOnStart    = true;            // Enforce rules on positions already open
input int               InpSlippagePoints    = 40;              // Close slippage (points)
input int               InpLogLevel          = 1;               // Log: 0 errors, 1 actions, 2 verbose

input group "Dashboard"
input bool              InpShowDashboard     = true;            // Show dashboard
input ENUM_DP_CORNER    InpCorner            = DP_CORNER_RIGHT_TOP; // Corner
input ENUM_DP_THEME     InpTheme             = DP_THEME_DARK;   // Theme
input int               InpOffsetX           = 12;              // Offset X (px)
input int               InpOffsetY           = 12;              // Offset Y (px)
input int               InpPanelWidth        = 380;             // Panel width (px, DPI-scaled)
input int               InpFontSize          = 12;              // Base font size (px)
input double            InpPanelScale        = 1.0;             // Extra scale (0.8–1.4 typical)
input int               InpRightClearance    = 58;              // Extra gap from price scale (right corners)
input int               InpBottomClearance   = 22;              // Extra gap from status bar (bottom corners)

input group "1. Time Intelligence"
input bool              InpEnableTimeAnalysis= true;            // Analyse closed trades by entry hour
input int               InpHistoryDays       = 90;              // History window (days)
input int               InpMinTradesPerHour  = 8;               // Min trades before an hour can auto-classify
input double            InpLosingWinRatePct  = 50.0;            // Auto-losing if win rate is below this %
input bool              InpLoseOnNegativeNet = true;            // Also auto-losing if that hour's net is < 0
input bool              InpBlockLosingHours  = false;           // Close trades opened in losing hours
input ENUM_DP_TIMEBASE  InpTimeBase          = DP_TIME_SERVER;  // Hour clock
input int               InpUtcOffsetHours    = 0;               // Used only if clock = UTC + offset
input string            InpManualLosingHours = "";              // Force-losing, e.g. 0-6,16,22-23
input string            InpForceSafeHours    = "";              // Never-block, e.g. 9-11

input group "2. Lot Size Guard"
input bool              InpEnableLotGuard    = true;            // Enable lot cap
input double            InpBalancePer001     = 2000.0;          // Balance needed per 0.01 lot
input double            InpLotUnit           = 0.01;            // Lot unit (keep 0.01 unless the symbol steps differ)
input ENUM_DP_LOT_REF   InpLotReference      = DP_LOT_BALANCE;  // Cap against balance or equity

input group "3. Money TP / SL / Breath"
input bool              InpEnableMoneyGuard  = true;            // Enable money TP + breathing SL
input double            InpTpPer001          = 2.0;             // Take profit (account currency) per 0.01 lot
input double            InpSlPer001          = 2.0;             // 1R stop (account currency) per 0.01 lot
input double            InpBreathMultiplier  = 3.0;             // Hard kill at this × 1R (3 = 2–3× MAE room)
input int               InpAmberMaxSeconds   = 0;               // Close if stuck in 1R–NR band this many seconds (0 = off)
input bool              InpSetBrokerHardSl   = true;            // Place broker SL at the hard kill (offline safety)
input bool              InpSetBrokerTp       = true;            // Place broker TP at the money TP
input bool              InpEnableProfitLock  = false;           // After peak hits Lock trigger, raise kill floor
input double            InpLockTriggerPct    = 80.0;            // Lock when peak profit ≥ this % of TP
input double            InpLockToR           = 0.0;             // Lock floor in R (0 = breakeven)

input group "4. Scale-in Block"
input bool              InpEnableOneTrade    = true;            // Kill 2nd/3rd positions (and netting adds)
input ENUM_DP_SCOPE     InpOneTradeScope     = DP_SCOPE_CHART_SYMBOL; // One-trade scope

input group "5. Daily Goal Lock (optional)"
input bool              InpEnableDailyLock   = false;           // Enable daily goal / loss cap
input double            InpDailyLockMoney    = 400.0;           // Block new trades once today ≥ this (0 = off)
input bool              InpDailyLockFlatten  = false;           // Also close the open trade when the goal hits
input double            InpDailyMaxLoss      = 0.0;             // Flatten + block if today ≤ -this (0 = off)

input group "6. Daily Start Floor"
input bool              InpEnableDailyFloor  = false;           // Enable daily start-balance floor
input double            InpDailyStartBalance = 600.0;           // Starting balance (resets each broker day)
input double            InpDailyFloorBufferPct = 3.0;           // Flatten when equity is within this % of the start
input double            InpDailyFloorArmPct    = 5.0;           // Inactive until equity has reached start + this % (e.g. 630 on 600)

input group "Alerts"
input bool              InpAlertOnClose      = true;            // Terminal Alert on a guard close
input bool              InpNotifyOnClose     = false;           // Push notification on a guard close

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
