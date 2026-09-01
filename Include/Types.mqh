#ifndef DOMPANION_TYPES_MQH
#define DOMPANION_TYPES_MQH

//+------------------------------------------------------------------+
//| Types.mqh                                                        |
//| Copyright 2026, Dominik Fischer                                  |
//| Shared types. Inputs live in DomPanion.mq5 and are copied once.  |
//+------------------------------------------------------------------+

#define DP_LOG_PREFIX            "[DomPanion] "
#define DP_MAX_POSITIONS         128
#define DP_MAX_PENDINGS          128
#define DP_MAX_ACTIONS           8
#define DP_MAX_CLOSE_QUEUE       64
#define DP_HOUR_COUNT            24
#define DP_GV_OWNER_PREFIX       "DomPanion.owner."
#define DP_OBJ_CANVAS            "DomPanion.canvas"
#define DP_TIMER_MS              250
#define DP_VOLUME_EPS            0.0000001
#define DP_MONEY_EPS             0.005
#define DP_ATL_MAGIC             260601
#define DP_ATL_COMMENT           "DP-ATL"
#define DP_MAX_ATL_BASKETS       8

enum ENUM_DP_CORNER
  {
   DP_CORNER_LEFT_TOP    = 0,  // Top left
   DP_CORNER_RIGHT_TOP   = 1,  // Top right
   DP_CORNER_LEFT_BOTTOM = 2,  // Bottom left
   DP_CORNER_RIGHT_BOTTOM= 3   // Bottom right
  };

enum ENUM_DP_SCOPE
  {
   DP_SCOPE_CHART_SYMBOL = 0,  // This chart only
   DP_SCOPE_ACCOUNT      = 1   // Whole account
  };

enum ENUM_DP_TIMEBASE
  {
   DP_TIME_SERVER = 0,         // Broker time
   DP_TIME_LOCAL  = 1,         // Your PC time
   DP_TIME_UTC    = 2,         // UTC
   DP_TIME_OFFSET = 3          // UTC + offset hours
  };

enum ENUM_DP_LOT_REF
  {
   DP_LOT_BALANCE = 0,         // Balance
   DP_LOT_EQUITY  = 1          // Equity
  };

enum ENUM_DP_THEME
  {
   DP_THEME_DARK  = 0,         // Dark
   DP_THEME_LIGHT = 1          // Light
  };

enum ENUM_DP_ZONE
  {
   DP_ZONE_FLAT    = 0,
   DP_ZONE_BREATH  = 1,        // 0 down to -1R
   DP_ZONE_AMBER   = 2,        // -1R down to -hard
   DP_ZONE_KILL    = 3,        // at or beyond hard stop
   DP_ZONE_TARGET  = 4,        // at or beyond money TP
   DP_ZONE_LOCKED  = 5         // profit-lock floor is active
  };

enum ENUM_DP_REASON
  {
   DP_REASON_NONE          = 0,
   DP_REASON_LOSING_HOUR   = 1,
   DP_REASON_LOT_CAP       = 2,
   DP_REASON_EXTRA_POS     = 3,
   DP_REASON_SCALE_IN      = 4,
   DP_REASON_TAKE_PROFIT   = 5,
   DP_REASON_HARD_STOP     = 6,
   DP_REASON_AMBER_TIMEOUT = 7,
   DP_REASON_PROFIT_LOCK   = 8,
   DP_REASON_DAILY_LOCK    = 9,
   DP_REASON_DAILY_LOSS    = 10,
   DP_REASON_PENDING       = 11,
   DP_REASON_DAILY_FLOOR   = 12,
   DP_REASON_ATL_BE        = 13
  };

//+------------------------------------------------------------------+
//| Runtime copy of EA inputs. Engine never reads `input` directly.  |
//+------------------------------------------------------------------+
struct SDpConfig
  {
   string            symbol;
   long              chartId;
   bool              dryRun;
   int               logLevel;              // 0=errors, 1=actions, 2=verbose
   int               slippagePoints;

   ENUM_DP_SCOPE     manageScope;
   long              magicFilter;           // -1 = all magics
   bool              enforceOnStart;

   bool              showDashboard;
   ENUM_DP_CORNER    corner;
   ENUM_DP_THEME     theme;
   int               offsetX;
   int               offsetY;
   int               panelWidth;
   int               fontSize;
   double            panelScale;
   int               rightClearance;
   int               bottomClearance;

   bool              enableTimeAnalysis;
   int               historyDays;
   int               minTradesPerHour;
   double            losingWinRatePct;
   bool              loseOnNegativeNet;
   bool              blockLosingHours;
   ENUM_DP_TIMEBASE  timeBase;
   int               utcOffsetHours;
   string            manualLosingHours;
   string            forceSafeHours;

   bool              enableLotGuard;
   double            balancePer001;
   double            lotUnit;
   ENUM_DP_LOT_REF   lotReference;

   bool              enableMoneyGuard;
   double            tpPer001;
   double            slPer001;
   double            breathMultiplier;
   int               amberMaxSeconds;
   bool              setBrokerHardSl;
   bool              setBrokerTp;
   bool              enableProfitLock;
   double            lockTriggerPct;
   double            lockToR;

   bool              enableOneTrade;
   ENUM_DP_SCOPE     oneTradeScope;

   bool              enableDailyLock;
   double            dailyLockMoney;
   bool              dailyLockFlatten;
   double            dailyMaxLoss;

   bool              enableDailyFloor;
   double            dailyStartBalance;
   double            dailyFloorBufferPct;
   double            dailyFloorArmPct;

   bool              enableAtl;
   double            atlBePlusPct;
   int               atlMaxTrades;
   double            atlLot;

   bool              alertOnClose;
   bool              notifyOnClose;
  };

//+------------------------------------------------------------------+
struct SHourStat
  {
   int               trades;
   int               wins;
   int               losses;
   double            net;
   double            winRate;               // 0..100, 0 if no trades
   bool              sampleOk;
   bool              autoLosing;
   bool              manualLosing;
   bool              forceSafe;
   bool              losing;                // final classification
  };

struct STimeReport
  {
   bool              ready;
   datetime          builtAt;
   datetime          fromTime;
   int               days;
   int               closedTrades;
   int               wins;
   int               losses;
   double            winRate;
   double            net;
   int               currentHour;
   int               bestHour;              // -1 if none
   int               worstHour;
   SHourStat         hour[DP_HOUR_COUNT];
   bool              currentHourLosing;
   string            losingList;
   string            bestText;
   string            worstText;
  };

//+------------------------------------------------------------------+
struct SPosSnap
  {
   ulong             ticket;
   ulong             id;
   string            symbol;
   ENUM_POSITION_TYPE type;
   double            volume;
   double            priceOpen;
   double            sl;
   double            tp;
   double            profitRaw;
   double            swap;
   double            commission;
   double            realized;
   double            profitNet;
   datetime          timeOpen;
   long              magic;
   string            comment;
   int               digits;
   double            point;
  };

struct SPendingSnap
  {
   ulong             ticket;
   string            symbol;
   ENUM_ORDER_TYPE   type;
   double            volume;
   datetime          timeSetup;
   long              magic;
   double            priceOpen;
   string            comment;
  };

// Per-ticket memory that survives ticks (MAE, amber clock, volume, broker stops).
struct SPosState
  {
   ulong             ticket;
   ulong             id;
   string            symbol;
   double            lastVolume;
   double            peakProfit;
   double            troughProfit;
   datetime          amberSince;            // 0 = not in amber
   bool              profitLocked;
   bool              brokerStopsSet;
   datetime          firstSeen;
   bool              seen;
  };

struct SCloseReq
  {
   ulong             ticket;                // position ticket, or pending ticket
   bool              isPending;
   double            volume;                // 0 = full close
   ENUM_DP_REASON    reason;
   string            detail;
   datetime          lastTry;
   int               attempts;
   bool              inFlight;
  };

struct SAction
  {
   datetime          t;
   ENUM_DP_REASON    reason;
   string            text;
  };

struct SAtlBasket
  {
   bool              active;
   string            symbol;
   ENUM_POSITION_TYPE type;
   int               idx[DP_MAX_POSITIONS];
   int               n;
   double            firstPrice;
   double            step;
   double            addVolume;
   double            pnl;
   int               nextMult;
   double            nextPrice;
   ulong             pendingTicket;
  };

//+------------------------------------------------------------------+
struct SPosView
  {
   ulong             ticket;
   string            symbol;
   string            side;
   double            volume;
   double            profitNet;
   double            tpMoney;
   double            softSlMoney;
   double            hardSlMoney;
   double            peakProfit;
   double            troughProfit;
   ENUM_DP_ZONE      zone;
   string            zoneName;
   bool              profitLocked;
   int               amberLeftSec;          // -1 if n/a
   double            maxLotsNow;
  };

struct SGuardView
  {
   bool              timeOn;
   bool              timeBlocking;
   bool              timeNowLosing;
   string            timeNowLabel;
   bool              lotOn;
   double            maxLots;
   double            balancePer001;
   bool              moneyOn;
   double            tpPer001;
   double            hardMult;
   bool              oneTradeOn;
   int               openCount;
   bool              dailyOn;
   double            dailyPnl;
   double            dailyTarget;
   bool              dailyHit;
   bool              dailyLossHit;
   bool              dailyFloorOn;
   double            dailyStartBalance;
   double            dailyFloorLevel;
   double            dailyFloorArmLevel;
   bool              dailyFloorArmed;
   bool              dailyFloorHit;
   bool              atlOn;
   bool              atlActive;
   int               atlLegs;
   int               atlNextMult;
   double            atlBasketPnl;
   double            atlBeTarget;
   double            atlNextPrice;
   string            atlStatus;
   bool              dryRun;
   bool              armed;
   bool              ownerConflict;
   bool              tradeAllowed;
  };

struct SViewModel
  {
   bool              valid;
   string            symbol;
   string            currency;
   double            balance;
   double            equity;
   datetime          serverTime;
   SGuardView        guards;
   SPosView          positions[DP_MAX_POSITIONS];
   int               posCount;
   STimeReport       time;
   SAction           actions[DP_MAX_ACTIONS];
   int               actionCount;
   string            headline;
   string            lastError;
  };

//+------------------------------------------------------------------+
string DpReasonText(const ENUM_DP_REASON reason)
  {
   switch(reason)
     {
      case DP_REASON_LOSING_HOUR:   return "losing hour";
      case DP_REASON_LOT_CAP:       return "lot cap";
      case DP_REASON_EXTRA_POS:     return "extra position";
      case DP_REASON_SCALE_IN:      return "scale-in";
      case DP_REASON_TAKE_PROFIT:   return "money TP";
      case DP_REASON_HARD_STOP:     return "hard SL";
      case DP_REASON_AMBER_TIMEOUT: return "amber timeout";
      case DP_REASON_PROFIT_LOCK:   return "profit lock";
      case DP_REASON_DAILY_LOCK:    return "daily goal";
      case DP_REASON_DAILY_LOSS:    return "daily loss cap";
      case DP_REASON_PENDING:       return "pending blocked";
      case DP_REASON_DAILY_FLOOR:   return "daily start floor";
      case DP_REASON_ATL_BE:        return "add-to-losers BE";
      default:                      return "none";
     }
  }

string DpZoneName(const ENUM_DP_ZONE zone)
  {
   switch(zone)
     {
      case DP_ZONE_TARGET:  return "TARGET";
      case DP_ZONE_KILL:    return "KILL";
      case DP_ZONE_AMBER:   return "AMBER";
      case DP_ZONE_LOCKED:  return "LOCKED";
      case DP_ZONE_BREATH:  return "BREATH";
      default:              return "FLAT";
     }
  }

string DpCornerName(const ENUM_DP_CORNER corner)
  {
   switch(corner)
     {
      case DP_CORNER_RIGHT_TOP:    return "top-right";
      case DP_CORNER_LEFT_BOTTOM:  return "bottom-left";
      case DP_CORNER_RIGHT_BOTTOM: return "bottom-right";
      default:                     return "top-left";
     }
  }

#endif // DOMPANION_TYPES_MQH
