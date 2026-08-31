#ifndef DOMPANION_DASHBOARD_MQH
#define DOMPANION_DASHBOARD_MQH

//+------------------------------------------------------------------+
//| Dashboard.mqh                                                    |
//| Copyright 2026, Dominik Fischer                                  |
//+------------------------------------------------------------------+
#include "Types.mqh"
#include "Util.mqh"
#include <Canvas/Canvas.mqh>

#ifndef FW_NORMAL
#define FW_NORMAL 400
#endif
#ifndef FW_BOLD
#define FW_BOLD 700
#endif

//+------------------------------------------------------------------+
//| Four-corner canvas panel. Coordinates are always computed from   |
//| the top-left of the chart so resize/corner changes cannot drift. |
//+------------------------------------------------------------------+
struct SDpTheme
  {
   color             bg;
   color             bgInner;
   color             border;
   color             text;
   color             muted;
   color             accent;
   color             green;
   color             red;
   color             amber;
   color             cellEmpty;
   uchar             bgAlpha;
  };

class CDashboard
  {
private:
   CCanvas           m_canvas;
   bool              m_ready;
   string            m_name;
   long              m_chartId;
   SDpConfig         m_cfg;
   SDpTheme          m_theme;

   int               m_x;
   int               m_y;
   int               m_w;
   int               m_h;
   int               m_pad;
   int               m_row;
   int               m_fs;
   int               m_fsSm;
   int               m_fsTitle;
   int               m_radius;
   int               m_curY;
   int               m_scalePct;          // 100 = 1.0

   void              LoadTheme(void);
   int               Px(const int logical) const;
   int               FontPx(const int px) const;
   uint              ARGB(const color clr, const uchar alpha = 255) const;
   void              Font(const int px, const bool bold);
   int               TextW(const string s);
   int               TextH(void);
   void              FillRound(const int x, const int y, const int w, const int h,
                               const int r, const uint fill);
   void              StrokeRound(const int x, const int y, const int w, const int h,
                                 const int r, const uint stroke);
   void              Text(const int x, const int y, const string s, const uint clr,
                          const uint align = 0);
   void              Pill(const int x, const int y, const int w, const int h,
                          const string s, const color bg, const color fg);
   void              HLine(const int x1, const int x2, const int y, const uint clr);
   void              DrawHeader(const SViewModel &vm, const int x0, const int x1);
   void              DrawAccount(const SViewModel &vm, const int x0, const int x1);
   void              DrawPositions(const SViewModel &vm, const int x0, const int x1);
   void              DrawPosBar(const SPosView &p, const int x, const int y,
                                const int w, const int h);
   void              DrawGuards(const SViewModel &vm, const int x0, const int x1);
   void              DrawClock(const SViewModel &vm, const int x0, const int x1);
   void              DrawActions(const SViewModel &vm, const int x0, const int x1);
   bool              Room(const int need) const;
   void              SectionTitle(const string s, const int x0);
   color             HeatColor(const SHourStat &hs) const;
   bool              EnsureCanvas(const int w, const int h, const int x, const int y);
   void              MoveCanvas(const int x, const int y);
   void              Place(const int w, const int h, int &x, int &y) const;
   int               ChartW(void) const;
   int               ChartH(void) const;

public:
                     CDashboard(void);
                    ~CDashboard(void);
   bool              Init(const SDpConfig &cfg);
   void              Deinit(void);
   void              Configure(const SDpConfig &cfg);
   void              Render(const SViewModel &vm);
  };

CDashboard::CDashboard(void)
  {
   m_ready    = false;
   m_name     = "";
   m_chartId  = 0;
   m_x = m_y  = 0;
   m_w = m_h  = 0;
   m_pad      = 12;
   m_row      = 16;
   m_fs       = 12;
   m_fsSm     = 10;
   m_fsTitle  = 15;
   m_radius   = 10;
   m_curY     = 0;
   m_scalePct = 100;
  }

CDashboard::~CDashboard(void)
  {
   Deinit();
  }

void CDashboard::LoadTheme(void)
  {
   if(m_cfg.theme == DP_THEME_LIGHT)
     {
      m_theme.bg        = C'244,246,248';
      m_theme.bgInner   = C'232,236,241';
      m_theme.border    = C'196,205,216';
      m_theme.text      = C'22,27,34';
      m_theme.muted     = C'110,119,129';
      m_theme.accent    = C'14,140,140';
      m_theme.green     = C'26,127,55';
      m_theme.red       = C'207,34,46';
      m_theme.amber     = C'154,103,0';
      m_theme.cellEmpty = C'220,225,230';
      m_theme.bgAlpha   = 235;
     }
   else
     {
      m_theme.bg        = C'16,20,26';
      m_theme.bgInner   = C'28,34,44';
      m_theme.border    = C'48,58,72';
      m_theme.text      = C'232,236,241';
      m_theme.muted     = C'139,149,165';
      m_theme.accent    = C'56,189,187';
      m_theme.green     = C'46,204,113';
      m_theme.red       = C'231,76,60';
      m_theme.amber     = C'243,156,18';
      m_theme.cellEmpty = C'36,44,56';
      m_theme.bgAlpha   = 230;
     }
  }

int CDashboard::Px(const int logical) const
  {
   return (int)MathRound((double)logical * (double)m_scalePct / 100.0);
  }

int CDashboard::FontPx(const int px) const
  {
   // CCanvas: negative tenths of a pixel → actual pixel size.
   return -10 * MathMax(9, px);
  }

uint CDashboard::ARGB(const color clr, const uchar alpha) const
  {
   return ColorToARGB(clr, alpha);
  }

void CDashboard::Font(const int px, const bool bold)
  {
   uint flags = (bold ? FW_BOLD : FW_NORMAL);
   m_canvas.FontSet("Arial", FontPx(px), flags);
  }

int CDashboard::TextW(const string s)
  {
   return m_canvas.TextWidth(s);
  }

int CDashboard::TextH(void)
  {
   return m_canvas.TextHeight("Ag");
  }

void CDashboard::FillRound(const int x, const int y, const int w, const int h,
                           const int r, const uint fill)
  {
   int rr = r;
   if(rr * 2 > w)
      rr = w / 2;
   if(rr * 2 > h)
      rr = h / 2;
   if(rr < 1)
     {
      m_canvas.FillRectangle(x, y, x + w - 1, y + h - 1, fill);
      return;
     }
   m_canvas.FillRectangle(x + rr, y, x + w - 1 - rr, y + h - 1, fill);
   m_canvas.FillRectangle(x, y + rr, x + w - 1, y + h - 1 - rr, fill);
   m_canvas.FillCircle(x + rr, y + rr, rr, fill);
   m_canvas.FillCircle(x + w - 1 - rr, y + rr, rr, fill);
   m_canvas.FillCircle(x + rr, y + h - 1 - rr, rr, fill);
   m_canvas.FillCircle(x + w - 1 - rr, y + h - 1 - rr, rr, fill);
  }

void CDashboard::StrokeRound(const int x, const int y, const int w, const int h,
                             const int r, const uint stroke)
  {
   int rr = r;
   if(rr * 2 > w)
      rr = w / 2;
   if(rr * 2 > h)
      rr = h / 2;
   int x2 = x + w - 1;
   int y2 = y + h - 1;
   m_canvas.Line(x + rr, y, x2 - rr, y, stroke);
   m_canvas.Line(x + rr, y2, x2 - rr, y2, stroke);
   m_canvas.Line(x, y + rr, x, y2 - rr, stroke);
   m_canvas.Line(x2, y + rr, x2, y2 - rr, stroke);
   m_canvas.Circle(x + rr, y + rr, rr, stroke);
   m_canvas.Circle(x2 - rr, y + rr, rr, stroke);
   m_canvas.Circle(x + rr, y2 - rr, rr, stroke);
   m_canvas.Circle(x2 - rr, y2 - rr, rr, stroke);
  }

void CDashboard::Text(const int x, const int y, const string s, const uint clr,
                      const uint align)
  {
   m_canvas.TextOut(x, y, s, clr, align);
  }

void CDashboard::Pill(const int x, const int y, const int w, const int h,
                      const string s, const color bg, const color fg)
  {
   FillRound(x, y, w, h, h / 2, ARGB(bg, 255));
   Font(m_fsSm, true);
   int tw = TextW(s);
   int th = TextH();
   Text(x + (w - tw) / 2, y + (h - th) / 2, s, ARGB(fg));
  }

void CDashboard::HLine(const int x1, const int x2, const int y, const uint clr)
  {
   m_canvas.Line(x1, y, x2, y, clr);
  }

bool CDashboard::Room(const int need) const
  {
   return (m_curY + need <= m_h - m_pad);
  }

void CDashboard::SectionTitle(const string s, const int x0)
  {
   Font(m_fsSm, true);
   Text(x0, m_curY, s, ARGB(m_theme.muted));
   m_curY += m_row;
  }

int CDashboard::ChartW(void) const
  {
   int w = (int)ChartGetInteger(m_chartId, CHART_WIDTH_IN_PIXELS);
   return (w > 0 ? w : 800);
  }

int CDashboard::ChartH(void) const
  {
   int h = (int)ChartGetInteger(m_chartId, CHART_HEIGHT_IN_PIXELS);
   return (h > 0 ? h : 600);
  }

void CDashboard::Place(const int w, const int h, int &x, int &y) const
  {
   int cw = ChartW();
   int ch = ChartH();
   int ox = Px(m_cfg.offsetX);
   int oy = Px(m_cfg.offsetY);
   int rightPad = Px(m_cfg.rightClearance);
   int botPad   = Px(m_cfg.bottomClearance);

   switch(m_cfg.corner)
     {
      case DP_CORNER_RIGHT_TOP:
         x = cw - w - ox - rightPad;
         y = oy;
         break;
      case DP_CORNER_LEFT_BOTTOM:
         x = ox;
         y = ch - h - oy - botPad;
         break;
      case DP_CORNER_RIGHT_BOTTOM:
         x = cw - w - ox - rightPad;
         y = ch - h - oy - botPad;
         break;
      default:
         x = ox;
         y = oy;
         break;
     }

   int maxX = MathMax(0, cw - w);
   int maxY = MathMax(0, ch - h);
   if(x < 0) x = 0;
   if(y < 0) y = 0;
   if(x > maxX) x = maxX;
   if(y > maxY) y = maxY;
  }

bool CDashboard::EnsureCanvas(const int w, const int h, const int x, const int y)
  {
   if(w < 40 || h < 40)
      return false;

   if(m_ready && m_w == w && m_h == h)
     {
      if(m_x != x || m_y != y)
         MoveCanvas(x, y);
      return true;
     }

   if(m_ready)
     {
      m_canvas.Destroy();
      m_ready = false;
     }
   ObjectDelete(m_chartId, m_name);

   if(!m_canvas.CreateBitmapLabel(m_chartId, 0, m_name, x, y, w, h,
                                  COLOR_FORMAT_ARGB_NORMALIZE))
     {
      Print(DP_LOG_PREFIX, "canvas create failed err=", IntegerToString(GetLastError()));
      return false;
     }

   ObjectSetInteger(m_chartId, m_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(m_chartId, m_name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
   ObjectSetInteger(m_chartId, m_name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(m_chartId, m_name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(m_chartId, m_name, OBJPROP_BACK, false);
   ObjectSetInteger(m_chartId, m_name, OBJPROP_ZORDER, 1000);
   ObjectSetString(m_chartId, m_name, OBJPROP_TOOLTIP, "DomPanion");

   m_ready = true;
   m_w = w;
   m_h = h;
   m_x = x;
   m_y = y;
   return true;
  }

void CDashboard::MoveCanvas(const int x, const int y)
  {
   ObjectSetInteger(m_chartId, m_name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(m_chartId, m_name, OBJPROP_YDISTANCE, y);
   m_x = x;
   m_y = y;
  }

bool CDashboard::Init(const SDpConfig &cfg)
  {
   Deinit();
   m_cfg     = cfg;
   m_chartId = cfg.chartId;
   m_name    = DP_OBJ_CANVAS + "." + IntegerToString(m_chartId);
   LoadTheme();
   return true;
  }

void CDashboard::Configure(const SDpConfig &cfg)
  {
   m_cfg = cfg;
   LoadTheme();
  }

void CDashboard::Deinit(void)
  {
   if(m_ready)
     {
      m_canvas.Destroy();
      m_ready = false;
     }
   if(m_chartId > 0 && StringLen(m_name) > 0)
      ObjectDelete(m_chartId, m_name);
   m_w = m_h = 0;
  }

color CDashboard::HeatColor(const SHourStat &hs) const
  {
   if(hs.losing)
      return m_theme.red;
   if(hs.trades <= 0)
      return m_theme.cellEmpty;
   if(!hs.sampleOk)
     {
      if(hs.net > DP_MONEY_EPS)
         return C'40,90,70';
      if(hs.net < -DP_MONEY_EPS)
         return C'90,45,45';
      return m_theme.cellEmpty;
     }
   if(hs.winRate >= 60.0)
      return m_theme.green;
   if(hs.winRate >= m_cfg.losingWinRatePct)
      return m_theme.accent;
   return m_theme.amber;
  }

void CDashboard::DrawHeader(const SViewModel &vm, const int x0, const int x1)
  {
   Font(m_fsTitle, true);
   Text(x0, m_curY, "DomPanion", ARGB(m_theme.accent));

   string pill = "ARMED";
   color  pbg  = m_theme.green;
   color  pfg  = C'12,18,16';
   if(vm.guards.ownerConflict)
     {
      pill = "STANDBY";
      pbg  = m_theme.red;
      pfg  = C'255,255,255';
     }
   else if(!vm.guards.tradeAllowed)
     {
      pill = "NO ALGO";
      pbg  = m_theme.red;
      pfg  = C'255,255,255';
     }
   else if(vm.guards.dryRun)
     {
      pill = "DRY RUN";
      pbg  = m_theme.amber;
      pfg  = C'20,16,8';
     }
   else if(!vm.guards.armed)
     {
      pill = "IDLE";
      pbg  = m_theme.bgInner;
      pfg  = m_theme.muted;
     }

   int pw = Px(78);
   int ph = Px(18);
   Pill(x1 - pw, m_curY, pw, ph, pill, pbg, pfg);
   m_curY += Px(22);
  }

void CDashboard::DrawAccount(const SViewModel &vm, const int x0, const int x1)
  {
   Font(m_fs, false);
   string mode = DpIsHedging() ? "hedge" : "netting";
   string line = vm.symbol + "  " + mode + "  " + DpMoney(vm.balance, vm.currency);
   Text(x0, m_curY, line, ARGB(m_theme.text));
   m_curY += m_row;

   Font(m_fsSm, false);
   string eq = "eq " + DoubleToString(vm.equity, 2)
               + "   day " + DoubleToString(vm.guards.dailyPnl, 2);
   Text(x0, m_curY, eq, ARGB(m_theme.muted));
   m_curY += m_row;

   if(StringLen(vm.headline) > 0)
     {
      color hc = m_theme.muted;
      if(StringFind(vm.headline, "KILL") >= 0 || StringFind(vm.headline, "blocked") >= 0)
         hc = m_theme.red;
      else if(StringFind(vm.headline, "SAFE") >= 0 || StringFind(vm.headline, "TARGET") >= 0)
         hc = m_theme.green;
      else if(StringFind(vm.headline, "AMBER") >= 0)
         hc = m_theme.amber;
      Font(m_fsSm, true);
      Text(x0, m_curY, vm.headline, ARGB(hc));
      m_curY += m_row;
     }
  }

void CDashboard::DrawPosBar(const SPosView &p, const int x, const int y,
                            const int w, const int h)
  {
   double lo = -MathMax(p.hardSlMoney, DP_MONEY_EPS);
   double hi = MathMax(p.tpMoney, DP_MONEY_EPS);
   double span = hi - lo;
   if(span <= 0.0)
      span = 1.0;

   FillRound(x, y, w, h, h / 2, ARGB(m_theme.bgInner));

   int xZero = x + (int)MathRound((0.0 - lo) / span * (double)(w - 1));
   int xSoft = x + (int)MathRound((-p.softSlMoney - lo) / span * (double)(w - 1));
   int xNow  = x + (int)MathRound((p.profitNet - lo) / span * (double)(w - 1));
   xZero = DpClampInt(xZero, x, x + w - 1);
   xSoft = DpClampInt(xSoft, x, x + w - 1);
   xNow  = DpClampInt(xNow, x, x + w - 1);

   // Amber band: hard (left) to soft.
   int xAmberL = x;
   int xAmberR = xSoft;
   if(xAmberR > xAmberL)
      m_canvas.FillRectangle(xAmberL, y + 1, xAmberR, y + h - 2, ARGB(m_theme.red, 55));

   color mk = m_theme.accent;
   if(p.zone == DP_ZONE_TARGET)
      mk = m_theme.green;
   else if(p.zone == DP_ZONE_KILL || p.zone == DP_ZONE_AMBER)
      mk = m_theme.red;
   else if(p.zone == DP_ZONE_LOCKED)
      mk = m_theme.amber;

   m_canvas.Line(xZero, y, xZero, y + h - 1, ARGB(m_theme.muted, 160));
   m_canvas.FillRectangle(xNow - 1, y, xNow + 1, y + h - 1, ARGB(mk));
  }

void CDashboard::DrawPositions(const SViewModel &vm, const int x0, const int x1)
  {
   if(!Room(m_row * 2))
      return;
   SectionTitle("POSITION", x0);

   if(vm.posCount <= 0)
     {
      Font(m_fs, false);
      Text(x0, m_curY, "None — guards watching", ARGB(m_theme.muted));
      m_curY += m_row + Px(4);
      return;
     }

   int innerW = x1 - x0;
   int shown = vm.posCount;
   for(int i = 0; i < shown; i++)
     {
      if(!Room(Px(54)))
         break;
      SPosView p = vm.positions[i];
      FillRound(x0 - Px(2), m_curY - Px(2), innerW + Px(4), Px(52), Px(6), ARGB(m_theme.bgInner, 180));

      Font(m_fs, true);
      string head = "#" + IntegerToString((long)p.ticket) + "  " + p.side + "  " + DpLots(p.volume);
      Text(x0, m_curY, head, ARGB(m_theme.text));

      color pc = (p.profitNet >= 0.0 ? m_theme.green : m_theme.red);
      string pnl = DoubleToString(p.profitNet, 2);
      Font(m_fs, true);
      int pw = TextW(pnl);
      Text(x1 - pw, m_curY, pnl, ARGB(pc));
      m_curY += m_row;

      Font(m_fsSm, false);
      string meta = "TP " + DoubleToString(p.tpMoney, 2)
                    + "   soft " + DoubleToString(p.softSlMoney, 2)
                    + "   hard " + DoubleToString(p.hardSlMoney, 2);
      Text(x0, m_curY, meta, ARGB(m_theme.muted));

      color zc = m_theme.muted;
      if(p.zone == DP_ZONE_TARGET) zc = m_theme.green;
      if(p.zone == DP_ZONE_AMBER || p.zone == DP_ZONE_KILL) zc = m_theme.red;
      if(p.zone == DP_ZONE_LOCKED) zc = m_theme.amber;
      string zs = p.zoneName;
      int zw = TextW(zs);
      Font(m_fsSm, true);
      Text(x1 - zw, m_curY, zs, ARGB(zc));
      m_curY += m_row - Px(2);

      DrawPosBar(p, x0, m_curY, innerW, Px(8));
      m_curY += Px(14);
     }
   m_curY += Px(4);
  }

void CDashboard::DrawGuards(const SViewModel &vm, const int x0, const int x1)
  {
   if(!Room(m_row * 7))
      return;
   SectionTitle("GUARDS", x0);
   Font(m_fsSm, false);

   SGuardView g = vm.guards;
   int colOn = x0;
   int colVal = x0 + Px(92);

   string k1 = "Time";
   string v1 = (g.timeOn ? "ON  " : "off  ") + g.timeNowLabel;
   if(g.timeOn && g.timeBlocking)
      v1 += "  block";
   color c1 = (!g.timeOn ? m_theme.muted : (g.timeNowLosing ? m_theme.red : m_theme.green));

   string k2 = "Lot";
   string v2 = (g.lotOn ? "ON  max " + DpLots(g.maxLots)
                          + "  (" + DoubleToString(g.balancePer001, 0) + "/0.01)"
                        : "off");
   color c2 = (g.lotOn ? m_theme.green : m_theme.muted);

   string k3 = "Money";
   string v3 = (g.moneyOn ? "ON  TP " + DoubleToString(g.tpPer001, 2)
                            + " / 0.01   hard " + DoubleToString(g.hardMult, 1) + "x"
                          : "off");
   color c3 = (g.moneyOn ? m_theme.green : m_theme.muted);

   string k4 = "Scale";
   string v4 = (g.oneTradeOn ? "ON  keep 1  (open " + IntegerToString(g.openCount) + ")"
                             : "off");
   color c4 = (g.oneTradeOn ? m_theme.green : m_theme.muted);

   string k5 = "Daily";
   string v5;
   color  c5;
   if(!g.dailyOn)
     {
      v5 = "off  today " + DoubleToString(g.dailyPnl, 2);
      c5 = m_theme.muted;
     }
   else
     {
      v5 = "ON  " + DoubleToString(g.dailyPnl, 2) + " / " + DoubleToString(g.dailyTarget, 2);
      if(g.dailyHit || g.dailyLossHit)
        {
         v5 += g.dailyLossHit ? "  LOSS CAP" : "  GOAL HIT";
         c5 = m_theme.amber;
        }
      else
         c5 = m_theme.green;
     }

   string k6 = "Floor";
   string v6;
   color  c6;
   if(!g.dailyFloorOn)
     {
      v6 = "off";
      c6 = m_theme.muted;
     }
   else
     {
      v6 = "ON  eq vs " + DoubleToString(g.dailyFloorLevel, 2)
           + "  (start " + DoubleToString(g.dailyStartBalance, 0) + ")";
      if(g.dailyFloorHit)
        {
         v6 += "  LOCKED";
         c6 = m_theme.red;
        }
      else
         c6 = m_theme.green;
     }

   string keys[6];
   string vals[6];
   color  cols[6];
   keys[0] = k1; vals[0] = v1; cols[0] = c1;
   keys[1] = k2; vals[1] = v2; cols[1] = c2;
   keys[2] = k3; vals[2] = v3; cols[2] = c3;
   keys[3] = k4; vals[3] = v4; cols[3] = c4;
   keys[4] = k5; vals[4] = v5; cols[4] = c5;
   keys[5] = k6; vals[5] = v6; cols[5] = c6;

   for(int i = 0; i < 6; i++)
     {
      if(!Room(m_row))
         break;
      Font(m_fsSm, true);
      Text(colOn, m_curY, keys[i], ARGB(m_theme.muted));
      Font(m_fsSm, false);
      Text(colVal, m_curY, vals[i], ARGB(cols[i]));
      m_curY += m_row - Px(1);
     }
   m_curY += Px(6);
  }

void CDashboard::DrawClock(const SViewModel &vm, const int x0, const int x1)
  {
   int cols = 6;
   int rows = 4;
   int gap  = Px(3);
   int inner = x1 - x0;
   int cw = (inner - gap * (cols - 1)) / cols;
   int ch = Px(22);
   int need = m_row + rows * (ch + gap) + m_row * 3;
   if(!Room(need))
      return;

   string clockTitle = "CLOCK  entry-hour   "
                       + IntegerToString(vm.time.days) + "d   n="
                       + IntegerToString(vm.time.closedTrades);
   SectionTitle(clockTitle, x0);

   int hour = 0;
   for(int r = 0; r < rows; r++)
     {
      int x = x0;
      for(int c = 0; c < cols; c++)
        {
         SHourStat hs = vm.time.hour[hour];
         color cell = HeatColor(hs);
         FillRound(x, m_curY, cw, ch, Px(3), ARGB(cell, (hs.trades > 0 ? 200 : 120)));

         if(hour == vm.time.currentHour)
            StrokeRound(x, m_curY, cw, ch, Px(3), ARGB(m_theme.amber, 255));
         else if(hs.losing)
            StrokeRound(x, m_curY, cw, ch, Px(3), ARGB(m_theme.red, 180));

         Font(m_fsSm, true);
         string lab = DpHourLabel(hour);
         color fg = (hs.losing || (hs.sampleOk && hs.winRate >= 60.0)
                     ? C'255,255,255' : m_theme.text);
         if(m_cfg.theme == DP_THEME_LIGHT && !hs.losing && hs.winRate < 60.0)
            fg = m_theme.text;
         int tw = TextW(lab);
         Text(x + (cw - tw) / 2, m_curY + Px(4), lab, ARGB(fg));

         x += cw + gap;
         hour++;
        }
      m_curY += ch + gap;
     }

   Font(m_fsSm, false);
   if(Room(m_row))
     {
      Text(x0, m_curY, "Best   " + vm.time.bestText, ARGB(m_theme.green));
      m_curY += m_row - Px(1);
     }
   if(Room(m_row))
     {
      Text(x0, m_curY, "Worst  " + vm.time.worstText, ARGB(m_theme.red));
      m_curY += m_row - Px(1);
     }
   if(Room(m_row))
     {
      Text(x0, m_curY, "Losing " + vm.time.losingList, ARGB(m_theme.muted));
      m_curY += m_row;
     }
   m_curY += Px(4);
  }

void CDashboard::DrawActions(const SViewModel &vm, const int x0, const int x1)
  {
   if(vm.actionCount <= 0)
      return;
   if(!Room(m_row * 2))
      return;
   SectionTitle("LAST ACTION", x0);
   Font(m_fsSm, false);
   int n = MathMin(vm.actionCount, 3);
   for(int i = 0; i < n; i++)
     {
      if(!Room(m_row))
         break;
      SAction a = vm.actions[i];
      string ts = TimeToString(a.t, TIME_MINUTES);
      Text(x0, m_curY, ts + "  " + a.text, ARGB(m_theme.muted));
      m_curY += m_row - Px(1);
     }
  }

void CDashboard::Render(const SViewModel &vm)
  {
   if(!DpWantUi(m_cfg.showDashboard))
     {
      if(m_ready)
         Deinit();
      return;
     }

   int dpi = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   if(dpi <= 0)
      dpi = 96;
   double dpiMul = (double)dpi / 96.0;
   double userMul = (m_cfg.panelScale > 0.2 ? m_cfg.panelScale : 1.0);

   int ch = ChartH();
   double sizeMul = 1.0;
   if(ch < 420)
      sizeMul = 0.78;
   else if(ch < 620)
      sizeMul = 0.88;
   else if(ch < 800)
      sizeMul = 0.94;

   m_scalePct = (int)MathRound(100.0 * dpiMul * userMul * sizeMul);
   if(m_scalePct < 70)
      m_scalePct = 70;
   if(m_scalePct > 180)
      m_scalePct = 180;

   m_pad     = Px(12);
   m_row     = Px(16);
   m_fs      = MathMax(10, (int)MathRound(m_cfg.fontSize * (double)m_scalePct / 100.0));
   m_fsSm    = MathMax(9, m_fs - 2);
   m_fsTitle = m_fs + 3;
   m_radius  = Px(10);

   int cw = ChartW();
   int wantW = Px(m_cfg.panelWidth);
   int maxW = MathMax(Px(200), cw - Px(m_cfg.offsetX) * 2 - Px(m_cfg.rightClearance));
   int w = MathMin(wantW, maxW);
   if(w > cw)
      w = cw;
   if(w < Px(200))
      w = MathMin(Px(200), cw);

   int posBlock = (vm.posCount <= 0 ? m_row * 2 + Px(8) : vm.posCount * Px(56) + Px(8));
   int bodyH = m_pad * 2
               + Px(28)             // header
               + m_row * 3          // account
               + Px(24)             // separators
               + m_row              // POSITION title
               + posBlock
               + m_row * 8          // guards
               + (vm.actionCount > 0 ? m_row * 4 : 0)
               + Px(12);
   int clockH = m_row + 4 * (Px(22) + Px(3)) + m_row * 3 + Px(8);
   int maxH = MathMax(Px(160), ch - Px(m_cfg.offsetY) * 2 - Px(m_cfg.bottomClearance));
   int wantH = bodyH;
   if(bodyH + clockH <= maxH)
      wantH += clockH;
   int h = MathMin(wantH, maxH);

   int x = 0, y = 0;
   Place(w, h, x, y);
   if(!EnsureCanvas(w, h, x, y))
      return;

   m_canvas.Erase(ARGB(m_theme.bg, m_theme.bgAlpha));
   FillRound(0, 0, m_w, m_h, m_radius, ARGB(m_theme.bg, m_theme.bgAlpha));
   StrokeRound(0, 0, m_w, m_h, m_radius, ARGB(m_theme.border, 255));

   int x0 = m_pad;
   int x1 = m_w - m_pad;
   m_curY = m_pad;

   DrawHeader(vm, x0, x1);
   HLine(x0, x1, m_curY, ARGB(m_theme.border, 180));
   m_curY += Px(8);
   DrawAccount(vm, x0, x1);
   HLine(x0, x1, m_curY, ARGB(m_theme.border, 140));
   m_curY += Px(8);
   DrawPositions(vm, x0, x1);
   HLine(x0, x1, m_curY, ARGB(m_theme.border, 140));
   m_curY += Px(8);
   DrawGuards(vm, x0, x1);
   HLine(x0, x1, m_curY, ARGB(m_theme.border, 140));
   m_curY += Px(8);
   DrawClock(vm, x0, x1);
   DrawActions(vm, x0, x1);

   if(StringLen(vm.lastError) > 0 && Room(m_row))
     {
      Font(m_fsSm, false);
      Text(x0, m_h - m_pad - m_row, vm.lastError, ARGB(m_theme.red));
     }

   m_canvas.Update(true);
  }

#endif // DOMPANION_DASHBOARD_MQH
