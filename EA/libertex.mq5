//+------------------------------------------------------------------+
//|  EA: RebuySmallProfitEA.mq5                                      |
//|  Función: abre buy y sell por ~$10 con apalancamiento (cálculo   |
//|  de lots), cierra cuando cada operación tenga $1 de ganancia,    |
//|  y reabre inmediatamente. Incluye manejo de riesgo de margen.    |
//+------------------------------------------------------------------+
#property copyright "Generado por ChatGPT"
#property version   "1.02"
#property strict

#include <Trade/Trade.mqh>

input double  TargetUSD            = 10.0;     // Monto objetivo en USD por operación (exposición)
input double  ProfitTargetUSD      = 1.0;      // Cerrar cuando la operación tenga esta ganancia en USD
input int     DesiredLeverage      = 250;      // Apalancamiento objetivo (solo usado en el cálculo de lotes)
input int     MagicNumber          = 20250911; // MagicNumber para identificar las posiciones del EA
input int     Slippage             = 10;       // Slippage permitido (puntos)
input double  MarginLevelCloseThreshold = 120.0; // % de margin level mínimo
input bool    CloseOtherPositionsOnRisk = false;   // si true, intentará cerrar otras posiciones
input bool    SendMobileNotif      = false;     // si true enviará notificaciones push (configurar en terminal)

input group "=== HORARIOS DE OPERACIÓN ==="
input bool ValidarHorario = true;                 // Validar horario
input bool ValidarHorarioDia = true;                 // Validar horario por día
input int StartHourNY = 14;                    // Hora inicio Nueva York (GMT)
input int EndHourNY = 23;                      // Hora fin Nueva York (GMT)
input int StartHourLondon = 8;                 // Hora inicio Londres (GMT)
input int EndHourLondon = 17;                  // Hora fin Londres (GMT)

input int ny_monOpen = 0;                // Incremento hora inicio Nueva York Lunes
input int ny_tueOpen = 0;               // Incremento hora inicio Nueva York Martes
input int ny_wedOpen = 0;               // Incremento hora inicio Nueva York Miércoles
input int ny_thuOpen = 0;                // Incremento hora inicio Nueva York Jueves
input int ny_friOpen = 0;                // Incremento hora inicio Nueva York Viernes
input int lo_monOpen = 0;                 // Incremento hora inicio Londres Lunes
input int lo_tueOpen = 0;                // Incremento hora inicio Londres Martes
input int lo_wedOpen = 0;                // Incremento hora inicio Londres Miércoles
input int lo_thuOpen = 0;                // Incremento hora inicio Londres Jueves
input int lo_friOpen = 0;                // Incremento hora inicio Londres Viernes
input int ny_monClose = 0;                 // Incremento hora fin Nueva York Lunes
input int ny_tueClose = 0;               // Incremento hora fin Nueva York Martes
input int ny_wedClose = 0;                // Incremento hora fin Nueva York Miércoles
input int ny_thuClose = 0;                // Incremento hora fin Nueva York Jueves
input int ny_friClose = 0;                // Incremento hora fin Nueva York Viernes
input int lo_monClose = 0;                 // Incremento hora fin Londres Lunes
input int lo_tueClose = 0;                // Incremento hora fin Londres Martes
input int lo_wedClose = 0;                // Incremento hora fin Londres Miércoles
input int lo_thuClose = 0;                // Incremento hora fin Londres Jueves
input int lo_friClose = 0;                // Incremento hora fin Londres Viernes

CTrade trade;
double g_currentLotFactor = 1.0; // factor multiplicador (se reduce si hay riesgo de margen)

//+------------------------------------------------------------------+
//| Calcula volumen (lots) aproximado para exponer 'usd' (BUY)      |
//+------------------------------------------------------------------+
double CalculateLotForUSD(double usd_amount, double leverage_override)
{
   double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(contract_size <= 0 || price <= 0) return(0.0);

   // Volumen (lots) = (usd_amount * leverage) / (contract_size * price)
   double lots = (usd_amount * leverage_override) / (contract_size * price);

   // Ajustar al step/min/max
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lot_min <= 0) lot_min = 0.01;
   if(lot_step <= 0) lot_step = 0.01;

   lots *= g_currentLotFactor;

   double steps = MathFloor(lots / lot_step + 0.0000001);
   double lots_norm = steps * lot_step;

   if(lots_norm < lot_min) lots_norm = lot_min;
   if(lots_norm > lot_max) lots_norm = lot_max;

   return(NormalizeDouble(lots_norm, 2));
}

//+------------------------------------------------------------------+
//| Calcula volumen (lots) aproximado para exponer 'usd' (SELL)     |
//+------------------------------------------------------------------+
double CalculateLotForUSDSell(double usd_amount, double leverage_override)
{
   double contract_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(contract_size <= 0 || price <= 0) return(0.0);

   double lots = (usd_amount * leverage_override) / (contract_size * price);

   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(lot_min <= 0) lot_min = 0.01;
   if(lot_step <= 0) lot_step = 0.01;

   lots *= g_currentLotFactor;

   double steps = MathFloor(lots / lot_step + 0.0000001);
   double lots_norm = steps * lot_step;

   if(lots_norm < lot_min) lots_norm = lot_min;
   if(lots_norm > lot_max) lots_norm = lot_max;

   return(NormalizeDouble(lots_norm, 2));
}

//+------------------------------------------------------------------+
//| Abre operación BUY                                               |
//+------------------------------------------------------------------+
bool OpenBuy(double lots)
{
   if(lots <= 0) return false;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.volume   = lots;
   request.type     = ORDER_TYPE_BUY;
   request.price    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.deviation= Slippage;
   request.magic    = (ulong)MagicNumber;
   request.type_filling = ORDER_FILLING_FOK;
   request.comment  = "RebuySmallProfitEA";

   if(!OrderSend(request, result))
   {
      PrintFormat("OrderSend falló. retcode=%d", result.retcode);
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      PrintFormat("Apertura BUY fallida, retcode=%d, comment=%s", result.retcode, result.comment);
      return false;
   }

   PrintFormat("Apertura BUY: ticket=%I64u, lots=%.2f, price=%.5f", result.order, lots, request.price);
   return true;
}

//+------------------------------------------------------------------+
//| Abre operación SELL                                              |
//+------------------------------------------------------------------+
bool OpenSell(double lots)
{
   if(lots <= 0) return false;

   MqlTradeRequest request;
   MqlTradeResult  result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = _Symbol;
   request.volume   = lots;
   request.type     = ORDER_TYPE_SELL;
   request.price    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.deviation= Slippage;
   request.magic    = (ulong)MagicNumber;
   request.type_filling = ORDER_FILLING_FOK;
   request.comment  = "ResellSmallProfitEA";

   if(!OrderSend(request, result))
   {
      PrintFormat("OrderSend falló. retcode=%d", result.retcode);
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
   {
      PrintFormat("Apertura SELL fallida, retcode=%d, comment=%s", result.retcode, result.comment);
      return false;
   }

   PrintFormat("Apertura SELL: ticket=%I64u, lots=%.2f, price=%.5f", result.order, lots, request.price);
   return true;
}

//+------------------------------------------------------------------+
//| Cierra posición por ticket                                       |
//+------------------------------------------------------------------+
bool ClosePositionByTicket(ulong ticket)
{
   bool closed = trade.PositionClose(ticket, Slippage);
   if(!closed)
   {
      PrintFormat("Error cerrando posición ticket=%I64u. GetLastError=%d", ticket, GetLastError());
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Devuelve el ticket de la posición propia BUY (o 0)               |
//+------------------------------------------------------------------+
ulong GetMyBuyTicket()
{
   for(int i=0;i<PositionsTotal();++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long   magic = (long)PositionGetInteger(POSITION_MAGIC);
      long   ptype = (long)PositionGetInteger(POSITION_TYPE); // 0 buy, 1 sell
      if(sym==_Symbol && magic == MagicNumber && ptype == POSITION_TYPE_BUY)
         return ticket;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Devuelve el ticket de la posición propia SELL (o 0)              |
//+------------------------------------------------------------------+
ulong GetMySellTicket()
{
   for(int i=0;i<PositionsTotal();++i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      long   magic = (long)PositionGetInteger(POSITION_MAGIC);
      long   ptype = (long)PositionGetInteger(POSITION_TYPE); // 0 buy, 1 sell
      if(sym==_Symbol && magic == MagicNumber && ptype == POSITION_TYPE_SELL)
         return ticket;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Calcular margin level %                                          |
//+------------------------------------------------------------------+
double GetMarginLevelPercent()
{
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double free   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin <= 0) return 1e9;
   return (free / margin) * 100.0;
}

//+------------------------------------------------------------------+
//| Intenta cerrar otras posiciones                                  |
//+------------------------------------------------------------------+
void TryCloseOtherPositions()
{
   if(!CloseOtherPositionsOnRisk) return;

   for(int i=PositionsTotal()-1;i>=0;--i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      if(magic == MagicNumber) continue; // no cierres nuestras
      string sym = PositionGetString(POSITION_SYMBOL);

      PrintFormat("Intentando cerrar posición externa ticket=%I64u", ticket);
      bool res = trade.PositionClose(ticket, Slippage);
      if(res) PrintFormat("Cerrada posición externa ticket=%I64u", ticket);
      else PrintFormat("No se pudo cerrar posición externa ticket=%I64u, err=%d", ticket, GetLastError());
      Sleep(200);
   }
}

//+------------------------------------------------------------------+
//| Manejo de riesgo por margen                                      |
//+------------------------------------------------------------------+
void HandleMarginRisk()
{
   double ml = GetMarginLevelPercent();
   PrintFormat("MarginLevel=%.2f%%", ml);

   if(ml < MarginLevelCloseThreshold)
   {
      Print("Riesgo de margen detectado. Intentando mitigación...");
      if(SendMobileNotif)
         SendNotification("EA: Riesgo de margen detectado. Revisar.");
      TryCloseOtherPositions();

      ml = GetMarginLevelPercent();
      PrintFormat("Tras liberar margen, MarginLevel=%.2f%%", ml);

      if(ml < MarginLevelCloseThreshold)
      {
         g_currentLotFactor *= 0.5;
         if(g_currentLotFactor < 0.1) g_currentLotFactor = 0.1;
         string msg = StringFormat("Reduciendo tamaño futuras operaciones: factor=%.3f", g_currentLotFactor);
         Print(msg);
         if(SendMobileNotif) SendNotification("EA: " + msg);
      }
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   Print("RebuySmallProfitEA iniciado. TargetUSD=", TargetUSD, " ProfitTargetUSD=", ProfitTargetUSD);
   if(!SymbolInfoInteger(_Symbol, SYMBOL_SELECT))
   {
      if(!SymbolSelect(_Symbol, true))
      {
         Print("No se pudo seleccionar símbolo ", _Symbol);
         return(INIT_FAILED);
      }
   }
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   HandleMarginRisk();

   // Tickets de nuestras posiciones para este símbolo y magic
   ulong buyTicket  = GetMyBuyTicket();
   ulong sellTicket = GetMySellTicket();

   // Si no existe ninguna de las dos, intentamos abrir ambas (si es sesión válida)
   if(buyTicket == 0 && sellTicket == 0)
   {
      if(!IsValidTradingSession()) return;

      double lotsBuy  = CalculateLotForUSD(TargetUSD, DesiredLeverage);
      double lotsSell = CalculateLotForUSDSell(TargetUSD, DesiredLeverage);

      if(lotsBuy <= 0 || lotsSell <= 0)
      {
         Print("Volumen inválido. No se abren posiciones.");
         return;
      }

      // Intentar abrir ambas. Si una falla, la otra puede seguir.
      OpenBuy(lotsBuy);
      Sleep(100);
      OpenSell(lotsSell);
      return;
   }

   // --- Manejo individual de BUY ---
   if(buyTicket != 0)
   {
      if(!PositionSelectByTicket(buyTicket))
      {
         // si no podemos seleccionar, forzamos a 0 para reabrir en la siguiente iteración
         buyTicket = 0;
      }
      else
      {
         double profit = PositionGetDouble(POSITION_PROFIT);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);

         Comment(StringFormat("BUY: ticket=%I64u | profit=%.2f USD | volume=%.2f | open_price=%.5f",
                              buyTicket, profit, volume, open_price));

         if(profit >= ProfitTargetUSD)
         {
            PrintFormat("BUY: Objetivo alcanzado (%.2f >= %.2f). Cerrando ticket=%I64u", profit, ProfitTargetUSD, buyTicket);
            if(ClosePositionByTicket(buyTicket))
            {
               Sleep(200);
               // Reabrir BUY si la sesión lo permite
               if(IsValidTradingSession())
               {
                  double lots = CalculateLotForUSD(TargetUSD, DesiredLeverage);
                  if(lots > 0) OpenBuy(lots);
               }
            }
         }
      }
   }

   // --- Manejo individual de SELL ---
   if(sellTicket != 0)
   {
      if(!PositionSelectByTicket(sellTicket))
      {
         sellTicket = 0;
      }
      else
      {
         double profit = PositionGetDouble(POSITION_PROFIT);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);

         Comment(StringFormat("SELL: ticket=%I64u | profit=%.2f USD | volume=%.2f | open_price=%.5f",
                              sellTicket, profit, volume, open_price));

         if(profit >= ProfitTargetUSD)
         {
            PrintFormat("SELL: Objetivo alcanzado (%.2f >= %.2f). Cerrando ticket=%I64u", profit, ProfitTargetUSD, sellTicket);
            if(ClosePositionByTicket(sellTicket))
            {
               Sleep(200);
               // Reabrir SELL si la sesión lo permite
               if(IsValidTradingSession())
               {
                  double lots = CalculateLotForUSDSell(TargetUSD, DesiredLeverage);
                  if(lots > 0) OpenSell(lots);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
bool IsValidTradingSession()
{
   if(!ValidarHorario)
   {
      return true;
   }

   MqlDateTime timeStruct;
   datetime currentTime = TimeCurrent(timeStruct);
   int hour = timeStruct.hour;

   // Evitar fines de semana (domingo=0, sábado=6)
   if(timeStruct.day_of_week == 0 || timeStruct.day_of_week == 6) {
      return false;
   }

   if(ValidarHorarioDia){
      if(timeStruct.day_of_week == 5) {
         bool nySession = (hour >= StartHourNY+ny_friOpen && hour < (EndHourNY - ny_friClose));
         bool londonSession = (hour >= StartHourLondon+lo_friOpen && hour < EndHourLondon - lo_friClose);
         return (nySession || londonSession);
      }
      if(timeStruct.day_of_week == 4) {
         bool nySession = (hour >= StartHourNY+ny_thuOpen && hour < EndHourNY - ny_thuClose);
         bool londonSession = (hour >= StartHourLondon+lo_thuOpen && hour < EndHourLondon - lo_thuClose);
         return (nySession || londonSession);
      }
      if(timeStruct.day_of_week == 3) {
         bool nySession = (hour >= StartHourNY+ny_wedOpen && hour < EndHourNY - ny_wedClose);
         bool londonSession = (hour >= StartHourLondon+lo_wedOpen && hour < EndHourLondon - lo_wedClose);
         return (nySession || londonSession);
      }
      if(timeStruct.day_of_week == 2) {
         bool nySession = (hour >= StartHourNY+ny_tueOpen && hour < EndHourNY - ny_tueClose);
         bool londonSession = (hour >= StartHourLondon+lo_tueOpen && hour < EndHourLondon - lo_tueClose);
         return (nySession || londonSession);
      }
      if(timeStruct.day_of_week == 1) {
         bool nySession = (hour >= StartHourNY+ny_monOpen && hour < EndHourNY - ny_monClose);
         bool londonSession = (hour >= StartHourLondon+lo_monOpen && hour < EndHourLondon - lo_monClose);
         return (nySession || londonSession);
      }
   }

   bool nySession = (hour >= StartHourNY && hour < EndHourNY);
   bool londonSession = (hour >= StartHourLondon && hour < (EndHourLondon));

   return (nySession || londonSession);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("RebuySmallProfitEA detenido. Reason=", reason);
}
