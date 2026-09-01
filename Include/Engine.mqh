#ifndef DOMPANION_ENGINE_MQH
#define DOMPANION_ENGINE_MQH

//+------------------------------------------------------------------+
//| Engine.mqh                                                       |
//| Copyright 2026, Dominik Fischer                                  |
//+------------------------------------------------------------------+
#include "Types.mqh"
#include "Util.mqh"
#include "Analyzer.mqh"
#include "Dashboard.mqh"
#include <Trade/Trade.mqh>

#define DP_MAX_CLOSE_ATTEMPTS  12
#define DP_RENDER_MS           200

class CDomEngine
  {
private:
   SDpConfig         m_cfg;
   CTrade            m_trade;
   CTimeAnalyzer     m_time;
   CDashboard        m_dash;

   SPosSnap          m_pos[DP_MAX_POSITIONS];
   int               m_posN;
   SPendingSnap      m_pend[DP_MAX_PENDINGS];
   int               m_pendN;
   SPosState         m_st[DP_MAX_POSITIONS];
   int               m_stN;
   SCloseReq         m_q[DP_MAX_CLOSE_QUEUE];
   int               m_qN;
   SAction           m_actions[DP_MAX_ACTIONS];
   int               m_actionN;

   bool              m_inPulse;
   bool              m_needReplay;
   bool              m_armed;
   bool              m_ownerConflict;
   bool              m_inited;
   datetime          m_initTime;
   datetime          m_dayStamp;
   datetime          m_dailyLockSince;
   bool              m_dailyHitSticky;
   bool              m_dailyLossSticky;
   bool              m_dailyFloorSticky;
   bool              m_dailyFloorArmed;
   double            m_dailyFloorLevel;
   double            m_dailyFloorArmLevel;
   double            m_dailyPeakEquity;
   double            m_dailyClosed;
   double            m_dailyPnl;
   string            m_lastError;
   uint              m_lastRenderMs;
   STimeReport       m_report;
   SViewModel        m_vm;
   ulong             m_noted[DP_MAX_CLOSE_QUEUE];
   int               m_notedN;
   ulong             m_dead[DP_MAX_CLOSE_QUEUE];
   int               m_deadN;
   SAtlBasket        m_atl[DP_MAX_ATL_BASKETS];
   int               m_atlN;
   uint              m_atlLastPlaceMs;

   void              ResetRuntime(void);
   bool              NoteOnce(const ulong ticket);
   bool              IsDead(const ulong ticket) const;
   void              MarkDead(const ulong ticket);
   void              PruneGoneTickets(ulong &arr[], int &n);
   void              PruneDead(void);
   int               FindState(const ulong ticket) const;
   int               EnsureState(const SPosSnap &snap);
   void              PruneState(void);
   int               FindQueue(const ulong ticket, const bool pending) const;
   int               ReasonRank(const ENUM_DP_REASON r) const;
   void              Enqueue(const ulong ticket, const bool pending, const double volume,
                             const ENUM_DP_REASON reason, const string detail);
   void              DequeueAt(const int idx);
   void              PushAction(const ENUM_DP_REASON reason, const string text);
   void              SnapshotPositions(void);
   void              SnapshotPendings(void);
   int               KeeperIndex(void) const;
   bool              InOneTradeScope(const string symbol) const;
   bool              Grandfathered(const datetime timeOpen) const;
   void              RefreshDaily(void);
   void              EnqueueAccountFlatten(const ENUM_DP_REASON reason, const string detail);
   void              EvaluatePendings(void);
   void              EvaluatePositions(void);
   void              ApplyMoneyAndStops(const int idx, const bool willClose);
   ENUM_DP_ZONE      ZoneOf(const double pnl, const double soft, const double hard,
                            const double tp, const bool locked, const double lockFloor) const;
   void              ProcessQueue(void);
   bool              ExecuteClose(SCloseReq &req);
   void              AlertClose(const string text);
   void              BuildView(void);
   void              Render(const bool force);
   void              Work(void);
   void              AtlSortBasket(SAtlBasket &b);
   bool              AtlFromDeals(const SPosSnap &p, double &first, double &step,
                                  double &addVol, int &legs);
   bool              AtlLevelFilled(const SAtlBasket &b, const double level);
   void              RebuildAtlBaskets(void);
   bool              InAtlBasket(const string symbol, const ENUM_POSITION_TYPE type) const;
   bool              AtlSameDirOpen(const string symbol, const ENUM_POSITION_TYPE type) const;
   bool              AtlHasMate(const int posIndex) const;
   double            AtlBeTarget(void) const;
   void              AtlStripStops(const SAtlBasket &b);
   void              AtlEnqueueBasket(const SAtlBasket &b, const string detail);
   bool              AtlBlockedAdds(void) const;
   bool              PolicyBlockNew(void) const;
   void              AtlCancelPendings(const string symbol, const ENUM_POSITION_TYPE type);
   void              AtlCancelAllPendings(void);
   void              AtlPlaceNext(SAtlBasket &b);
   void              RunAddToLosers(void);
   void              AtlFillView(SGuardView &g) const;

public:
                     CDomEngine(void);
   bool              Init(const SDpConfig &cfg);
   void              Deinit(const int reason);
   void              Pulse(void);
   void              OnTick(void);
   void              OnTimer(void);
   void              OnTradeTransaction(const MqlTradeTransaction &trans);
   void              OnChartEvent(const int id);
  };

CDomEngine::CDomEngine(void)
  {
   ResetRuntime();
   m_inited = false;
  }

void CDomEngine::ResetRuntime(void)
  {
   m_posN = m_pendN = m_stN = m_qN = m_actionN = m_notedN = m_deadN = 0;
   m_atlN = 0;
   m_atlLastPlaceMs = 0;
   m_inPulse = m_needReplay = m_armed = m_ownerConflict = false;
   m_initTime = 0;
   m_dayStamp = 0;
   m_dailyLockSince = 0;
   m_dailyHitSticky = m_dailyLossSticky = m_dailyFloorSticky = false;
   m_dailyFloorArmed = false;
   m_dailyFloorLevel = 0.0;
   m_dailyFloorArmLevel = 0.0;
   m_dailyPeakEquity = 0.0;
   m_dailyClosed = m_dailyPnl = 0.0;
   m_lastError = "";
   m_lastRenderMs = 0;
   ZeroMemory(m_report);
   ZeroMemory(m_vm);
  }

bool CDomEngine::NoteOnce(const ulong ticket)
  {
   for(int i = 0; i < m_notedN; i++)
     {
      if(m_noted[i] == ticket)
         return false;
     }
   if(m_notedN < DP_MAX_CLOSE_QUEUE)
      m_noted[m_notedN++] = ticket;
   return true;
  }

bool CDomEngine::IsDead(const ulong ticket) const
  {
   for(int i = 0; i < m_deadN; i++)
     {
      if(m_dead[i] == ticket)
         return true;
     }
   return false;
  }

void CDomEngine::MarkDead(const ulong ticket)
  {
   if(IsDead(ticket))
      return;
   if(m_deadN < DP_MAX_CLOSE_QUEUE)
      m_dead[m_deadN++] = ticket;
  }

void CDomEngine::PruneGoneTickets(ulong &arr[], int &n)
  {
   int w = 0;
   for(int i = 0; i < n; i++)
     {
      bool live = false;
      for(int p = 0; p < m_posN && !live; p++)
         if(m_pos[p].ticket == arr[i])
            live = true;
      for(int p = 0; p < m_pendN && !live; p++)
         if(m_pend[p].ticket == arr[i])
            live = true;
      if(!live)
         continue;
      arr[w++] = arr[i];
     }
   n = w;
  }

void CDomEngine::PruneDead(void)
  {
   PruneGoneTickets(m_dead, m_deadN);
   PruneGoneTickets(m_noted, m_notedN);
  }

int CDomEngine::ReasonRank(const ENUM_DP_REASON r) const
  {
   switch(r)
     {
      case DP_REASON_DAILY_FLOOR:   return 110;
      case DP_REASON_DAILY_LOSS:    return 100;
      case DP_REASON_ATL_BE:        return 85;
      case DP_REASON_HARD_STOP:     return 90;
      case DP_REASON_AMBER_TIMEOUT: return 80;
      case DP_REASON_PROFIT_LOCK:   return 75;
      case DP_REASON_DAILY_LOCK:    return 70;
      case DP_REASON_LOSING_HOUR:   return 60;
      case DP_REASON_LOT_CAP:       return 50;
      case DP_REASON_EXTRA_POS:     return 40;
      case DP_REASON_SCALE_IN:      return 35;
      case DP_REASON_TAKE_PROFIT:   return 20;
      case DP_REASON_PENDING:       return 10;
      default:                      return 0;
     }
  }

int CDomEngine::FindState(const ulong ticket) const
  {
   for(int i = 0; i < m_stN; i++)
     {
      if(m_st[i].ticket == ticket)
         return i;
     }
   return -1;
  }

int CDomEngine::EnsureState(const SPosSnap &snap)
  {
   int i = FindState(snap.ticket);
   if(i >= 0)
     {
      m_st[i].id     = snap.id;
      m_st[i].symbol = snap.symbol;
      m_st[i].seen   = true;
      if(snap.profitNet > m_st[i].peakProfit)
         m_st[i].peakProfit = snap.profitNet;
      if(snap.profitNet < m_st[i].troughProfit)
         m_st[i].troughProfit = snap.profitNet;
      if(m_st[i].lastVolume <= DP_VOLUME_EPS)
         m_st[i].lastVolume = snap.volume;
      else if(snap.volume < m_st[i].lastVolume - DP_VOLUME_EPS)
         m_st[i].lastVolume = snap.volume;
      return i;
     }
   if(m_stN >= DP_MAX_POSITIONS)
     {
      DpLog(0, m_cfg.logLevel, "position state table full");
      return -1;
     }
   i = m_stN++;
   m_st[i].ticket        = snap.ticket;
   m_st[i].id            = snap.id;
   m_st[i].symbol        = snap.symbol;
   m_st[i].lastVolume    = snap.volume;
   m_st[i].peakProfit    = snap.profitNet;
   m_st[i].troughProfit  = snap.profitNet;
   m_st[i].amberSince    = 0;
   m_st[i].profitLocked  = false;
   m_st[i].brokerStopsSet= false;
   m_st[i].firstSeen     = TimeCurrent();
   m_st[i].seen          = true;
   return i;
  }

void CDomEngine::PruneState(void)
  {
   int w = 0;
   for(int i = 0; i < m_stN; i++)
     {
      if(!m_st[i].seen)
         continue;
      if(w != i)
         m_st[w] = m_st[i];
      m_st[w].seen = false;
      w++;
     }
   m_stN = w;
  }

int CDomEngine::FindQueue(const ulong ticket, const bool pending) const
  {
   for(int i = 0; i < m_qN; i++)
     {
      if(m_q[i].ticket == ticket && m_q[i].isPending == pending)
         return i;
     }
   return -1;
  }

void CDomEngine::Enqueue(const ulong ticket, const bool pending, const double volume,
                         const ENUM_DP_REASON reason, const string detail)
  {
   if(IsDead(ticket))
      return;
   int i = FindQueue(ticket, pending);
   if(i >= 0)
     {
      if(ReasonRank(reason) >= ReasonRank(m_q[i].reason))
        {
         m_q[i].reason  = reason;
         m_q[i].detail  = detail;
         m_q[i].volume  = volume;
        }
      return;
     }
   if(m_qN >= DP_MAX_CLOSE_QUEUE)
     {
      DpLog(0, m_cfg.logLevel, "close queue full, dropping " + IntegerToString((long)ticket));
      return;
     }
   i = m_qN++;
   m_q[i].ticket    = ticket;
   m_q[i].isPending = pending;
   m_q[i].volume    = volume;
   m_q[i].reason    = reason;
   m_q[i].detail    = detail;
   m_q[i].lastTry   = 0;
   m_q[i].attempts  = 0;
   m_q[i].inFlight  = false;
  }

void CDomEngine::DequeueAt(const int idx)
  {
   if(idx < 0 || idx >= m_qN)
      return;
   for(int i = idx; i < m_qN - 1; i++)
      m_q[i] = m_q[i + 1];
   m_qN--;
  }

void CDomEngine::PushAction(const ENUM_DP_REASON reason, const string text)
  {
   for(int i = DP_MAX_ACTIONS - 1; i > 0; i--)
      m_actions[i] = m_actions[i - 1];
   m_actions[0].t      = TimeCurrent();
   m_actions[0].reason = reason;
   m_actions[0].text   = text;
   if(m_actionN < DP_MAX_ACTIONS)
      m_actionN++;
  }

bool CDomEngine::InOneTradeScope(const string symbol) const
  {
   if(m_cfg.oneTradeScope == DP_SCOPE_ACCOUNT)
      return true;
   return (symbol == m_cfg.symbol);
  }

bool CDomEngine::Grandfathered(const datetime timeOpen) const
  {
   if(m_cfg.enforceOnStart)
      return false;
   return (timeOpen > 0 && timeOpen <= m_initTime);
  }

int CDomEngine::KeeperIndex(void) const
  {
   int keeper = -1;
   datetime bestT = 0;
   ulong bestTicket = 0;
   bool have = false;
   for(int i = 0; i < m_posN; i++)
     {
      if(!InOneTradeScope(m_pos[i].symbol))
         continue;
      if(!have || m_pos[i].timeOpen < bestT ||
         (m_pos[i].timeOpen == bestT && m_pos[i].ticket < bestTicket))
        {
         have = true;
         keeper = i;
         bestT = m_pos[i].timeOpen;
         bestTicket = m_pos[i].ticket;
        }
     }
   return keeper;
  }

void CDomEngine::SnapshotPositions(void)
  {
   m_posN = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      if(!DpManageSymbol(symbol, m_cfg))
         continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!DpManageMagic(magic, m_cfg))
         continue;
      if(m_posN >= DP_MAX_POSITIONS)
         break;

      SPosSnap s;
      s.ticket     = ticket;
      s.id         = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      s.symbol     = symbol;
      s.type       = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      s.volume     = PositionGetDouble(POSITION_VOLUME);
      s.priceOpen  = PositionGetDouble(POSITION_PRICE_OPEN);
      s.sl         = PositionGetDouble(POSITION_SL);
      s.tp         = PositionGetDouble(POSITION_TP);
      s.profitRaw  = PositionGetDouble(POSITION_PROFIT);
      s.swap       = PositionGetDouble(POSITION_SWAP);
      s.timeOpen   = (datetime)PositionGetInteger(POSITION_TIME);
      s.magic      = magic;
      s.comment    = PositionGetString(POSITION_COMMENT);
      s.digits     = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      s.point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
      s.commission = 0.0;
      s.realized   = 0.0;
      s.profitNet  = DpPositionNetProfit(ticket, s.commission, s.realized);
      m_pos[m_posN++] = s;
     }
  }

void CDomEngine::SnapshotPendings(void)
  {
   m_pendN = 0;
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
         continue;

      string symbol = OrderGetString(ORDER_SYMBOL);
      if(!DpManageSymbol(symbol, m_cfg))
         continue;
      long magic = OrderGetInteger(ORDER_MAGIC);
      if(!DpManageMagic(magic, m_cfg))
         continue;
      if(m_pendN >= DP_MAX_PENDINGS)
         break;

      SPendingSnap p;
      p.ticket    = ticket;
      p.symbol    = symbol;
      p.type      = type;
      p.volume    = OrderGetDouble(ORDER_VOLUME_CURRENT);
      p.timeSetup = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      p.magic     = magic;
      p.priceOpen = OrderGetDouble(ORDER_PRICE_OPEN);
      p.comment   = OrderGetString(ORDER_COMMENT);
      m_pend[m_pendN++] = p;
     }
  }

void CDomEngine::RefreshDaily(void)
  {
   datetime day = DpDayStartServer();
   if(day != m_dayStamp)
     {
      m_dayStamp         = day;
      m_dailyHitSticky   = false;
      m_dailyLossSticky  = false;
      m_dailyFloorSticky = false;
      m_dailyFloorArmed  = false;
      m_dailyPeakEquity  = 0.0;
      m_dailyLockSince   = 0;
     }

   m_dailyClosed = DpClosedPnl(day, TimeCurrent(), m_cfg);

   // Today's deals already include realized partials and commissions.
   // Add only open floating (price + swap) so those are not counted twice.
   double floating = 0.0;
   for(int i = 0; i < m_posN; i++)
      floating += m_pos[i].profitRaw + m_pos[i].swap;
   m_dailyPnl = m_dailyClosed + floating;

   if(m_cfg.enableDailyLock && m_cfg.dailyLockMoney > 0.0 &&
      m_dailyPnl + DP_MONEY_EPS >= m_cfg.dailyLockMoney)
     {
      if(!m_dailyHitSticky)
         m_dailyLockSince = TimeCurrent();
      m_dailyHitSticky = true;
     }

   if(m_cfg.enableDailyLock && m_cfg.dailyMaxLoss > 0.0 &&
      m_dailyPnl <= -m_cfg.dailyMaxLoss + DP_MONEY_EPS)
      m_dailyLossSticky = true;

   m_dailyFloorLevel    = DpDailyFloorTrigger(m_cfg.dailyStartBalance, m_cfg.dailyFloorBufferPct);
   m_dailyFloorArmLevel = DpDailyFloorTrigger(m_cfg.dailyStartBalance, m_cfg.dailyFloorArmPct);
   if(m_cfg.enableDailyFloor && m_cfg.dailyStartBalance > 0.0)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > m_dailyPeakEquity)
         m_dailyPeakEquity = equity;
      // Inactive until peak equity has reached start + arm% (e.g. 630 on a 600 seed).
      // Sticky so a later drawdown is still protected.
      if(m_dailyFloorArmLevel > 0.0 &&
         m_dailyPeakEquity + DP_MONEY_EPS >= m_dailyFloorArmLevel)
         m_dailyFloorArmed = true;
      if(m_dailyFloorArmed && m_dailyFloorLevel > 0.0 &&
         equity <= m_dailyFloorLevel + DP_MONEY_EPS)
         m_dailyFloorSticky = true;
     }
  }

void CDomEngine::EnqueueAccountFlatten(const ENUM_DP_REASON reason, const string detail)
  {
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(!PositionSelectByTicket(ticket))
         continue;
      if(!DpManageMagic(PositionGetInteger(POSITION_MAGIC), m_cfg))
         continue;
      Enqueue(ticket, false, 0.0, reason, detail);
     }

   int orders = OrdersTotal();
   for(int i = 0; i < orders; i++)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(!OrderSelect(ticket))
         continue;
      ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY || type == ORDER_TYPE_SELL)
         continue;
      if(!DpManageMagic(OrderGetInteger(ORDER_MAGIC), m_cfg))
         continue;
      Enqueue(ticket, true, 0.0, reason, detail);
     }
  }

void CDomEngine::EvaluatePendings(void)
  {
   bool posInScope = false;
   for(int i = 0; i < m_posN; i++)
     {
      if(InOneTradeScope(m_pos[i].symbol))
        {
         posInScope = true;
         break;
        }
     }

   bool hourNowLosing = m_cfg.blockLosingHours && m_time.IsLosingHour(m_report.currentHour);
   double money = DpLotRefValue(m_cfg.lotReference);

   for(int i = 0; i < m_pendN; i++)
     {
      ENUM_DP_REASON reason = DP_REASON_NONE;
      string detail = "";

      if(m_dailyFloorSticky)
        {
         reason = DP_REASON_DAILY_FLOOR;
         detail = DpFloorDetail(m_dailyFloorLevel);
        }
      else if(Grandfathered(m_pend[i].timeSetup))
         continue;
      else if(m_dailyLossSticky)
        {
         reason = DP_REASON_DAILY_LOSS;
         detail = "daily loss cap";
        }
      else if(m_dailyHitSticky)
        {
         reason = DP_REASON_DAILY_LOCK;
         detail = "daily goal";
        }
      else if(DpIsAtlPending(m_pend[i]))
        {
         if(hourNowLosing)
           {
            reason = DP_REASON_LOSING_HOUR;
            detail = "no ATL adds in a losing hour";
           }
         else
            continue;
        }
      else if(m_cfg.enableAtl &&
              AtlSameDirOpen(m_pend[i].symbol, DpPosTypeFromOrder(m_pend[i].type)))
         continue;
      else if(m_cfg.enableOneTrade && posInScope && InOneTradeScope(m_pend[i].symbol))
        {
         reason = DP_REASON_PENDING;
         detail = "position already open";
        }
      else if(hourNowLosing)
        {
         reason = DP_REASON_LOSING_HOUR;
         detail = "current hour is a losing bucket";
        }
      else if(m_cfg.enableLotGuard)
        {
         double maxLots = DpMaxLots(m_pend[i].symbol, money, m_cfg.balancePer001, m_cfg.lotUnit);
         if(m_pend[i].volume > maxLots + DP_VOLUME_EPS)
           {
            reason = DP_REASON_LOT_CAP;
            detail = "vol " + DpLots(m_pend[i].volume) + " > max " + DpLots(maxLots);
           }
        }

      if(reason != DP_REASON_NONE)
         Enqueue(m_pend[i].ticket, true, 0.0, reason, detail);
     }
  }

ENUM_DP_ZONE CDomEngine::ZoneOf(const double pnl, const double soft, const double hard,
                                const double tp, const bool locked, const double lockFloor) const
  {
   if(pnl >= tp - DP_MONEY_EPS)
      return DP_ZONE_TARGET;
   if(locked && pnl <= lockFloor + DP_MONEY_EPS)
      return DP_ZONE_LOCKED;
   if(pnl <= -hard + DP_MONEY_EPS)
      return DP_ZONE_KILL;
   if(pnl <= -soft + DP_MONEY_EPS)
      return DP_ZONE_AMBER;
   if(pnl < -DP_MONEY_EPS)
      return DP_ZONE_BREATH;
   return DP_ZONE_FLAT;
  }

void CDomEngine::EvaluatePositions(void)
  {
   int keeper = (m_cfg.enableOneTrade ? KeeperIndex() : -1);
   double money = DpLotRefValue(m_cfg.lotReference);
   datetime now = TimeCurrent();

   for(int i = 0; i < m_posN; i++)
     {
      SPosSnap snap = m_pos[i];
      int si = EnsureState(snap);
      if(si < 0)
         continue;

      bool gf = Grandfathered(snap.timeOpen);
      bool inGrid = InAtlBasket(snap.symbol, snap.type);
      double tpMoney = 0.0, softMoney = 0.0, hardMoney = 0.0;
      DpMoneyBand(snap.volume, m_cfg, tpMoney, softMoney, hardMoney);

      double lockFloor = 0.0;
      if(m_cfg.enableProfitLock)
         lockFloor = m_cfg.lockToR * softMoney;

      if(m_cfg.enableProfitLock && tpMoney > 0.0 &&
         m_st[si].peakProfit + DP_MONEY_EPS >= tpMoney * m_cfg.lockTriggerPct / 100.0)
         m_st[si].profitLocked = true;

      ENUM_DP_REASON reason = DP_REASON_NONE;
      string detail = "";
      double closeVol = 0.0; // full

      if(m_dailyFloorSticky)
        {
         reason = DP_REASON_DAILY_FLOOR;
         detail = DpFloorDetail(m_dailyFloorLevel);
        }
      else if(!gf && m_dailyLossSticky)
        {
         reason = DP_REASON_DAILY_LOSS;
         detail = "daily PnL " + DoubleToString(m_dailyPnl, 2);
        }
      else if(!gf && m_cfg.enableOneTrade && keeper >= 0 && i != keeper &&
              InOneTradeScope(snap.symbol) && !AtlHasMate(i))
        {
         reason = DP_REASON_EXTRA_POS;
         detail = "keeper #" + IntegerToString((long)m_pos[keeper].ticket);
        }
      else if(!gf && m_cfg.enableOneTrade && InOneTradeScope(snap.symbol) &&
              m_st[si].lastVolume > DP_VOLUME_EPS &&
              snap.volume > m_st[si].lastVolume + DP_VOLUME_EPS &&
              !m_cfg.enableAtl)
        {
         reason = DP_REASON_SCALE_IN;
         closeVol = snap.volume - m_st[si].lastVolume;
         detail = "delta " + DpLots(closeVol);
        }
      else if(!gf && m_cfg.enableLotGuard)
        {
         double maxLots = DpMaxLots(snap.symbol, money, m_cfg.balancePer001, m_cfg.lotUnit);
         if(snap.volume > maxLots + DP_VOLUME_EPS)
           {
            reason = DP_REASON_LOT_CAP;
            detail = "vol " + DpLots(snap.volume) + " > max " + DpLots(maxLots);
           }
        }

      if(reason == DP_REASON_NONE && !gf && m_cfg.blockLosingHours &&
         m_time.IsLosingEntry(snap.timeOpen) && !inGrid)
        {
         reason = DP_REASON_LOSING_HOUR;
         detail = "opened " + DpHourLabel(DpHourOf(snap.timeOpen, m_cfg)) + ":00";
        }

      if(reason == DP_REASON_NONE && !gf && m_dailyHitSticky)
        {
         bool flatten = m_cfg.dailyLockFlatten;
         bool isNew   = (snap.timeOpen >= m_dailyLockSince && m_dailyLockSince > 0);
         if(flatten || (isNew && !inGrid))
           {
            reason = DP_REASON_DAILY_LOCK;
            detail = "daily " + DoubleToString(m_dailyPnl, 2)
                     + " / " + DoubleToString(m_cfg.dailyLockMoney, 2);
           }
        }

      // Money guard — skip individual TP/SL on an active add-to-losers basket.
      if(reason == DP_REASON_NONE && m_cfg.enableMoneyGuard && !inGrid)
        {
         ENUM_DP_ZONE zone = ZoneOf(snap.profitNet, softMoney, hardMoney, tpMoney,
                                    m_st[si].profitLocked, lockFloor);
         if(zone == DP_ZONE_TARGET)
           {
            reason = DP_REASON_TAKE_PROFIT;
            detail = DoubleToString(snap.profitNet, 2) + " >= TP " + DoubleToString(tpMoney, 2);
           }
         else if(m_st[si].profitLocked && snap.profitNet <= lockFloor + DP_MONEY_EPS)
           {
            reason = DP_REASON_PROFIT_LOCK;
            detail = "floor " + DoubleToString(lockFloor, 2);
           }
         else if(zone == DP_ZONE_KILL)
           {
            reason = DP_REASON_HARD_STOP;
            detail = DoubleToString(snap.profitNet, 2) + " <= -" + DoubleToString(hardMoney, 2);
           }
         else if(zone == DP_ZONE_AMBER)
           {
            if(m_st[si].amberSince <= 0)
               m_st[si].amberSince = now;
            if(m_cfg.amberMaxSeconds > 0 &&
               (now - m_st[si].amberSince) >= m_cfg.amberMaxSeconds)
              {
               reason = DP_REASON_AMBER_TIMEOUT;
               detail = IntegerToString((int)(now - m_st[si].amberSince)) + "s in amber";
              }
           }
         else
            m_st[si].amberSince = 0;
        }
      else if(m_cfg.enableMoneyGuard)
        {
         // still track amber clock for the dashboard even if another reason fires
         ENUM_DP_ZONE zone = ZoneOf(snap.profitNet, softMoney, hardMoney, tpMoney,
                                    m_st[si].profitLocked, lockFloor);
         if(zone != DP_ZONE_AMBER)
            m_st[si].amberSince = 0;
        }

      if(reason != DP_REASON_NONE)
         Enqueue(snap.ticket, false, closeVol, reason, detail);

      ApplyMoneyAndStops(i, reason != DP_REASON_NONE || inGrid);
     }
  }

void CDomEngine::ApplyMoneyAndStops(const int idx, const bool willClose)
  {
   if(willClose || !m_cfg.enableMoneyGuard)
      return;
   if(!m_cfg.setBrokerHardSl && !m_cfg.setBrokerTp)
      return;
   if(m_cfg.dryRun)
      return;

   SPosSnap snap = m_pos[idx];
   int si = FindState(snap.ticket);
   if(si < 0)
      return;

   double tpMoney = 0.0, softMoney = 0.0, hardMoney = 0.0;
   DpMoneyBand(snap.volume, m_cfg, tpMoney, softMoney, hardMoney);

   double slPrice = 0.0;
   double tpPrice = 0.0;
   bool wantSl = m_cfg.setBrokerHardSl;
   bool wantTp = m_cfg.setBrokerTp;

   if(wantSl)
     {
      double slTarget = (m_st[si].profitLocked ? m_cfg.lockToR * softMoney : -hardMoney);
      if(!DpPriceForMoney(snap.symbol, snap.type, snap.volume, snap.priceOpen, slTarget, slPrice))
         wantSl = false;
      else if(!DpStopDistanceOk(snap.symbol, slPrice, snap.type == POSITION_TYPE_BUY, true))
         wantSl = false;
     }
   if(wantTp)
     {
      if(!DpPriceForMoney(snap.symbol, snap.type, snap.volume, snap.priceOpen, tpMoney, tpPrice))
         wantTp = false;
      else if(!DpStopDistanceOk(snap.symbol, tpPrice, snap.type == POSITION_TYPE_BUY, false))
         wantTp = false;
     }

   double newSl = (wantSl ? slPrice : snap.sl);
   double newTp = (wantTp ? tpPrice : snap.tp);

   double tick = SymbolInfoDouble(snap.symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick <= 0.0)
      tick = snap.point;
   bool slSame = (!wantSl) || MathAbs(snap.sl - newSl) < tick * 0.5;
   bool tpSame = (!wantTp) || MathAbs(snap.tp - newTp) < tick * 0.5;
   if(slSame && tpSame && m_st[si].brokerStopsSet)
      return;
   if(!wantSl && !wantTp)
      return;

   DpPrepareTrade(m_trade, snap.symbol, m_cfg.slippagePoints);
   if(!m_trade.PositionModify(snap.ticket, newSl, newTp))
     {
      DpLog(2, m_cfg.logLevel,
            "broker SL/TP modify failed #" + IntegerToString((long)snap.ticket) +
            " ret=" + DpRetcodeText(m_trade.ResultRetcode()));
      return;
     }
   m_st[si].brokerStopsSet = true;
  }

bool CDomEngine::ExecuteClose(SCloseReq &req)
  {
   if(req.isPending)
     {
      if(!OrderSelect(req.ticket))
         return true;
      if(m_cfg.dryRun)
         return true;
      DpPrepareTrade(m_trade, OrderGetString(ORDER_SYMBOL), m_cfg.slippagePoints);
      return m_trade.OrderDelete(req.ticket);
     }

   if(!PositionSelectByTicket(req.ticket))
      return true;
   string symbol = PositionGetString(POSITION_SYMBOL);
   double vol    = PositionGetDouble(POSITION_VOLUME);

   if(m_cfg.dryRun)
      return true;

   DpPrepareTrade(m_trade, symbol, m_cfg.slippagePoints);
   bool full = (req.volume <= DP_VOLUME_EPS || req.volume + DP_VOLUME_EPS >= vol);
   double part = 0.0;
   if(!full)
     {
      part = DpNormalizeVolume(symbol, req.volume);
      if(part <= DP_VOLUME_EPS || part + DP_VOLUME_EPS >= vol)
         full = true;
     }

   ENUM_ORDER_TYPE_FILLING modes[3];
   int nm = 0;
   uint filling = (uint)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      modes[nm++] = ORDER_FILLING_IOC;
   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      modes[nm++] = ORDER_FILLING_FOK;
   modes[nm++] = ORDER_FILLING_RETURN;

   for(int i = 0; i < nm; i++)
     {
      m_trade.SetTypeFilling(modes[i]);
      bool ok = (full ? m_trade.PositionClose(req.ticket)
                      : m_trade.PositionClosePartial(req.ticket, part));
      if(ok)
         return true;
      if(m_trade.ResultRetcode() != TRADE_RETCODE_INVALID_FILL)
         return false;
     }
   return false;
  }

void CDomEngine::AlertClose(const string text)
  {
   if(m_cfg.alertOnClose)
      Alert(DP_LOG_PREFIX, text);
   if(m_cfg.notifyOnClose)
      SendNotification("DomPanion: " + text);
  }

void CDomEngine::ProcessQueue(void)
  {
   bool rebuildHist = false;
   datetime now = TimeCurrent();
   for(int i = m_qN - 1; i >= 0; i--)
     {
      if(m_q[i].inFlight)
         continue;
      if(m_q[i].attempts > 0 && m_q[i].lastTry == now)
         continue;
      if(!m_cfg.dryRun && !DpTradeAllowed())
        {
         m_lastError = "Algo Trading is off";
         continue;
        }

      m_q[i].inFlight = true;
      m_q[i].lastTry  = now;
      m_q[i].attempts++;

      bool ok = ExecuteClose(m_q[i]);
      uint rc = m_trade.ResultRetcode();
      m_q[i].inFlight = false;

      bool gone = m_q[i].isPending ? !OrderSelect(m_q[i].ticket)
                                   : !PositionSelectByTicket(m_q[i].ticket);
      if(m_cfg.dryRun)
         gone = true;

      if(ok || gone ||
         rc == TRADE_RETCODE_DONE ||
         rc == TRADE_RETCODE_PLACED ||
         rc == TRADE_RETCODE_DONE_PARTIAL ||
         rc == TRADE_RETCODE_POSITION_CLOSED)
        {
         string tag = (m_cfg.dryRun ? "DRY " : "");
         string kind = (m_q[i].isPending ? "delete pending #" : "close #");
         string msg = tag + kind + IntegerToString((long)m_q[i].ticket)
                      + "  " + DpReasonText(m_q[i].reason)
                      + "  " + m_q[i].detail;
         bool announce = !m_cfg.dryRun || NoteOnce(m_q[i].ticket);
         if(announce)
           {
            DpLog(1, m_cfg.logLevel, msg);
            PushAction(m_q[i].reason, msg);
            if(!m_cfg.dryRun)
               AlertClose(msg);
           }
         DequeueAt(i);
         m_lastError = "";
         if(!m_cfg.dryRun)
            rebuildHist = true;
         continue;
        }

      string err = "fail #" + IntegerToString((long)m_q[i].ticket)
                   + " " + DpReasonText(m_q[i].reason)
                   + " ret=" + DpRetcodeText(rc);
      m_lastError = err;
      DpLog(0, m_cfg.logLevel, err);

      if(rc == TRADE_RETCODE_INVALID_CLOSE_VOLUME && m_q[i].volume > DP_VOLUME_EPS)
        {
         m_q[i].volume = 0.0;
         continue;
        }

      if(!DpRetryable(rc))
        {
         PushAction(m_q[i].reason, "GIVE UP " + err);
         MarkDead(m_q[i].ticket);
         DequeueAt(i);
        }
      else if(m_q[i].attempts >= DP_MAX_CLOSE_ATTEMPTS)
        {
         m_q[i].attempts = DP_MAX_CLOSE_ATTEMPTS - 1;
        }
     }

   if(rebuildHist)
      m_time.Rebuild(true);
  }

void CDomEngine::BuildView(void)
  {
   ZeroMemory(m_vm);
   m_vm.valid      = true;
   m_vm.symbol     = m_cfg.symbol;
   m_vm.currency   = AccountInfoString(ACCOUNT_CURRENCY);
   m_vm.balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   m_vm.equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   m_vm.serverTime = TimeCurrent();
   m_vm.lastError  = m_lastError;
   m_vm.time       = m_report;

   SGuardView g;
   ZeroMemory(g);
   g.timeOn          = m_cfg.enableTimeAnalysis || (StringLen(m_cfg.manualLosingHours) > 0);
   g.timeBlocking    = m_cfg.blockLosingHours;
   g.timeNowLosing   = m_report.currentHourLosing;
   g.timeNowLabel    = DpHourLabel(m_report.currentHour) + ":00 "
                       + (g.timeNowLosing ? "LOSE" : "SAFE");
   g.lotOn           = m_cfg.enableLotGuard;
   g.balancePer001   = m_cfg.balancePer001;
   g.maxLots         = DpMaxLots(m_cfg.symbol, DpLotRefValue(m_cfg.lotReference),
                                 m_cfg.balancePer001, m_cfg.lotUnit);
   g.moneyOn         = m_cfg.enableMoneyGuard;
   g.tpPer001        = m_cfg.tpPer001;
   g.hardMult        = m_cfg.breathMultiplier;
   g.oneTradeOn      = m_cfg.enableOneTrade;
   g.openCount       = m_posN;
   g.atlOverridesOne = (m_cfg.enableAtl && m_cfg.enableOneTrade);
   g.dailyOn         = m_cfg.enableDailyLock;
   g.dailyPnl        = m_dailyPnl;
   g.dailyTarget     = m_cfg.dailyLockMoney;
   g.dailyHit           = m_dailyHitSticky;
   g.dailyLossHit       = m_dailyLossSticky;
   g.dailyFloorOn       = m_cfg.enableDailyFloor;
   g.dailyStartBalance  = m_cfg.dailyStartBalance;
   g.dailyFloorLevel    = m_dailyFloorLevel;
   g.dailyFloorArmLevel = m_dailyFloorArmLevel;
   g.dailyFloorArmed    = m_dailyFloorArmed;
   g.dailyFloorHit      = m_dailyFloorSticky;
   AtlFillView(g);
   g.dryRun          = m_cfg.dryRun;
   g.armed           = m_armed;
   g.ownerConflict   = m_ownerConflict;
   g.tradeAllowed    = DpTradeAllowed();
   m_vm.guards       = g;

   double money = DpLotRefValue(m_cfg.lotReference);
   m_vm.posCount = 0;
   for(int i = 0; i < m_posN && m_vm.posCount < DP_MAX_POSITIONS; i++)
     {
      SPosSnap snap = m_pos[i];
      int si = FindState(snap.ticket);
      SPosView v;
      ZeroMemory(v);
      v.ticket     = snap.ticket;
      v.symbol     = snap.symbol;
      v.side       = (snap.type == POSITION_TYPE_BUY ? "BUY" : "SELL");
      v.volume     = snap.volume;
      v.profitNet  = snap.profitNet;
      DpMoneyBand(snap.volume, m_cfg, v.tpMoney, v.softSlMoney, v.hardSlMoney);
      v.peakProfit   = (si >= 0 ? m_st[si].peakProfit : snap.profitNet);
      v.troughProfit = (si >= 0 ? m_st[si].troughProfit : snap.profitNet);
      v.profitLocked = (si >= 0 && m_st[si].profitLocked);
      double lockFloor = m_cfg.lockToR * v.softSlMoney;
      v.zone = ZoneOf(snap.profitNet, v.softSlMoney, v.hardSlMoney, v.tpMoney,
                      v.profitLocked, lockFloor);
      v.zoneName = DpZoneName(v.zone);
      v.amberLeftSec = -1;
      if(si >= 0 && m_st[si].amberSince > 0 && m_cfg.amberMaxSeconds > 0)
        {
         int used = (int)(TimeCurrent() - m_st[si].amberSince);
         v.amberLeftSec = MathMax(0, m_cfg.amberMaxSeconds - used);
        }
      v.maxLotsNow = DpMaxLots(snap.symbol, money, m_cfg.balancePer001, m_cfg.lotUnit);
      m_vm.positions[m_vm.posCount++] = v;
     }

   m_vm.actionCount = m_actionN;
   for(int i = 0; i < m_actionN; i++)
      m_vm.actions[i] = m_actions[i];

   if(m_ownerConflict)
      m_vm.headline = "Standby — another DomPanion owns all-symbols mode";
   else if(!g.tradeAllowed)
      m_vm.headline = "Algo Trading OFF — guards cannot close";
   else if(m_dailyFloorSticky)
      m_vm.headline = "START FLOOR — flattening / blocking for today";
   else if(m_cfg.enableDailyFloor && !m_dailyFloorArmed)
      m_vm.headline = "Floor waiting — arm at "
                      + DoubleToString(m_dailyFloorArmLevel, 2);
   else if(m_dailyLossSticky)
      m_vm.headline = "Daily loss cap hit — flattening / blocking";
   else if(m_dailyHitSticky)
      m_vm.headline = "Daily goal hit — new trades blocked";
   else if(g.atlActive)
      m_vm.headline = "ATL " + IntegerToString(g.atlLegs) + "  "
                      + g.atlStatus + "  pnl " + DoubleToString(g.atlBasketPnl, 2)
                      + " / " + DoubleToString(g.atlBeTarget, 2);
   else if(g.timeBlocking && g.timeNowLosing)
      m_vm.headline = "LOSING HOUR — entries will be closed";
   else if(m_posN > 0)
      m_vm.headline = IntegerToString(m_posN) + " open  ·  max lot "
                      + DpLots(g.maxLots);
   else
      m_vm.headline = "No position — " + (g.timeNowLosing ? "LOSING HOUR" : "SAFE")
                      + "  ·  max lot " + DpLots(g.maxLots);
  }

void CDomEngine::Render(const bool force)
  {
   uint now = GetTickCount();
   if(!force && m_lastRenderMs != 0 && (now - m_lastRenderMs) < DP_RENDER_MS)
      return;
   BuildView();
   m_dash.Render(m_vm);
   m_lastRenderMs = now;
  }

void CDomEngine::Work(void)
  {
   if(!m_inited)
      return;

   if(m_cfg.manageScope == DP_SCOPE_ACCOUNT)
     {
      m_armed = DpClaimOwnership(m_cfg.chartId, true, m_ownerConflict);
     }
   else
     {
      m_armed = true;
      m_ownerConflict = false;
     }

   m_time.Rebuild(false);
   m_time.CopyReport(m_report);

   SnapshotPositions();
   SnapshotPendings();
   RebuildAtlBaskets();

   if(m_armed)
     {
      RefreshDaily();
      if(m_dailyFloorSticky)
         EnqueueAccountFlatten(DP_REASON_DAILY_FLOOR, DpFloorDetail(m_dailyFloorLevel));
      EvaluatePendings();
      EvaluatePositions();
      RunAddToLosers();
      PruneState();
      PruneDead();
      ProcessQueue();
     }
   else
     {
      for(int i = 0; i < m_posN; i++)
         EnsureState(m_pos[i]);
      PruneState();
      RefreshDaily();
     }
  }

void CDomEngine::Pulse(void)
  {
   if(m_inPulse)
     {
      m_needReplay = true;
      return;
     }
   m_inPulse = true;
   int hops = 0;
   do
     {
      m_needReplay = false;
      Work();
      hops++;
     }
   while(m_needReplay && hops < 2);
   m_inPulse = false;
   Render(false);
  }

bool CDomEngine::Init(const SDpConfig &cfg)
  {
   ResetRuntime();
   m_cfg = cfg;
   if(m_cfg.breathMultiplier < 1.0)
      m_cfg.breathMultiplier = 1.0;
   if(m_cfg.lotUnit <= 0.0)
      m_cfg.lotUnit = 0.01;
   if(m_cfg.historyDays < 1)
      m_cfg.historyDays = 1;
   if(m_cfg.minTradesPerHour < 1)
      m_cfg.minTradesPerHour = 1;
   if(m_cfg.slippagePoints < 0)
      m_cfg.slippagePoints = 0;
   if(m_cfg.lockTriggerPct < 0.0)
      m_cfg.lockTriggerPct = 0.0;
   if(m_cfg.lockTriggerPct > 100.0)
      m_cfg.lockTriggerPct = 100.0;
   if(m_cfg.panelWidth < 220)
      m_cfg.panelWidth = 220;
   if(m_cfg.historyDays > 3650)
      m_cfg.historyDays = 3650;
   if(m_cfg.panelScale < 0.5)
      m_cfg.panelScale = 0.5;
   if(m_cfg.panelScale > 2.0)
      m_cfg.panelScale = 2.0;
   if(m_cfg.losingWinRatePct < 0.0)
      m_cfg.losingWinRatePct = 0.0;
   if(m_cfg.losingWinRatePct > 100.0)
      m_cfg.losingWinRatePct = 100.0;
   if(m_cfg.amberMaxSeconds < 0)
      m_cfg.amberMaxSeconds = 0;
   if(m_cfg.lockToR < 0.0)
      m_cfg.lockToR = 0.0;
   if(m_cfg.fontSize < 9)
      m_cfg.fontSize = 9;
   if(m_cfg.offsetX < 0)
      m_cfg.offsetX = 0;
   if(m_cfg.offsetY < 0)
      m_cfg.offsetY = 0;

   m_initTime = TimeCurrent();
   m_dayStamp = DpDayStartServer();
   m_armed    = true;

   if(m_cfg.enableLotGuard && m_cfg.balancePer001 <= 0.0)
     {
      Print(DP_LOG_PREFIX, "Lot Guard needs Balance per 0.01 > 0");
      return false;
     }
   if(m_cfg.enableMoneyGuard && (m_cfg.tpPer001 <= 0.0 || m_cfg.slPer001 <= 0.0))
     {
      Print(DP_LOG_PREFIX, "Money Guard needs TP per 0.01 and SL per 0.01 > 0");
      return false;
     }
   if(m_cfg.enableDailyFloor && m_cfg.dailyStartBalance <= 0.0)
     {
      Print(DP_LOG_PREFIX, "Daily Start Floor needs Starting balance > 0");
      return false;
     }
   if(m_cfg.dailyFloorBufferPct < 0.0)
      m_cfg.dailyFloorBufferPct = 0.0;
   if(m_cfg.dailyFloorBufferPct > 100.0)
      m_cfg.dailyFloorBufferPct = 100.0;
   if(m_cfg.dailyFloorArmPct < 0.0)
      m_cfg.dailyFloorArmPct = 0.0;
   if(m_cfg.dailyFloorArmPct > 100.0)
      m_cfg.dailyFloorArmPct = 100.0;
   if(m_cfg.atlMaxTrades < 2)
      m_cfg.atlMaxTrades = 2;
   if(m_cfg.atlMaxTrades > 20)
      m_cfg.atlMaxTrades = 20;
   if(m_cfg.atlBePlusPct < 0.0)
      m_cfg.atlBePlusPct = 0.0;
   if(m_cfg.atlLot < 0.0)
      m_cfg.atlLot = 0.0;

   if(m_cfg.enableDailyFloor &&
      m_cfg.dailyFloorArmPct <= m_cfg.dailyFloorBufferPct)
     {
      Print(DP_LOG_PREFIX,
            "Daily Start Floor: Arm % must be greater than Buffer % "
            "(else it would lock the moment it arms). Default 5 vs 3.");
      return false;
     }

   m_time.Configure(m_cfg);
   if(!m_time.SpecOk())
     {
      m_lastError = "hour spec: " + m_time.SpecError();
      Print(DP_LOG_PREFIX, m_lastError);
      return false;
     }

   if(m_cfg.manageScope == DP_SCOPE_ACCOUNT)
      m_armed = DpClaimOwnership(m_cfg.chartId, true, m_ownerConflict);

   m_dash.Init(m_cfg);
   m_inited = true;
   m_time.Rebuild(true);
   m_time.CopyReport(m_report);

   if(!EventSetMillisecondTimer(DP_TIMER_MS))
     {
      EventSetTimer(1);
      DpLog(0, m_cfg.logLevel, "millisecond timer failed, falling back to 1s");
     }

   Pulse();
   Render(true);

   DpLog(1, m_cfg.logLevel,
         "ready  symbol=" + m_cfg.symbol
         + "  scope=" + (m_cfg.manageScope == DP_SCOPE_ACCOUNT ? "account" : "chart")
         + "  hedge=" + (DpIsHedging() ? "yes" : "no")
         + "  corner=" + DpCornerName(m_cfg.corner)
         + (m_cfg.dryRun ? "  DRY RUN" : ""));
   return true;
  }

void CDomEngine::Deinit(const int reason)
  {
   EventKillTimer();
   m_dash.Deinit();
   if(reason == REASON_CHARTCLOSE || reason == REASON_REMOVE ||
      reason == REASON_RECOMPILE || reason == REASON_CLOSE ||
      reason == REASON_INITFAILED || reason == REASON_ACCOUNT)
      DpReleaseOwnership(m_cfg.chartId, m_cfg.manageScope == DP_SCOPE_ACCOUNT);
   m_inited = false;
  }

void CDomEngine::OnTick(void)
  {
   Pulse();
  }

void CDomEngine::OnTimer(void)
  {
   Pulse();
   Render(true);
  }

void CDomEngine::OnTradeTransaction(const MqlTradeTransaction &trans)
  {
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
      trans.type == TRADE_TRANSACTION_POSITION ||
      trans.type == TRADE_TRANSACTION_ORDER_ADD ||
      trans.type == TRADE_TRANSACTION_ORDER_DELETE ||
      trans.type == TRADE_TRANSACTION_HISTORY_ADD)
     {
      m_time.Rebuild(true);
      Pulse();
     }
  }

void CDomEngine::OnChartEvent(const int id)
  {
   if(id == CHARTEVENT_CHART_CHANGE)
      Render(true);
  }

#include "AddToLosers.mqh"

#endif // DOMPANION_ENGINE_MQH
