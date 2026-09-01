#ifndef DOMPANION_ADDTOLOSERS_MQH
#define DOMPANION_ADDTOLOSERS_MQH

//+------------------------------------------------------------------+
//| AddToLosers.mqh                                                  |
//| Copyright 2026, Dominik Fischer                                  |
//| Grid-in on a manual 2nd add. Engine methods only.                |
//+------------------------------------------------------------------+

void CDomEngine::AtlSortBasket(SAtlBasket &b)
  {
   for(int i = 0; i < b.n - 1; i++)
     {
      for(int j = i + 1; j < b.n; j++)
        {
         int ia = b.idx[i];
         int ib = b.idx[j];
         if(m_pos[ib].timeOpen < m_pos[ia].timeOpen ||
            (m_pos[ib].timeOpen == m_pos[ia].timeOpen && m_pos[ib].ticket < m_pos[ia].ticket))
           {
            b.idx[i] = ib;
            b.idx[j] = ia;
           }
        }
     }
  }

bool CDomEngine::AtlFromDeals(const SPosSnap &p, double &first, double &step,
                              double &addVol, int &legs)
  {
   first = 0.0;
   step = 0.0;
   addVol = 0.0;
   legs = 0;
   if(!HistorySelectByPosition(p.id))
      return false;

   double px[];
   double vol[];
   int n = 0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      ENUM_DEAL_TYPE dt = (ENUM_DEAL_TYPE)HistoryDealGetInteger(d, DEAL_TYPE);
      if(dt != DEAL_TYPE_BUY && dt != DEAL_TYPE_SELL)
         continue;
      ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
      if(en != DEAL_ENTRY_IN && en != DEAL_ENTRY_INOUT)
         continue;
      int k = n++;
      if(ArrayResize(px, n, 8) < n || ArrayResize(vol, n, 8) < n)
         break;
      px[k]  = HistoryDealGetDouble(d, DEAL_PRICE);
      vol[k] = HistoryDealGetDouble(d, DEAL_VOLUME);
     }
   if(n < 2)
      return false;
   first  = px[0];
   step   = MathAbs(px[1] - px[0]);
   addVol = vol[1];
   legs   = n;
   return (step > 0.0);
  }

bool CDomEngine::AtlLevelFilled(const SAtlBasket &b, const double level)
  {
   if(b.n >= 2)
     {
      for(int i = 0; i < b.n; i++)
        {
         if(DpPriceNear(b.symbol, m_pos[b.idx[i]].priceOpen, level, b.step))
            return true;
        }
      return false;
     }
   if(b.n == 1)
     {
      if(!HistorySelectByPosition(m_pos[b.idx[0]].id))
         return false;
      int deals = HistoryDealsTotal();
      for(int i = 0; i < deals; i++)
        {
         ulong d = HistoryDealGetTicket(i);
         if(d == 0)
            continue;
         ENUM_DEAL_TYPE dt = (ENUM_DEAL_TYPE)HistoryDealGetInteger(d, DEAL_TYPE);
         if(dt != DEAL_TYPE_BUY && dt != DEAL_TYPE_SELL)
            continue;
         ENUM_DEAL_ENTRY en = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY);
         if(en != DEAL_ENTRY_IN && en != DEAL_ENTRY_INOUT)
            continue;
         double px = HistoryDealGetDouble(d, DEAL_PRICE);
         if(DpPriceNear(b.symbol, px, level, b.step))
            return true;
        }
     }
   return false;
  }

void CDomEngine::RebuildAtlBaskets(void)
  {
   m_atlN = 0;
   if(!m_cfg.enableAtl)
      return;

   for(int i = 0; i < m_posN; i++)
     {
      int slot = -1;
      for(int b = 0; b < m_atlN; b++)
        {
         if(m_atl[b].symbol == m_pos[i].symbol && m_atl[b].type == m_pos[i].type)
           {
            slot = b;
            break;
           }
        }
      if(slot < 0)
        {
         if(m_atlN >= DP_MAX_ATL_BASKETS)
            continue;
         slot = m_atlN++;
         m_atl[slot].active = false;
         m_atl[slot].symbol = m_pos[i].symbol;
         m_atl[slot].type   = m_pos[i].type;
         m_atl[slot].n      = 0;
         m_atl[slot].pendingTicket = 0;
         m_atl[slot].nextMult = 0;
         m_atl[slot].nextPrice = 0.0;
         m_atl[slot].pnl = 0.0;
         m_atl[slot].step = 0.0;
         m_atl[slot].firstPrice = 0.0;
         m_atl[slot].addVolume = 0.0;
        }
      if(m_atl[slot].n < DP_MAX_POSITIONS)
         m_atl[slot].idx[m_atl[slot].n++] = i;
     }

   for(int b = 0; b < m_atlN; b++)
     {
      SAtlBasket basket = m_atl[b];
      AtlSortBasket(basket);
      basket.pnl = 0.0;
      for(int i = 0; i < basket.n; i++)
         basket.pnl += m_pos[basket.idx[i]].profitNet;

      int legs = basket.n;
      if(basket.n >= 2)
        {
         basket.firstPrice = m_pos[basket.idx[0]].priceOpen;
         basket.step       = MathAbs(m_pos[basket.idx[1]].priceOpen - basket.firstPrice);
         basket.addVolume  = m_pos[basket.idx[1]].volume;
        }
      else if(basket.n == 1 && !DpIsHedging())
        {
         double f = 0.0, s = 0.0, v = 0.0;
         int lg = 0;
         if(AtlFromDeals(m_pos[basket.idx[0]], f, s, v, lg) && lg >= 2)
           {
            basket.firstPrice = f;
            basket.step       = s;
            basket.addVolume  = v;
            legs              = lg;
           }
        }

      if(m_cfg.atlLot > 0.0)
         basket.addVolume = DpNormalizeVolume(basket.symbol, m_cfg.atlLot);

      double tick = SymbolInfoDouble(basket.symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick <= 0.0)
         tick = SymbolInfoDouble(basket.symbol, SYMBOL_POINT);
      bool ok = (legs >= 2 && basket.step >= tick * 2.0);
      basket.active = ok;

      basket.nextMult  = 0;
      basket.nextPrice = 0.0;
      if(ok)
        {
         int maxK = m_cfg.atlMaxTrades - 1;
         if(maxK < 2)
            maxK = 2;
         int dir = (basket.type == POSITION_TYPE_BUY ? -1 : 1);
         for(int k = 2; k <= maxK; k++)
           {
            double lvl = DpNormPrice(basket.symbol, basket.firstPrice + dir * k * basket.step);
            if(!AtlLevelFilled(basket, lvl))
              {
               basket.nextMult  = k;
               basket.nextPrice = lvl;
               break;
              }
           }
        }

      for(int p = 0; p < m_pendN; p++)
        {
         if(!DpIsAtlPending(m_pend[p]))
            continue;
         if(m_pend[p].symbol != basket.symbol)
            continue;
         if(DpPosTypeFromOrder(m_pend[p].type) != basket.type)
            continue;
         basket.pendingTicket = m_pend[p].ticket;
         break;
        }
      m_atl[b] = basket;
     }
  }

bool CDomEngine::InAtlBasket(const string symbol, const ENUM_POSITION_TYPE type) const
  {
   if(!m_cfg.enableAtl)
      return false;
   for(int b = 0; b < m_atlN; b++)
     {
      if(m_atl[b].active && m_atl[b].symbol == symbol && m_atl[b].type == type)
         return true;
     }
   return false;
  }

bool CDomEngine::AtlSameDirOpen(const string symbol, const ENUM_POSITION_TYPE type) const
  {
   if(!m_cfg.enableAtl)
      return false;
   for(int i = 0; i < m_posN; i++)
     {
      if(m_pos[i].symbol == symbol && m_pos[i].type == type)
         return true;
     }
   return false;
  }

bool CDomEngine::AtlHasMate(const int posIndex) const
  {
   if(!m_cfg.enableAtl || posIndex < 0 || posIndex >= m_posN)
      return false;
   for(int j = 0; j < m_posN; j++)
     {
      if(j == posIndex)
         continue;
      if(m_pos[j].symbol == m_pos[posIndex].symbol &&
         m_pos[j].type == m_pos[posIndex].type)
         return true;
     }
   return false;
  }

double CDomEngine::AtlBeTarget(void) const
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double t = bal * m_cfg.atlBePlusPct / 100.0;
   if(t < 0.10)
      t = 0.10;
   return t;
  }

void CDomEngine::AtlStripStops(const SAtlBasket &b)
  {
   if(m_cfg.dryRun)
      return;
   for(int i = 0; i < b.n; i++)
     {
      SPosSnap s = m_pos[b.idx[i]];
      if(s.sl == 0.0 && s.tp == 0.0)
         continue;
      DpPrepareTrade(m_trade, s.symbol, m_cfg.slippagePoints);
      m_trade.PositionModify(s.ticket, 0.0, 0.0);
     }
  }

void CDomEngine::AtlEnqueueBasket(const SAtlBasket &b, const string detail)
  {
   for(int i = 0; i < b.n; i++)
      Enqueue(m_pos[b.idx[i]].ticket, false, 0.0, DP_REASON_ATL_BE, detail);
   for(int p = 0; p < m_pendN; p++)
     {
      if(!DpIsAtlPending(m_pend[p]))
         continue;
      if(m_pend[p].symbol != b.symbol)
         continue;
      if(DpPosTypeFromOrder(m_pend[p].type) != b.type)
         continue;
      Enqueue(m_pend[p].ticket, true, 0.0, DP_REASON_ATL_BE, detail);
     }
  }

bool CDomEngine::AtlBlockedAdds(void) const
  {
   if(m_dailyFloorSticky || m_dailyLossSticky)
      return true;
   if(m_dailyHitSticky)
      return true;
   if(m_cfg.blockLosingHours && m_time.IsLosingHour(m_report.currentHour))
      return true;
   if(!m_cfg.dryRun && !DpTradeAllowed())
      return true;
   return false;
  }

void CDomEngine::AtlPlaceNext(SAtlBasket &b)
  {
   if(b.nextMult < 2 || b.nextPrice <= 0.0)
      return;
   if(AtlBlockedAdds())
      return;

   uint nowMs = GetTickCount();
   if(m_atlLastPlaceMs != 0 && (nowMs - m_atlLastPlaceMs) < 1500)
      return;

   double vol = DpNormalizeVolume(b.symbol, b.addVolume);
   if(vol <= DP_VOLUME_EPS)
      return;

   if(m_cfg.enableLotGuard)
     {
      double money = DpLotRefValue(m_cfg.lotReference);
      double maxLots = DpMaxLots(b.symbol, money, m_cfg.balancePer001, m_cfg.lotUnit);
      double have = 0.0;
      for(int i = 0; i < b.n; i++)
         have += m_pos[b.idx[i]].volume;
      if(have + vol > maxLots + DP_VOLUME_EPS)
        {
         b.nextMult = 0;
         return;
        }
     }

   double ask = SymbolInfoDouble(b.symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(b.symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(b.step > 0.0 && spread > b.step * 0.35)
      return;

   bool buy = (b.type == POSITION_TYPE_BUY);
   bool through = buy ? (ask <= b.nextPrice + spread * 0.5)
                      : (bid >= b.nextPrice - spread * 0.5);

   if(m_cfg.dryRun)
     {
      m_atlLastPlaceMs = nowMs;
      PushAction(DP_REASON_ATL_BE,
                 "DRY ATL " + (through ? "market " : "limit ")
                 + DoubleToString(b.nextPrice, (int)SymbolInfoInteger(b.symbol, SYMBOL_DIGITS))
                 + "  x" + IntegerToString(b.nextMult));
      return;
     }

   if(b.pendingTicket > 0)
     {
      if(!OrderSelect(b.pendingTicket))
         b.pendingTicket = 0;
      else
        {
         double px = OrderGetDouble(ORDER_PRICE_OPEN);
         if(DpPriceNear(b.symbol, px, b.nextPrice, b.step))
            return;
         DpPrepareTrade(m_trade, b.symbol, m_cfg.slippagePoints);
         m_trade.OrderDelete(b.pendingTicket);
         b.pendingTicket = 0;
        }
     }

   DpPrepareTrade(m_trade, b.symbol, m_cfg.slippagePoints);
   m_trade.SetExpertMagicNumber(DP_ATL_MAGIC);
   string cmt = DP_ATL_COMMENT;
   bool ok = false;
   if(through)
     {
      ok = buy ? m_trade.Buy(vol, b.symbol, 0.0, 0.0, 0.0, cmt)
               : m_trade.Sell(vol, b.symbol, 0.0, 0.0, 0.0, cmt);
     }
   else
     {
      ok = buy ? m_trade.BuyLimit(vol, b.nextPrice, b.symbol, 0.0, 0.0, 0, cmt)
               : m_trade.SellLimit(vol, b.nextPrice, b.symbol, 0.0, 0.0, 0, cmt);
     }
   m_trade.SetExpertMagicNumber(0);
   m_atlLastPlaceMs = nowMs;
   if(!ok)
      DpLog(0, m_cfg.logLevel,
            "ATL place failed k=" + IntegerToString(b.nextMult)
            + " ret=" + DpRetcodeText(m_trade.ResultRetcode()));
   else
      DpLog(1, m_cfg.logLevel,
            "ATL place " + (through ? "market" : "limit")
            + " x" + IntegerToString(b.nextMult)
            + " " + DoubleToString(b.nextPrice, (int)SymbolInfoInteger(b.symbol, SYMBOL_DIGITS))
            + "  " + DpLots(vol));
  }

void CDomEngine::RunAddToLosers(void)
  {
   if(!m_cfg.enableAtl)
      return;

   double target = AtlBeTarget();
   for(int b = 0; b < m_atlN; b++)
     {
      if(!m_atl[b].active)
         continue;
      if(m_atl[b].pnl + DP_MONEY_EPS >= target)
        {
         string det = "basket " + DoubleToString(m_atl[b].pnl, 2)
                      + " >= BE+" + DoubleToString(target, 2);
         AtlEnqueueBasket(m_atl[b], det);
         continue;
        }
      AtlStripStops(m_atl[b]);
      AtlPlaceNext(m_atl[b]);
     }
  }

void CDomEngine::AtlFillView(SGuardView &g) const
  {
   g.atlOn       = m_cfg.enableAtl;
   g.atlActive   = false;
   g.atlLegs     = 0;
   g.atlNextMult = 0;
   g.atlBasketPnl= 0.0;
   g.atlBeTarget = AtlBeTarget();
   g.atlNextPrice= 0.0;
   g.atlStatus   = (m_cfg.enableAtl ? "wait 2nd add" : "off");

   int pick = -1;
   for(int b = 0; b < m_atlN; b++)
     {
      if(!m_atl[b].active)
         continue;
      if(m_atl[b].symbol == m_cfg.symbol)
        {
         pick = b;
         break;
        }
      if(pick < 0)
         pick = b;
     }
   if(pick < 0)
      return;

   const SAtlBasket bsk = m_atl[pick];
   g.atlActive    = true;
   g.atlLegs      = bsk.n;
   g.atlNextMult  = bsk.nextMult;
   g.atlBasketPnl = bsk.pnl;
   g.atlNextPrice = bsk.nextPrice;
   if(bsk.pnl + DP_MONEY_EPS >= g.atlBeTarget)
      g.atlStatus = "BE hit — closing";
   else if(bsk.nextMult >= 2)
      g.atlStatus = "x" + IntegerToString(bsk.nextMult) + "  "
                    + DoubleToString(bsk.nextPrice, (int)SymbolInfoInteger(bsk.symbol, SYMBOL_DIGITS));
   else
      g.atlStatus = IntegerToString(bsk.n) + " legs  cap";
  }

#endif
