#ifndef DOMPANION_ANALYZER_MQH
#define DOMPANION_ANALYZER_MQH

//+------------------------------------------------------------------+
//| Analyzer.mqh                                                     |
//| Copyright 2026, Dominik Fischer                                  |
//+------------------------------------------------------------------+
#include "Types.mqh"
#include "Util.mqh"

//+------------------------------------------------------------------+
//| Groups closed positions by entry hour. A position is closed when |
//| aggregated in-volume is covered by out-volume. Stats use net P/L |
//| (profit + swap + commission + fee) of every deal on that id.     |
//+------------------------------------------------------------------+
struct SHistPos
  {
   ulong             id;
   string            symbol;
   long              magic;
   datetime          tOpen;
   double            inVol;
   double            outVol;
   double            pnl;
   bool              hasIn;
  };

class CTimeAnalyzer
  {
private:
   SDpConfig         m_cfg;
   STimeReport       m_report;
   bool              m_losingManual[DP_HOUR_COUNT];
   bool              m_safeManual[DP_HOUR_COUNT];
   bool              m_specOk;
   string            m_specErr;
   datetime          m_lastBuild;

   int               FindAcc(SHistPos &acc[], const int n, const ulong id) const;
   void              ResetHour(SHourStat &h) const;
   void              Classify(void);
   void              Summarize(void);

public:
                     CTimeAnalyzer(void);
   void              Configure(const SDpConfig &cfg);
   bool              SpecOk(void) const { return m_specOk; }
   string            SpecError(void) const { return m_specErr; }
   bool              Rebuild(const bool force);
   void              CopyReport(STimeReport &out) const { out = m_report; }
   bool              IsLosingHour(const int hour) const;
   bool              IsLosingEntry(const datetime serverOpenTime) const;
  };

CTimeAnalyzer::CTimeAnalyzer(void)
  {
   m_specOk    = true;
   m_specErr   = "";
   m_lastBuild = 0;
   ZeroMemory(m_report);
   ArrayInitialize(m_losingManual, false);
   ArrayInitialize(m_safeManual, false);
  }

void CTimeAnalyzer::Configure(const SDpConfig &cfg)
  {
   m_cfg = cfg;
   m_specOk  = true;
   m_specErr = "";

   string err1 = "";
   string err2 = "";
   if(!DpParseHourSpec(cfg.manualLosingHours, m_losingManual, err1))
     {
      m_specOk  = false;
      m_specErr = err1;
      ArrayInitialize(m_losingManual, false);
     }
   if(!DpParseHourSpec(cfg.forceSafeHours, m_safeManual, err2))
     {
      m_specOk = false;
      m_specErr = (StringLen(m_specErr) > 0 ? m_specErr + "; " : "") + err2;
      ArrayInitialize(m_safeManual, false);
     }
   m_lastBuild = 0;
  }

int CTimeAnalyzer::FindAcc(SHistPos &acc[], const int n, const ulong id) const
  {
   for(int i = 0; i < n; i++)
     {
      if(acc[i].id == id)
         return i;
     }
   return -1;
  }

void CTimeAnalyzer::ResetHour(SHourStat &h) const
  {
   h.trades        = 0;
   h.wins          = 0;
   h.losses        = 0;
   h.net           = 0.0;
   h.winRate       = 0.0;
   h.sampleOk      = false;
   h.autoLosing    = false;
   h.manualLosing  = false;
   h.forceSafe     = false;
   h.losing        = false;
  }

bool CTimeAnalyzer::Rebuild(const bool force)
  {
   if(!m_cfg.enableTimeAnalysis)
     {
      if(m_report.closedTrades != 0 || m_lastBuild != 0)
        {
         for(int h = 0; h < DP_HOUR_COUNT; h++)
            ResetHour(m_report.hour[h]);
         for(int d = 0; d < DP_DOW_COUNT; d++)
            ResetHour(m_report.weekday[d]);
         m_report.closedTrades = 0;
         m_report.wins = 0;
         m_report.losses = 0;
         m_report.net = 0.0;
         m_report.winRate = 0.0;
         m_lastBuild = 0;
        }
      m_report.currentHour = DpHourOf(TimeCurrent(), m_cfg);
      m_report.currentDow  = DpDowOf(TimeCurrent(), m_cfg);
      Classify();
      Summarize();
      m_report.ready = true;
      return true;
     }

   if(IsStopped())
      return false;

   datetime now = TimeCurrent();
   if(!force && m_lastBuild > 0 && (now - m_lastBuild) < 30)
     {
      m_report.currentHour = DpHourOf(now, m_cfg);
      m_report.currentDow  = DpDowOf(now, m_cfg);
      m_report.currentHourLosing = (m_report.currentHour >= 0 && m_report.currentHour < 24
                                    && m_report.hour[m_report.currentHour].losing);
      return true;
     }

   int days = m_cfg.historyDays;
   if(days < 1)
      days = 1;
   datetime from = now - (datetime)((long)days * 86400);
   if(from < 0)
      from = 0;
   datetime pad = (datetime)(14 * 86400);
   datetime selectFrom = (from > pad ? from - pad : 0);

   ZeroMemory(m_report);
   m_report.fromTime = from;
   m_report.days     = days;
   m_report.builtAt  = now;
   m_report.currentHour = DpHourOf(now, m_cfg);
   m_report.currentDow  = DpDowOf(now, m_cfg);
   for(int h = 0; h < DP_HOUR_COUNT; h++)
      ResetHour(m_report.hour[h]);
   for(int d = 0; d < DP_DOW_COUNT; d++)
      ResetHour(m_report.weekday[d]);

   if(!HistorySelect(selectFrom, now))
     {
      DpLog(0, m_cfg.logLevel, "HistorySelect failed for time analysis.");
      Classify();
      Summarize();
      m_report.ready = true;
      m_lastBuild = now;
      return false;
     }

   SHistPos acc[];
   int nAcc = 0;
   int deals = HistoryDealsTotal();
   int lastIdx = -1;
   ulong lastPid = 0;

   for(int i = 0; i < deals; i++)
     {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      ENUM_DEAL_TYPE dtype = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dtype != DEAL_TYPE_BUY && dtype != DEAL_TYPE_SELL)
         continue;

      string sym = HistoryDealGetString(ticket, DEAL_SYMBOL);
      if(!DpManageSymbol(sym, m_cfg))
         continue;

      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(!DpManageMagic(magic, m_cfg))
         continue;

      ulong pid = (ulong)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      if(pid == 0)
         continue;

      int idx = (lastPid == pid && lastIdx >= 0) ? lastIdx : FindAcc(acc, nAcc, pid);
      if(idx < 0)
        {
         idx = nAcc;
         nAcc++;
         if(ArrayResize(acc, nAcc, 64) < nAcc)
            break;
         acc[idx].id     = pid;
         acc[idx].symbol = sym;
         acc[idx].magic  = magic;
         acc[idx].tOpen  = 0;
         acc[idx].inVol  = 0.0;
         acc[idx].outVol = 0.0;
         acc[idx].pnl    = 0.0;
         acc[idx].hasIn  = false;
        }
      lastPid = pid;
      lastIdx = idx;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      datetime t = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      double vol = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      acc[idx].pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                      + HistoryDealGetDouble(ticket, DEAL_SWAP)
                      + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                      + HistoryDealGetDouble(ticket, DEAL_FEE);

      if(entry == DEAL_ENTRY_IN)
        {
         acc[idx].inVol += vol;
         acc[idx].hasIn  = true;
         if(acc[idx].tOpen == 0 || t < acc[idx].tOpen)
            acc[idx].tOpen = t;
        }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
        {
         acc[idx].outVol += vol;
        }
      else if(entry == DEAL_ENTRY_INOUT)
        {
         // Reversal: the in-side is a new position at this deal time.
         acc[idx].outVol += vol;
         if(acc[idx].tOpen == 0)
            acc[idx].tOpen = t;
         acc[idx].hasIn = true;
        }
     }

   for(int i = 0; i < nAcc; i++)
     {
      if(!acc[i].hasIn || acc[i].tOpen <= 0)
         continue;
      if(acc[i].tOpen < from)
         continue;
      if(acc[i].inVol - acc[i].outVol > DP_VOLUME_EPS)
         continue;

      int hour = DpHourOf(acc[i].tOpen, m_cfg);
      if(hour < 0 || hour > 23)
         continue;

      SHourStat hstat = m_report.hour[hour];
      hstat.trades++;
      hstat.net += acc[i].pnl;
      if(acc[i].pnl > DP_MONEY_EPS)
         hstat.wins++;
      else
         hstat.losses++;
      m_report.hour[hour] = hstat;

      int dow = DpDowOf(acc[i].tOpen, m_cfg);
      if(dow >= 0 && dow < DP_DOW_COUNT)
        {
         SHourStat dstat = m_report.weekday[dow];
         dstat.trades++;
         dstat.net += acc[i].pnl;
         if(acc[i].pnl > DP_MONEY_EPS)
            dstat.wins++;
         else
            dstat.losses++;
         m_report.weekday[dow] = dstat;
        }

      m_report.closedTrades++;
      m_report.net += acc[i].pnl;
      if(acc[i].pnl > DP_MONEY_EPS)
         m_report.wins++;
      else
         m_report.losses++;
     }

   int dayMin = MathMax(3, m_cfg.minTradesPerHour);
   for(int h = 0; h < DP_HOUR_COUNT; h++)
     {
      SHourStat hs = m_report.hour[h];
      if(hs.trades > 0)
         hs.winRate = 100.0 * (double)hs.wins / (double)hs.trades;
      hs.sampleOk = (hs.trades >= m_cfg.minTradesPerHour);
      m_report.hour[h] = hs;
     }
   for(int d = 0; d < DP_DOW_COUNT; d++)
     {
      SHourStat ds = m_report.weekday[d];
      if(ds.trades > 0)
         ds.winRate = 100.0 * (double)ds.wins / (double)ds.trades;
      ds.sampleOk = (ds.trades >= dayMin);
      m_report.weekday[d] = ds;
     }

   if(m_report.closedTrades > 0)
      m_report.winRate = 100.0 * (double)m_report.wins / (double)m_report.closedTrades;

   Classify();
   Summarize();
   m_report.ready = true;
   m_lastBuild = now;
   return true;
  }

void CTimeAnalyzer::Classify(void)
  {
   for(int h = 0; h < DP_HOUR_COUNT; h++)
     {
      SHourStat hs = m_report.hour[h];
      hs.manualLosing = m_losingManual[h];
      hs.forceSafe    = m_safeManual[h];
      hs.autoLosing   = false;

      if(m_cfg.enableTimeAnalysis && hs.sampleOk)
        {
         bool wrBad = (hs.winRate < m_cfg.losingWinRatePct);
         bool netBad = (m_cfg.loseOnNegativeNet && hs.net < -DP_MONEY_EPS);
         hs.autoLosing = (wrBad || netBad);
        }

      // Manual losing adds; force-safe always wins; auto otherwise.
      hs.losing = hs.manualLosing || hs.autoLosing;
      if(hs.forceSafe)
         hs.losing = false;

      m_report.hour[h] = hs;
     }

   for(int d = 0; d < DP_DOW_COUNT; d++)
     {
      SHourStat ds = m_report.weekday[d];
      ds.autoLosing = false;
      ds.losing     = false;
      if(m_cfg.enableTimeAnalysis && ds.sampleOk)
        {
         bool wrBad = (ds.winRate < m_cfg.losingWinRatePct);
         bool netBad = (m_cfg.loseOnNegativeNet && ds.net < -DP_MONEY_EPS);
         ds.autoLosing = (wrBad || netBad);
         ds.losing     = ds.autoLosing;
        }
      m_report.weekday[d] = ds;
     }
  }

void CTimeAnalyzer::Summarize(void)
  {
   m_report.bestHour  = -1;
   m_report.worstHour = -1;
   double bestScore  = -1.0e100;
   double worstScore =  1.0e100;

   bool lose[DP_HOUR_COUNT];
   ArrayInitialize(lose, false);

   for(int h = 0; h < DP_HOUR_COUNT; h++)
     {
      lose[h] = m_report.hour[h].losing;
      if(m_report.hour[h].trades <= 0)
         continue;
      // Rank by net, then by win rate, requiring at least one trade.
      double score = m_report.hour[h].net;
      if(score > bestScore)
        {
         bestScore = score;
         m_report.bestHour = h;
        }
      if(score < worstScore)
        {
         worstScore = score;
         m_report.worstHour = h;
        }
     }

   m_report.losingList = DpHourMaskList(lose);
   m_report.currentHourLosing = (m_report.currentHour >= 0 && m_report.currentHour < 24
                                 && m_report.hour[m_report.currentHour].losing);

   if(m_report.bestHour >= 0)
     {
      SHourStat b = m_report.hour[m_report.bestHour];
      m_report.bestText = DpHourLabel(m_report.bestHour) + ":00  "
                          + DoubleToString(b.winRate, 0) + "%  "
                          + DoubleToString(b.net, 2) + "  n="
                          + IntegerToString(b.trades);
     }
   else
      m_report.bestText = "n/a";

   if(m_report.worstHour >= 0)
     {
      SHourStat w = m_report.hour[m_report.worstHour];
      m_report.worstText = DpHourLabel(m_report.worstHour) + ":00  "
                           + DoubleToString(w.winRate, 0) + "%  "
                           + DoubleToString(w.net, 2) + "  n="
                           + IntegerToString(w.trades);
     }
   else
      m_report.worstText = "n/a";

   m_report.bestDay  = -1;
   m_report.worstDay = -1;
   bestScore  = -1.0e100;
   worstScore =  1.0e100;
   for(int d = 0; d < DP_DOW_COUNT; d++)
     {
      if(m_report.weekday[d].trades <= 0)
         continue;
      double score = m_report.weekday[d].net;
      if(score > bestScore)
        {
         bestScore = score;
         m_report.bestDay = d;
        }
      if(score < worstScore)
        {
         worstScore = score;
         m_report.worstDay = d;
        }
     }

   if(m_report.bestDay >= 0)
     {
      SHourStat b = m_report.weekday[m_report.bestDay];
      m_report.bestDayText = DpDowName(m_report.bestDay) + "  "
                             + DoubleToString(b.winRate, 0) + "%  "
                             + DoubleToString(b.net, 2);
     }
   else
      m_report.bestDayText = "n/a";

   if(m_report.worstDay >= 0)
     {
      SHourStat w = m_report.weekday[m_report.worstDay];
      m_report.worstDayText = DpDowName(m_report.worstDay) + "  "
                              + DoubleToString(w.winRate, 0) + "%  "
                              + DoubleToString(w.net, 2);
     }
   else
      m_report.worstDayText = "n/a";

   if(m_report.bestDay >= 0 || m_report.bestHour >= 0)
     {
      m_report.playText = "Play ";
      if(m_report.bestDay >= 0)
         m_report.playText += " " + DpDowName(m_report.bestDay) + " "
                              + DoubleToString(m_report.weekday[m_report.bestDay].net, 0);
      if(m_report.bestHour >= 0)
         m_report.playText += "   " + DpHourLabel(m_report.bestHour) + ":00 "
                              + DoubleToString(m_report.hour[m_report.bestHour].net, 0);
     }
   else
      m_report.playText = "Play  n/a";

   if(m_report.worstDay >= 0 || m_report.worstHour >= 0)
     {
      m_report.skipText = "Skip ";
      if(m_report.worstDay >= 0)
         m_report.skipText += " " + DpDowName(m_report.worstDay) + " "
                              + DoubleToString(m_report.weekday[m_report.worstDay].net, 0);
      if(m_report.worstHour >= 0)
         m_report.skipText += "   " + DpHourLabel(m_report.worstHour) + ":00 "
                              + DoubleToString(m_report.hour[m_report.worstHour].net, 0);
     }
   else
      m_report.skipText = "Skip  n/a";
  }

bool CTimeAnalyzer::IsLosingHour(const int hour) const
  {
   if(hour < 0 || hour > 23)
      return false;
   return m_report.hour[hour].losing;
  }

bool CTimeAnalyzer::IsLosingEntry(const datetime serverOpenTime) const
  {
   return IsLosingHour(DpHourOf(serverOpenTime, m_cfg));
  }

#endif // DOMPANION_ANALYZER_MQH
