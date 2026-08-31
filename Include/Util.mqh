#ifndef DOMPANION_UTIL_MQH
#define DOMPANION_UTIL_MQH

//+------------------------------------------------------------------+
//| Util.mqh                                                         |
//| Copyright 2026, Dominik Fischer                                  |
//+------------------------------------------------------------------+
#include "Types.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Logging. Level: 0 errors, 1 actions, 2 verbose.                  |
//+------------------------------------------------------------------+
void DpLog(const int minLevel, const int cfgLevel, const string msg)
  {
   if(cfgLevel >= minLevel)
      Print(DP_LOG_PREFIX, msg);
  }

string DpMoney(const double value, const string currency, const int digits = 2)
  {
   return (currency + " " + DoubleToString(value, digits));
  }

string DpLots(const double lots)
  {
   return DoubleToString(lots, 2);
  }

string DpHourLabel(const int hour)
  {
   if(hour < 0 || hour > 23)
      return "--";
   return (hour < 10 ? "0" : "") + IntegerToString(hour);
  }

int DpClampInt(const int v, const int lo, const int hi)
  {
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
  }

double DpClampDbl(const double v, const double lo, const double hi)
  {
   if(v < lo)
      return lo;
   if(v > hi)
      return hi;
   return v;
  }

//+------------------------------------------------------------------+
//| Timebase conversion for hour-of-day buckets.                     |
//| Deal/position times from the terminal are server timestamps.     |
//+------------------------------------------------------------------+
datetime DpShiftTime(const datetime serverTime, const SDpConfig &cfg)
  {
   if(serverTime <= 0)
      return 0;

   switch(cfg.timeBase)
     {
      case DP_TIME_LOCAL:
         return serverTime + (TimeLocal() - TimeCurrent());
      case DP_TIME_UTC:
         return serverTime + (TimeGMT() - TimeCurrent());
      case DP_TIME_OFFSET:
         return serverTime + (TimeGMT() - TimeCurrent()) + cfg.utcOffsetHours * 3600;
      default:
         return serverTime;
     }
  }

int DpHourOf(const datetime serverTime, const SDpConfig &cfg)
  {
   datetime t = DpShiftTime(serverTime, cfg);
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return dt.hour;
  }

datetime DpDayStartServer(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min  = 0;
   dt.sec  = 0;
   return StructToTime(dt);
  }

//+------------------------------------------------------------------+
//| Parse "8-10,14,16-18" / "0-6 22 23" into a 24-slot bool array.   |
//+------------------------------------------------------------------+
bool DpHourToken(const string tok, int &hour)
  {
   hour = -1;
   int n = StringLen(tok);
   if(n <= 0)
      return false;
   for(int i = 0; i < n; i++)
     {
      ushort c = (ushort)StringGetCharacter(tok, i);
      if(c < '0' || c > '9')
         return false;
     }
   hour = (int)StringToInteger(tok);
   return (hour >= 0 && hour <= 23);
  }

bool DpParseHourSpec(const string spec, bool &hours[], string &err)
  {
   if(ArraySize(hours) < DP_HOUR_COUNT)
     {
      if(ArrayResize(hours, DP_HOUR_COUNT) < DP_HOUR_COUNT)
        {
         err = "hour array resize failed";
         return false;
        }
     }
   ArrayInitialize(hours, false);
   err = "";

   string s = spec;
   StringTrimLeft(s);
   StringTrimRight(s);
   if(StringLen(s) == 0)
      return true;

   StringReplace(s, " - ", "-");
   StringReplace(s, "- ", "-");
   StringReplace(s, " -", "-");
   StringReplace(s, " ", ",");
   StringReplace(s, ";", ",");
   StringReplace(s, "|", ",");

   string parts[];
   int n = StringSplit(s, ',', parts);
   if(n <= 0)
     {
      err = "empty hour spec after split";
      return false;
     }

   for(int i = 0; i < n; i++)
     {
      string tok = parts[i];
      StringTrimLeft(tok);
      StringTrimRight(tok);
      if(StringLen(tok) == 0)
         continue;

      int dash = StringFind(tok, "-");
      if(dash < 0)
        {
         int h = 0;
         if(!DpHourToken(tok, h))
           {
            err = "invalid hour '" + tok + "'";
            return false;
           }
         hours[h] = true;
        }
      else
        {
         string a = StringSubstr(tok, 0, dash);
         string b = StringSubstr(tok, dash + 1);
         StringTrimLeft(a);
         StringTrimRight(a);
         StringTrimLeft(b);
         StringTrimRight(b);
         int h1 = 0;
         int h2 = 0;
         if(!DpHourToken(a, h1) || !DpHourToken(b, h2))
           {
            err = "invalid hour range '" + tok + "'";
            return false;
           }
         if(h1 <= h2)
           {
            for(int h = h1; h <= h2; h++)
               hours[h] = true;
           }
         else
           {
            for(int h = h1; h <= 23; h++)
               hours[h] = true;
            for(int h = 0; h <= h2; h++)
               hours[h] = true;
           }
        }
     }
   return true;
  }

string DpHourMaskList(const bool &hours[])
  {
   string out = "";
   int runStart = -1;
   for(int h = 0; h <= 24; h++)
     {
      bool on = (h < 24 && hours[h]);
      if(on && runStart < 0)
         runStart = h;
      if(!on && runStart >= 0)
        {
         int runEnd = h - 1;
         if(StringLen(out) > 0)
            out += ",";
         if(runStart == runEnd)
            out += DpHourLabel(runStart);
         else
            out += DpHourLabel(runStart) + "-" + DpHourLabel(runEnd);
         runStart = -1;
        }
     }
   return (StringLen(out) == 0 ? "none" : out);
  }

//+------------------------------------------------------------------+
string DpOwnerGvName(void)
  {
   return DP_GV_OWNER_PREFIX + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
  }

bool DpChartExists(const long chartId)
  {
   if(chartId <= 0)
      return false;
   long id = ChartFirst();
   while(id >= 0)
     {
      if(id == chartId)
         return true;
      id = ChartNext(id);
     }
   return false;
  }

bool DpClaimOwnership(const long chartId, const bool needAllSymbols, bool &conflict)
  {
   conflict = false;
   if(!needAllSymbols)
      return true;

   string gv = DpOwnerGvName();
   if(GlobalVariableCheck(gv))
     {
      long owner = (long)GlobalVariableGet(gv);
      if(owner == chartId)
        {
         GlobalVariableSet(gv, (double)chartId);
         GlobalVariableTemp(gv);
         return true;
        }
      if(owner > 0 && DpChartExists(owner))
        {
         conflict = true;
         return false;
        }
     }

   GlobalVariableSet(gv, (double)chartId);
   GlobalVariableTemp(gv);
   if((long)GlobalVariableGet(gv) != chartId)
     {
      conflict = true;
      return false;
     }
   return true;
  }

void DpReleaseOwnership(const long chartId, const bool needAllSymbols)
  {
   if(!needAllSymbols)
      return;
   string gv = DpOwnerGvName();
   if(!GlobalVariableCheck(gv))
      return;
   long owner = (long)GlobalVariableGet(gv);
   if(owner == chartId)
      GlobalVariableDel(gv);
  }

bool DpManageSymbol(const string symbol, const SDpConfig &cfg)
  {
   if(cfg.manageScope == DP_SCOPE_ACCOUNT)
      return true;
   return (symbol == cfg.symbol);
  }

bool DpManageMagic(const long magic, const SDpConfig &cfg)
  {
   if(cfg.magicFilter < 0)
      return true;
   return (magic == cfg.magicFilter);
  }

//+------------------------------------------------------------------+
bool DpIsHedging(void)
  {
   return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
            == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
  }

double DpLotRefValue(const ENUM_DP_LOT_REF ref)
  {
   if(ref == DP_LOT_EQUITY)
      return AccountInfoDouble(ACCOUNT_EQUITY);
   return AccountInfoDouble(ACCOUNT_BALANCE);
  }

double DpSymbolVolumeStep(const string symbol)
  {
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   return step;
  }

double DpNormalizeVolume(const string symbol, double volume)
  {
   double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = DpSymbolVolumeStep(symbol);
   if(vmin <= 0.0)
      vmin = step;
   if(vmax <= 0.0)
      vmax = 100.0;

   volume = MathFloor(volume / step + 1.0e-8) * step;
   if(volume + DP_VOLUME_EPS < vmin)
      return 0.0;
   if(volume > vmax)
      volume = vmax;
   int digits = 0;
   double s = step;
   while(digits < 8 && MathAbs(s - MathRound(s)) > 1.0e-10)
     {
      s *= 10.0;
      digits++;
     }
   return NormalizeDouble(volume, digits);
  }

// Max volume allowed for this symbol given the 0.01-unit budget.
double DpMaxLots(const string symbol, const double money, const double balancePer001, const double lotUnit)
  {
   if(balancePer001 <= 0.0 || lotUnit <= 0.0 || money <= 0.0)
      return 0.0;
   int units = (int)MathFloor(money / balancePer001 + 1.0e-12);
   if(units <= 0)
      return 0.0;
   return DpNormalizeVolume(symbol, (double)units * lotUnit);
  }

double DpUnits001(const double volume, const double lotUnit)
  {
   double u = (lotUnit > 0.0 ? lotUnit : 0.01);
   return volume / u;
  }

void DpMoneyBand(const double volume, const SDpConfig &cfg,
                 double &tpMoney, double &softMoney, double &hardMoney)
  {
   double units = DpUnits001(volume, cfg.lotUnit);
   tpMoney   = units * cfg.tpPer001;
   softMoney = units * cfg.slPer001;
   hardMoney = softMoney * cfg.breathMultiplier;
   if(hardMoney < softMoney)
      hardMoney = softMoney;
  }

// Equity level that trips the daily start-balance floor.
// 600 start + 3% buffer → 618. Close when equity is at or below this.
double DpDailyFloorTrigger(const double startBalance, const double bufferPct)
  {
   if(startBalance <= 0.0)
      return 0.0;
   double pct = bufferPct;
   if(pct < 0.0)
      pct = 0.0;
   return startBalance * (1.0 + pct / 100.0);
  }

string DpFloorDetail(const double floorLevel)
  {
   return "eq " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2)
          + " <= floor " + DoubleToString(floorLevel, 2);
  }

//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DpFillingFor(const string symbol)
  {
   uint mode = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   if((mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   return ORDER_FILLING_RETURN;
  }

void DpPrepareTrade(CTrade &trade, const string symbol, const int slippagePoints)
  {
   trade.SetExpertMagicNumber(0);
   trade.SetDeviationInPoints(slippagePoints < 0 ? 0 : slippagePoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFilling(DpFillingFor(symbol));
   trade.LogLevel(LOG_LEVEL_ERRORS);
  }

//+------------------------------------------------------------------+
//| Net P/L of an open position: floating + swap + commissions/fees  |
//| of every deal on the position, plus realized profit of partials. |
//+------------------------------------------------------------------+
double DpPositionNetProfit(const ulong ticket, double &commission, double &realized)
  {
   commission = 0.0;
   realized   = 0.0;
   if(!PositionSelectByTicket(ticket))
      return 0.0;

   double floating = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   ulong  pid      = (ulong)PositionGetInteger(POSITION_IDENTIFIER);

   if(!HistorySelectByPosition(pid))
      return floating;

   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
         continue;

      commission += HistoryDealGetDouble(deal, DEAL_COMMISSION)
                    + HistoryDealGetDouble(deal, DEAL_FEE);

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
         realized += HistoryDealGetDouble(deal, DEAL_PROFIT)
                     + HistoryDealGetDouble(deal, DEAL_SWAP);
     }
   return floating + commission + realized;
  }

// Realized P/L of closed deals whose close time is in [from, to].
double DpClosedPnl(const datetime from, const datetime to, const SDpConfig &cfg)
  {
   if(!HistorySelect(from, to))
      return 0.0;

   double pnl = 0.0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      datetime t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(t < from || t > to)
         continue;
      ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
         continue;
      if(!DpManageSymbol(HistoryDealGetString(deal, DEAL_SYMBOL), cfg))
         continue;
      if(!DpManageMagic(HistoryDealGetInteger(deal, DEAL_MAGIC), cfg))
         continue;
      pnl += HistoryDealGetDouble(deal, DEAL_PROFIT)
             + HistoryDealGetDouble(deal, DEAL_SWAP)
             + HistoryDealGetDouble(deal, DEAL_COMMISSION)
             + HistoryDealGetDouble(deal, DEAL_FEE);
     }
   return pnl;
  }

//+------------------------------------------------------------------+
//| Close-price that would produce targetMoney for this position.    |
//| Uses OrderCalcProfit (handles tick value, profit vs loss ticks). |
//+------------------------------------------------------------------+
bool DpPriceForMoney(const string symbol,
                     const ENUM_POSITION_TYPE type,
                     const double volume,
                     const double openPrice,
                     const double targetMoney,
                     double &outPrice)
  {
   outPrice = 0.0;
   if(volume <= DP_VOLUME_EPS || openPrice <= 0.0)
      return false;

   double tick = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(tick <= 0.0)
      return false;

   ENUM_ORDER_TYPE ot = (type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   bool buy = (type == POSITION_TYPE_BUY);
   bool wantProfit = (targetMoney >= 0.0);

   // Direction of price that increases profit.
   int dir = 0;
   if(buy)
      dir = (wantProfit ? 1 : -1);
   else
      dir = (wantProfit ? -1 : 1);

   double sample = 0.0;
   if(!OrderCalcProfit(ot, symbol, volume, openPrice, openPrice + dir * tick, sample))
      return false;
   if(MathAbs(sample) < 1.0e-12)
      return false;

   double ticksNeeded = targetMoney / sample;
   // sample is profit of `dir * tick`, which already has the sign of targetMoney's side.
   outPrice = openPrice + dir * tick * ticksNeeded;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   outPrice = NormalizeDouble(outPrice, digits);

   double minP = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(minP <= 0.0)
      minP = SymbolInfoDouble(symbol, SYMBOL_POINT);
   // Snap to tick
   if(minP > 0.0)
      outPrice = NormalizeDouble(MathRound(outPrice / minP) * minP, digits);
   return (outPrice > 0.0);
  }

int DpStopsLevelPoints(const string symbol)
  {
   int stops = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return MathMax(stops, freeze);
  }

bool DpStopDistanceOk(const string symbol, const double price, const bool isBuy, const bool isSl)
  {
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;
   int level = DpStopsLevelPoints(symbol);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double minDist = (double)level * point;
   if(isBuy)
     {
      if(isSl)
         return (bid - price >= minDist);
      return (price - ask >= minDist);
     }
   if(isSl)
      return (price - ask >= minDist);
   return (bid - price >= minDist);
  }

bool DpTradeAllowed(void)
  {
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      return false;
   return true;
  }

bool DpWantUi(const bool showDashboard)
  {
   if(!showDashboard)
      return false;
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return false;
   return true;
  }

bool DpRetryable(const uint retcode)
  {
   switch(retcode)
     {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_ERROR:
      case TRADE_RETCODE_TIMEOUT:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TOO_MANY_REQUESTS:
      case TRADE_RETCODE_LOCKED:
      case TRADE_RETCODE_FROZEN:
      case TRADE_RETCODE_MARKET_CLOSED:
      case TRADE_RETCODE_LIMIT_VOLUME:
      case TRADE_RETCODE_INVALID_FILL:
      case TRADE_RETCODE_INVALID_CLOSE_VOLUME:
      case TRADE_RETCODE_CLOSE_ORDER_EXIST:
      case TRADE_RETCODE_TRADE_DISABLED:
      case TRADE_RETCODE_CLIENT_DISABLES_AT:
      case TRADE_RETCODE_SERVER_DISABLES_AT:
         return true;
      default:
         return false;
     }
  }

string DpRetcodeText(const uint retcode)
  {
   return IntegerToString((int)retcode);
  }

#endif // DOMPANION_UTIL_MQH
