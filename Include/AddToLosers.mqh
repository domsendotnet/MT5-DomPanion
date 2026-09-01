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

   double   px[];
   double   vol[];
   datetime tm[];
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
      if(ArrayResize(px, n, 8) < n || ArrayResize(vol, n, 8) < n ||
         ArrayResize(tm, n, 8) < n)
         break;
      px[k]  = HistoryDealGetDouble(d, DEAL_PRICE);
      vol[k] = HistoryDealGetDouble(d, DEAL_VOLUME);
      tm[k]  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
     }
   if(n < 2)
      return false;
   for(int i = 0; i < n - 1; i++)
     {
      for(int j = i + 1; j < n; j++)
        {
         if(tm[j] < tm[i] || (tm[j] == tm[i] && px[j] < px[i]))
           {
            datetime tt = tm[i]; tm[i] = tm[j]; tm[j] = tt;
            double tp = px[i];  px[i] = px[j];  px[j] = tp;
            double tv = vol[i]; vol[i] = vol[j]; vol[j] = tv;
           }
        }
     }
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
         m_atl[slot].bePrice = 0.0;
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
      bool ok = (legs >= 2 && basket.step >= tick);
      basket.active = ok;
      basket.bePrice = (ok ? AtlBasketBePrice(basket) : 0.0);

      basket.nextMult  = 0;
      basket.nextPrice = 0.0;
      if(ok)
        {
         // max 2 = the two the user opened, no auto add (k starts at 2).
         int maxK = m_cfg.atlMaxTrades - 1;
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

double CDomEngine::AtlBeTarget(void) const
  {
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double t = bal * m_cfg.atlBePlusPct / 100.0;
   if(t < 0.10)
      t = 0.10;
   return t;
  }

double CDomEngine::AtlBasketBePrice(const SAtlBasket &b) const
  {
   if(b.n <= 0)
      return 0.0;

   double volSum = 0.0;
   double pxVol  = 0.0;
   double extra  = 0.0;
   for(int i = 0; i < b.n; i++)
     {
      int k = b.idx[i];
      if(k < 0 || k >= m_posN)
         continue;
      volSum += m_pos[k].volume;
      pxVol  += m_pos[k].priceOpen * m_pos[k].volume;
      extra  += m_pos[k].swap + m_pos[k].commission;
     }
   if(volSum <= DP_VOLUME_EPS)
      return 0.0;

   double vwap = pxVol / volSum;
   double be   = vwap;
   if(MathAbs(extra) >= DP_MONEY_EPS)
     {
      double px = 0.0;
      if(DpPriceForMoney(b.symbol, b.type, volSum, vwap, -extra, px) && px > 0.0)
         be = px;
     }
   return DpNormPrice(b.symbol, be);
  }

string CDomEngine::AtlBeObjName(const ENUM_POSITION_TYPE type, const bool label) const
  {
   string s = DP_OBJ_ATL_BE;
   s += (label ? ".lbl." : ".");
   s += (type == POSITION_TYPE_BUY ? "buy." : "sell.");
   s += IntegerToString(m_cfg.chartId);
   return s;
  }

void CDomEngine::AtlBeDropLine(const ENUM_POSITION_TYPE type)
  {
   long id = m_cfg.chartId;
   ObjectDelete(id, AtlBeObjName(type, false));
   ObjectDelete(id, AtlBeObjName(type, true));
  }

void CDomEngine::AtlBeLineDelete(void)
  {
   AtlBeDropLine(POSITION_TYPE_BUY);
   AtlBeDropLine(POSITION_TYPE_SELL);
  }

void CDomEngine::AtlBePutLine(const ENUM_POSITION_TYPE type, const double price,
                              const string caption)
  {
   long id = m_cfg.chartId;
   if(id <= 0 || price <= 0.0)
      return;

   string nLine = AtlBeObjName(type, false);
   string nLbl  = AtlBeObjName(type, true);
   color  clr   = (m_cfg.theme == DP_THEME_LIGHT ? C'180,90,0' : C'243,156,18');

   if(ObjectFind(id, nLine) < 0)
     {
      if(!ObjectCreate(id, nLine, OBJ_HLINE, 0, 0, price))
         return;
      ObjectSetInteger(id, nLine, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(id, nLine, OBJPROP_HIDDEN, true);
      ObjectSetInteger(id, nLine, OBJPROP_BACK, false);
      ObjectSetInteger(id, nLine, OBJPROP_WIDTH, 1);
      ObjectSetInteger(id, nLine, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(id, nLine, OBJPROP_COLOR, clr);
     }
   else
     {
      ObjectMove(id, nLine, 0, 0, price);
      ObjectSetInteger(id, nLine, OBJPROP_COLOR, clr);
     }
   ObjectSetString(id, nLine, OBJPROP_TOOLTIP, caption);

   datetime t = iTime(m_cfg.symbol, PERIOD_CURRENT, 0);
   if(t <= 0)
      t = TimeCurrent();

   if(ObjectFind(id, nLbl) < 0)
     {
      if(!ObjectCreate(id, nLbl, OBJ_TEXT, 0, t, price))
         return;
      ObjectSetInteger(id, nLbl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(id, nLbl, OBJPROP_HIDDEN, true);
      ObjectSetInteger(id, nLbl, OBJPROP_BACK, false);
      ObjectSetInteger(id, nLbl, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(id, nLbl, OBJPROP_FONTSIZE, 8);
      ObjectSetString(id, nLbl, OBJPROP_FONT, "Arial");
     }
   ObjectMove(id, nLbl, 0, t, price);
   ObjectSetInteger(id, nLbl, OBJPROP_COLOR, clr);
   ObjectSetString(id, nLbl, OBJPROP_TEXT, caption);
  }

void CDomEngine::SyncAtlBeLine(void)
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;

   bool   wantBuy  = false;
   bool   wantSell = false;
   double beBuy    = 0.0;
   double beSell   = 0.0;

   if(m_cfg.enableAtl)
     {
      for(int b = 0; b < m_atlN; b++)
        {
         if(!m_atl[b].active)
            continue;
         if(m_atl[b].symbol != m_cfg.symbol)
            continue;
         double px = m_atl[b].bePrice;
         if(px <= 0.0)
            px = AtlBasketBePrice(m_atl[b]);
         if(px <= 0.0)
            continue;
         if(m_atl[b].type == POSITION_TYPE_BUY)
           {
            wantBuy = true;
            beBuy   = px;
           }
         else
           {
            wantSell = true;
            beSell   = px;
           }
        }
     }

   int sides = (wantBuy ? 1 : 0) + (wantSell ? 1 : 0);
   int digits = (int)SymbolInfoInteger(m_cfg.symbol, SYMBOL_DIGITS);
   if(digits < 0)
      digits = 5;

   if(wantBuy)
     {
      string cap = (sides > 1 ? "ATL BE BUY  " : "ATL BE  ")
                   + DoubleToString(beBuy, digits);
      AtlBePutLine(POSITION_TYPE_BUY, beBuy, cap);
     }
   else
      AtlBeDropLine(POSITION_TYPE_BUY);

   if(wantSell)
     {
      string cap = (sides > 1 ? "ATL BE SELL  " : "ATL BE  ")
                   + DoubleToString(beSell, digits);
      AtlBePutLine(POSITION_TYPE_SELL, beSell, cap);
     }
   else
      AtlBeDropLine(POSITION_TYPE_SELL);

   ChartRedraw(m_cfg.chartId);
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

bool CDomEngine::PolicyBlockNew(void) const
  {
   if(m_dailyFloorSticky || m_dailyLossSticky)
      return true;
   if(m_dailyHitSticky)
      return true;
   if(m_cfg.blockLosingHours && m_time.IsLosingHour(m_report.currentHour))
      return true;
   return false;
  }

bool CDomEngine::AtlBlockedAdds(void) const
  {
   if(PolicyBlockNew())
      return true;
   if(!m_cfg.dryRun && !DpTradeAllowed())
      return true;
   return false;
  }

void CDomEngine::AtlCancelPendings(const string symbol, const ENUM_POSITION_TYPE type)
  {
   for(int p = 0; p < m_pendN; p++)
     {
      if(!DpIsAtlPending(m_pend[p]))
         continue;
      if(m_pend[p].symbol != symbol)
         continue;
      if(DpPosTypeFromOrder(m_pend[p].type) != type)
         continue;
      Enqueue(m_pend[p].ticket, true, 0.0, DP_REASON_PENDING, "ATL add blocked");
     }
  }

void CDomEngine::AtlCancelAllPendings(void)
  {
   for(int p = 0; p < m_pendN; p++)
     {
      if(!DpIsAtlPending(m_pend[p]))
         continue;
      Enqueue(m_pend[p].ticket, true, 0.0, DP_REASON_PENDING, "ATL add blocked");
     }
  }

void CDomEngine::AtlSkip(const string why, const bool noisy)
  {
   m_atlNote = why;
   if(!noisy)
      return;
   uint nowMs = GetTickCount();
   if(m_atlLastSkipLogMs != 0 && (nowMs - m_atlLastSkipLogMs) < 5000)
      return;
   m_atlLastSkipLogMs = nowMs;
   DpLog(1, m_cfg.logLevel, "ATL skip: " + why);
  }

bool CDomEngine::AtlLimitDistOk(const string symbol, const bool buy, const double price) const
  {
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;
   double minDist = (double)DpStopsLevelPoints(symbol) * point;
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(buy)
      return (ask - price >= minDist);
   return (price - bid >= minDist);
  }

bool CDomEngine::AtlSendMarket(const bool buy, const double vol, const string symbol,
                               const string cmt)
  {
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
      m_trade.SetExpertMagicNumber(DP_ATL_MAGIC);
      bool ok = buy ? m_trade.Buy(vol, symbol, 0.0, 0.0, 0.0, cmt)
                    : m_trade.Sell(vol, symbol, 0.0, 0.0, 0.0, cmt);
      if(ok)
         return true;
      if(m_trade.ResultRetcode() != TRADE_RETCODE_INVALID_FILL)
         return false;
     }
   return false;
  }

bool CDomEngine::AtlSendLimit(const bool buy, const double vol, const double price,
                              const string symbol, const string cmt)
  {
   // Pendings must not inherit IOC from DpPrepareTrade — brokers reject that.
   m_trade.SetTypeFilling(ORDER_FILLING_RETURN);
   m_trade.SetExpertMagicNumber(DP_ATL_MAGIC);
   bool ok = buy ? m_trade.BuyLimit(vol, price, symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, cmt)
                 : m_trade.SellLimit(vol, price, symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, cmt);
   if(ok)
      return true;
   if(m_trade.ResultRetcode() != TRADE_RETCODE_INVALID_FILL)
      return false;
   m_trade.SetTypeFilling(DpFillingFor(symbol));
   m_trade.SetExpertMagicNumber(DP_ATL_MAGIC);
   return buy ? m_trade.BuyLimit(vol, price, symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, cmt)
              : m_trade.SellLimit(vol, price, symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, cmt);
  }

void CDomEngine::AtlPlaceNext(SAtlBasket &b)
  {
   if(b.nextMult < 2 || b.nextPrice <= 0.0)
     {
      AtlSkip(IntegerToString(b.n) + " legs  max trades", false);
      return;
     }
   if(AtlBlockedAdds())
     {
      AtlSkip("adds blocked (hour/daily/algo)", true);
      return;
     }

   uint nowMs = GetTickCount();
   if(m_atlLastPlaceMs != 0 && (nowMs - m_atlLastPlaceMs) < 1500)
      return;

   double vol = DpNormalizeVolume(b.symbol, b.addVolume);
   if(vol <= DP_VOLUME_EPS)
     {
      AtlSkip("add volume 0", true);
      return;
     }

   // Per ticket, same as the lot guard. Basket total may exceed max — that is the grid.
   if(m_cfg.enableLotGuard)
     {
      double money = DpLotRefValue(m_cfg.lotReference);
      double maxLots = DpMaxLots(b.symbol, money, m_cfg.balancePer001, m_cfg.lotUnit);
      if(vol > maxLots + DP_VOLUME_EPS)
        {
         AtlSkip("add " + DpLots(vol) + " > max " + DpLots(maxLots), true);
         return;
        }
     }

   double ask = SymbolInfoDouble(b.symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(b.symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
     {
      AtlSkip("no quote", true);
      return;
     }
   double spread = ask - bid;
   bool buy = (b.type == POSITION_TYPE_BUY);
   bool through = buy ? (ask <= b.nextPrice) : (bid >= b.nextPrice);
   if(!through && !AtlLimitDistOk(b.symbol, buy, b.nextPrice))
      through = true;

   if(through && b.step > 0.0 && spread > b.step * 0.80)
     {
      AtlSkip("spread " + DoubleToString(spread, (int)SymbolInfoInteger(b.symbol, SYMBOL_DIGITS))
              + " vs gap", true);
      return;
     }

   int digits = (int)SymbolInfoInteger(b.symbol, SYMBOL_DIGITS);
   string pxTxt = DoubleToString(b.nextPrice, digits);

   if(m_cfg.dryRun)
     {
      m_atlLastPlaceMs = nowMs;
      m_atlNote = (through ? "DRY market x" : "DRY limit x")
                  + IntegerToString(b.nextMult) + "  " + pxTxt;
      PushAction(DP_REASON_ATL_BE, m_atlNote);
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
           {
            m_atlNote = "limit x" + IntegerToString(b.nextMult) + "  " + pxTxt;
            return;
           }
         DpPrepareTrade(m_trade, b.symbol, m_cfg.slippagePoints);
         m_trade.OrderDelete(b.pendingTicket);
         b.pendingTicket = 0;
        }
     }

   DpPrepareTrade(m_trade, b.symbol, m_cfg.slippagePoints);
   string cmt = DP_ATL_COMMENT;
   bool ok = through ? AtlSendMarket(buy, vol, b.symbol, cmt)
                     : AtlSendLimit(buy, vol, b.nextPrice, b.symbol, cmt);
   m_trade.SetExpertMagicNumber(0);
   m_atlLastPlaceMs = nowMs;
   if(!ok)
     {
      string err = "place fail k=" + IntegerToString(b.nextMult)
                   + " ret=" + DpRetcodeText(m_trade.ResultRetcode());
      m_atlNote = err;
      DpLog(0, m_cfg.logLevel, "ATL " + err);
     }
   else
     {
      m_atlNote = (through ? "market x" : "limit x")
                  + IntegerToString(b.nextMult) + "  " + pxTxt;
      DpLog(1, m_cfg.logLevel, "ATL " + m_atlNote + "  " + DpLots(vol));
     }
  }

void CDomEngine::RunAddToLosers(void)
  {
   m_atlNote = "";
   if(!m_cfg.enableAtl)
     {
      AtlCancelAllPendings();
      return;
     }

   bool blockAdds = AtlBlockedAdds();
   if(blockAdds)
     {
      AtlCancelAllPendings();
      AtlSkip("adds blocked (hour/daily/algo)", true);
     }

   double target = AtlBeTarget();
   for(int b = 0; b < m_atlN; b++)
     {
      if(!m_atl[b].active)
        {
         AtlCancelPendings(m_atl[b].symbol, m_atl[b].type);
         if(!blockAdds && m_atl[b].n >= 2)
            AtlSkip("2 trades but entry gap too small", true);
         continue;
        }
      if(m_atl[b].pnl + DP_MONEY_EPS >= target)
        {
         string det = "basket " + DoubleToString(m_atl[b].pnl, 2)
                      + " >= BE+" + DoubleToString(target, 2);
         AtlEnqueueBasket(m_atl[b], det);
         m_atlNote = "BE hit — closing";
         continue;
        }
      if(!blockAdds)
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
   if(StringLen(m_atlNote) > 0)
      g.atlStatus = m_atlNote;
   else if(bsk.pnl + DP_MONEY_EPS >= g.atlBeTarget)
      g.atlStatus = "BE hit — closing";
   else if(bsk.pendingTicket > 0 && bsk.nextMult >= 2)
      g.atlStatus = "limit x" + IntegerToString(bsk.nextMult) + "  "
                    + DoubleToString(bsk.nextPrice, (int)SymbolInfoInteger(bsk.symbol, SYMBOL_DIGITS));
   else if(bsk.nextMult >= 2)
      g.atlStatus = "x" + IntegerToString(bsk.nextMult) + "  "
                    + DoubleToString(bsk.nextPrice, (int)SymbolInfoInteger(bsk.symbol, SYMBOL_DIGITS));
   else
      g.atlStatus = IntegerToString(bsk.n) + " legs  max trades";
  }

#endif
