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
#property version     "1.21"
#property description "DomPanion — clock, lot cap, money TP/SL, one-trade, start floor, add-to-losers."
#property description "Does not open trades. Attach to the chart you trade."

#include "Include/Types.mqh"
#include "Include/Engine.mqh"

//+------------------------------------------------------------------+
// What you see in MT5 Inputs is the // text. Keep it tiny.
//+------------------------------------------------------------------+
input group "1  Practice"
input bool              InpDryRun              = false; // Don't close — just show

input group "2  Screen"
input bool              InpShowDashboard       = true;                  // Show panel
input ENUM_DP_CORNER    InpCorner              = DP_CORNER_RIGHT_TOP;   // Corner
input ENUM_DP_THEME     InpTheme               = DP_THEME_DARK;         // Dark or light
input bool              InpAlertOnClose        = true;                  // Pop-up
input bool              InpNotifyOnClose       = false;                 // Phone

input group "3  Lots"
input bool              InpEnableLotGuard      = true;    // Limit lots
input double            InpBalancePer001       = 2000.0;  // Money for 0.01 lot

input group "4  Profit"
input bool              InpEnableMoneyGuard    = true;  // Use money TP / SL
input double            InpTpPer001            = 2.0;   // Win per 0.01
input double            InpSlPer001            = 2.0;   // Room per 0.01
input double            InpBreathMultiplier    = 3.0;   // Close after this many rooms
input bool              InpSetBrokerHardSl     = true;  // Broker SL
input bool              InpSetBrokerTp         = true;  // Broker TP

input group "5  Trades"
input bool              InpEnableOneTrade      = true;  // Only 1 trade

input group "6  Hours"
input bool              InpEnableTimeAnalysis  = true;  // Show hour clock
input bool              InpBlockLosingHours    = false; // Kill bad-hour trades
input string            InpManualLosingHours   = "";    // Bad hours
input string            InpForceSafeHours      = "";    // Good hours

input group "7  Today"
input bool              InpEnableDailyLock     = false;  // Stop after a win
input double            InpDailyLockMoney      = 400.0;  // Win goal
input bool              InpDailyLockFlatten    = false;  // Close trade at goal
input double            InpDailyMaxLoss        = 0.0;    // Max loss (0=off)

input group "8  Start money"
input bool              InpEnableDailyFloor    = false;  // Protect start money
input double            InpDailyStartBalance   = 600.0;  // I started with
input double            InpDailyFloorArmPct    = 5.0;    // Wait until up %
input double            InpDailyFloorBufferPct = 3.0;    // Close if only up %

input group "9  Add to losers"
input bool              InpEnableAtl           = false;  // Add to losers
input double            InpAtlBePlusPct        = 0.5;    // Extra profit %
input int               InpAtlMaxTrades        = 6;      // Max trades
input double            InpAtlLot              = 0.0;    // Lot per add (0=2nd)

input group "10 Extra"
input ENUM_DP_SCOPE     InpManageScope         = DP_SCOPE_CHART_SYMBOL; // Watch
input ENUM_DP_SCOPE     InpOneTradeScope       = DP_SCOPE_CHART_SYMBOL; // One-trade on
input long              InpMagicFilter         = -1;     // Which trades (-1=all  0=manual)
input bool              InpEnforceOnStart      = true;   // Fix trades already open
input int               InpSlippagePoints      = 40;     // Slippage
input int               InpLogLevel            = 1;      // Log 0/1/2
input int               InpOffsetX             = 12;     // Panel side gap
input int               InpOffsetY             = 12;     // Panel top gap
input int               InpPanelWidth          = 380;    // Panel width
input int               InpFontSize            = 12;     // Text size
input double            InpPanelScale          = 1.0;    // Panel scale
input int               InpRightClearance      = 58;     // Right gap
input int               InpBottomClearance     = 22;     // Bottom gap
input int               InpHistoryDays         = 90;     // Clock days
input int               InpMinTradesPerHour    = 8;      // Min trades / hour
input double            InpLosingWinRatePct    = 50.0;   // Bad hour if win % below
input bool              InpLoseOnNegativeNet   = true;   // Bad hour if net < 0
input ENUM_DP_TIMEBASE  InpTimeBase            = DP_TIME_SERVER; // Clock time
input int               InpUtcOffsetHours      = 0;      // UTC extra hours
input double            InpLotUnit             = 0.01;   // Lot step
input ENUM_DP_LOT_REF   InpLotReference        = DP_LOT_BALANCE; // Lots from
input int               InpAmberMaxSeconds     = 0;      // Stuck seconds (0=off)
input bool              InpEnableProfitLock    = false;  // Lock profit
input double            InpLockTriggerPct      = 80.0;   // Lock at % of TP
input double            InpLockToR             = 0.0;    // Lock to (0=even)

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

   cfg.enableAtl          = InpEnableAtl;
   cfg.atlBePlusPct       = InpAtlBePlusPct;
   cfg.atlMaxTrades       = InpAtlMaxTrades;
   cfg.atlLot             = InpAtlLot;

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
