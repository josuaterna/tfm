//+------------------------------------------------------------------+
//|                                        TradingSystemEA.mq5      |
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

// Objetos de trading
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

// Parámetros de entrada configurables
input group "=== CONFIGURACIÓN BÁSICA ==="
input bool LotPer = false;                       // Activar tamaño lote porcentaje
input double LotSize = 0.01;                    // Tamaño de lote
input double LotSizePer= 0.01;                 // Tamaño de lote en porcentaje   
input ulong MagicNumber = 12345;               // Número mágico
input uint Slippage = 10;                       // Deslizamiento en puntos

input group "=== HORARIOS DE OPERACIÓN ==="
input int StartHourNY = 14;                    // Hora inicio Nueva York (GMT)
input int EndHourNY = 23;                      // Hora fin Nueva York (GMT)
input int StartHourLondon = 8;                 // Hora inicio Londres (GMT)
input int EndHourLondon = 17;                  // Hora fin Londres (GMT)

input group "=== PARÁMETROS DE TENDENCIA ==="
input double TrendPercentage = 80.0;           // Porcentaje objetivo cierres/aperturas EMA50 (%)
input int TrendPeriods = 25;                   // Períodos para análisis encima/debajo EMA50
input int InclinationPeriods = 25;             // Períodos para inclinación pronunciada EMA50
input int InclinationFactor = 10;               // Factor a multiplicar slope para detectar inclinación

input group "=== PARÁMETROS DE VOLATILIDAD ==="
input int InpPeriods = 5;                      // Períodos
input int InpADXMinLevel = 30;                 // Nivel mínimo ADX para operar

input group "=== PARÁMETROS DE GESTIÓN ==="
input double TakeProfitFactor = 1.5;           // Factor Take Profit
input int CandleAveragePeriods = 30;           // Períodos para promedio velas grandes
input double StrongCandleFactor = 2;         // Factor para determinar vela grande
input int MaxPosActivas = 3;                   // Cantidad de posiciones activas máxima permitida
input int SupResThreshold = 60;                // Factor de gap para soporte / resistencia 

// Variables para handles de indicadores
int emaHandle;
int rsiHandle;
int adxHandle;

// Arrays para datos de indicadores
double emaArray[];
double rsiArray[];
double adxArray[];
double diPlusArray[];
double diMinusArray[];

// Enumeraciones para estados
enum TrendDirection {
   TREND_NONE = 0,
   TREND_BULLISH = 1,
   TREND_BEARISH = -1
};

enum MarketCondition {
   CONDITION_NONE = 0,
   CONDITION_OVERSOLD = 1,
   CONDITION_OVERBOUGHT = -1
};



//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Configurar magic number para el objeto trade
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   // Inicializar handles de indicadores
   emaHandle = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, 3, PRICE_CLOSE);
   adxHandle = iADXWilder(_Symbol,PERIOD_CURRENT, InpPeriods);
   
   // Verificar handles válidos
   if(emaHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE) {
      Print("Error al crear handles de indicadores");
      return(INIT_FAILED);
   }
   
   // Configurar arrays como series temporales
   ArraySetAsSeries(emaArray, true);
   ArraySetAsSeries(rsiArray, true);
   ArraySetAsSeries(adxArray, true);
   ArraySetAsSeries(diPlusArray, true);
   ArraySetAsSeries(diMinusArray, true);
   
   Print("EA inicializado correctamente");
   Print("Parámetros configurados:");
   Print("- Porcentaje tendencia: ", TrendPercentage, "%");
   Print("- Períodos tendencia: ", TrendPeriods);
   Print("- Períodos inclinación: ", InclinationPeriods);
   Print("- Factor TP: ", TakeProfitFactor);
   Print("- Posiciones activas máx: ", MaxPosActivas);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Liberar handles
   if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   
   Print("EA finalizado");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Verificar si es horario de trading válido
   if(!IsValidTradingSession()) {
      return;
   }
   
   // Verificar si ya hay posiciones abiertas
   if(CountOpenPositions() > MaxPosActivas) {
      return;
   }
   
   // Actualizar datos de indicadores
   if(!UpdateIndicatorData()) {
      return;
   }
   
   // Paso 1: Detectar tendencia
   TrendDirection trend = DetectTrend();
   if(trend == TREND_NONE) {
      return;
   }
   
   // Paso 2: Evaluar RSI para sobre compra/venta
   MarketCondition condition = EvaluateRSI(trend);
   if(condition == CONDITION_NONE) {
      return;
   }
   
   // Paso 3: Evaluar ADX
   if(!IsADXStrong()) {
      return;
   }
   
   // Paso 4: Evaluar zona de soporte/resistencia
   if(!IsPriceInSupportResistanceZone(trend)) {
      return;
   }
   
   // Paso 5: Ejecutar operación si se cumplen todas las condiciones
   ExecuteTrade(trend, condition);
}

//+------------------------------------------------------------------+
//| Verificar si es sesión de trading válida                        |
//+------------------------------------------------------------------+
bool IsValidTradingSession()
{
   MqlDateTime timeStruct;
   datetime currentTime = TimeCurrent(timeStruct);
   
   // Evitar fines de semana
   if(timeStruct.day_of_week == 0 || timeStruct.day_of_week == 6) {
      return false;
   }
   
   int hour = timeStruct.hour;
   
   // Sesión de Nueva York
   bool nySession = (hour >= StartHourNY && hour < EndHourNY);
   // Sesión de Londres
   bool londonSession = (hour >= StartHourLondon && hour < EndHourLondon);
   
   return (nySession || londonSession);
}

//+------------------------------------------------------------------+
//| Actualizar datos de indicadores                                 |
//+------------------------------------------------------------------+
bool UpdateIndicatorData()
{
   // Copiar datos EMA
   if(CopyBuffer(emaHandle, 0, 0, TrendPeriods + 10, emaArray) <= 0) {
      Print("Error copiando datos EMA");
      return false;
   }
   
   // Copiar datos RSI
   if(CopyBuffer(rsiHandle, 0, 0, 10, rsiArray) <= 0) {
      Print("Error copiando datos RSI");
      return false;
   }
   
   // Copiar datos ADX
   if(CopyBuffer(adxHandle, 0, 0, 10, adxArray) <= 0) {
      Print("Error copiando datos ADX principal");
      return false;
   }
   
   // Copiar datos DI+
   if(CopyBuffer(adxHandle, 1, 0, 10, diPlusArray) <= 0) {
      Print("Error copiando datos DI+");
      return false;
   }
   
   // Copiar datos DI-
   if(CopyBuffer(adxHandle, 2, 0, 10, diMinusArray) <= 0) {
      Print("Error copiando datos DI-");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Detectar tendencia según los criterios especificados            |
//+------------------------------------------------------------------+
TrendDirection DetectTrend()
{
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, TrendPeriods + 1, rates) <= 0) {
      Print("Error copiando datos de precios para tendencia");
      return TREND_NONE;
   }
   
   ArraySetAsSeries(rates, true);
   
   // Indicio 1: Evaluar últimos períodos especificados
   int bullishCloseCount = 0;
   int bearishOpenCount = 0;
   
   for(int i = 1; i <= TrendPeriods; i++) {
      if(i >= ArraySize(rates) || i >= ArraySize(emaArray)) break;
      
      double closePrice = rates[i].close;
      double openPrice = rates[i].open;
      double emaValue = emaArray[i];
      
      if(closePrice > emaValue) {
         bullishCloseCount++;
      }
      
      if(openPrice < emaValue) {
         bearishOpenCount++;
      }
   }
   
   double requiredCount = (TrendPeriods * TrendPercentage) / 100.0;
   bool indicio1Alcista = (bullishCloseCount >= requiredCount);
   bool indicio1Bajista = (bearishOpenCount >= requiredCount);
   
   if(indicio1Alcista) {
      return TREND_BULLISH;
   }
   else if(indicio1Bajista) {
      return TREND_BEARISH;
   }
   
   return TREND_NONE;
}


//+------------------------------------------------------------------+
//| Evaluar RSI para condiciones de sobre compra/venta              |
//+------------------------------------------------------------------+
MarketCondition EvaluateRSI(TrendDirection trend)
{
   if(ArraySize(rsiArray) == 0) return CONDITION_NONE;
   
   double currentRSI = rsiArray[1];
   double lastRSI = rsiArray[2];
   
   if(trend == TREND_BULLISH && lastRSI <= 20 && currentRSI > 20) {
      return CONDITION_OVERSOLD;
   }
   else if(trend == TREND_BEARISH && lastRSI >= 80 && currentRSI < 80) {
      return CONDITION_OVERBOUGHT;
   }
   
   return CONDITION_NONE;
}

//+------------------------------------------------------------------+
//| Verificar si ADX es fuerte (30 o más)                          |
//+------------------------------------------------------------------+
bool IsADXStrong()
{
   if(ArraySize(adxArray) == 0) return false;
   
   double currentADX = adxArray[2];
   return (currentADX >= InpADXMinLevel);
}

//+------------------------------------------------------------------+
//| Verificar si el precio está en zona de soporte/resistencia      |
//+------------------------------------------------------------------+
bool IsPriceInSupportResistanceZone(TrendDirection trend)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   
   if(ArraySize(emaArray) == 0) return false;
   
   double currentPrice = tick.last;
   double ema50 = emaArray[0];
   double tolerance = _Point * SupResThreshold; // Tolerancia
   
   if(trend == TREND_BULLISH) {
      // En tendencia alcista, buscar soporte cerca de EMA50
      return (MathAbs(currentPrice - ema50) <= tolerance && currentPrice >= ema50);
   }
   else if(trend == TREND_BEARISH) {
      // En tendencia bajista, buscar resistencia cerca de EMA50
      return (MathAbs(currentPrice - ema50) <= tolerance && currentPrice <= ema50);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Ejecutar operación de trading                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(TrendDirection trend, MarketCondition condition)
{
   if(trend == TREND_BULLISH && condition == CONDITION_OVERSOLD) {
      if (ExecuteBuyTrade())
      {
         Print("OK Buy");
      }
   }
   else if(trend == TREND_BEARISH && condition == CONDITION_OVERBOUGHT) {
      if (ExecuteSellTrade())
      {
         Print("OK Sell");
      }
   }
}

//+------------------------------------------------------------------+
//| Ejecutar operación de compra                                    |
//+------------------------------------------------------------------+
bool ExecuteBuyTrade()
{
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 10, rates) <= 0) return false;
   ArraySetAsSeries(rates, true);

   int i = 1;
   if(i >= ArraySize(rsiArray)) return false;
   
   double openPrice = rates[i].open;
   double closePrice = rates[i].close;
   double highPrice = rates[i].high;
   double lowPrice = rates[i].low;
   double rsiValue = rsiArray[i];
   
   // Verificar si es vela verde
   if(closePrice > openPrice) {
      // Verificar si es vela fuerte
      if(IsCandleStrong(i, rates)) {
      
      //--- 1. ENTRADA: A mercado (precio actual ASK)
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         //--- 2. STOP LOSS: Por debajo de la vela (usar el mínimo)
         double stopLoss = lowPrice;
         
         //--- 3. CALCULAR RIESGO usando el máximo como referencia
         double entryReference = highPrice;  // Referencia para cálculos
         double risk = entryReference - stopLoss;
         
         //--- Validar riesgo mínimo
         if(risk <= 0) 
         {
             Print("Error: Riesgo inválido");
             return false;
         }
         
         //--- 4. TAKE PROFIT: Relación 1:1 o 1.5:1 basada en referencia
         double riskRewardRatio = TakeProfitFactor;
         double takeProfit = currentAsk + (risk * riskRewardRatio);
         
         //--- 5. EJECUTAR COMPRA A MERCADO
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_DEAL;
         request.symbol = _Symbol;
         if (!LotPer){
            request.volume = LotSize; // lote fijo
         }
         else{
            double lotSizecalc = (AccountInfoDouble(ACCOUNT_BALANCE) * LotSizePer) / (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * SymbolInfoDouble(_Symbol, SYMBOL_BID));
            
            //--- NORMALIZAR EL LOTE SEGÚN ESPECIFICACIONES DEL BROKER
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
            double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            
            //--- Ajustar al step más cercano
            lotSizecalc = MathFloor(lotSizecalc / lotStep) * lotStep;
            
            //--- Validar límites
            if(lotSizecalc < minLot) lotSizecalc = minLot;
            if(lotSizecalc > maxLot) lotSizecalc = maxLot;
            
            request.volume = lotSizecalc;
         }
         request.type = ORDER_TYPE_BUY;           // COMPRA A MERCADO
         request.price = currentAsk;              // Precio actual de mercado
         request.sl = stopLoss;
         request.tp = takeProfit;
         request.deviation = Slippage;
         request.magic = MagicNumber;
         request.comment = StringFormat("Buy Market: Price=%.5f SL=%.5f TP=%.5f", 
                                        currentAsk, stopLoss, takeProfit);
         
         //--- Enviar orden
         if(OrderSend(request, result))
         {
             if(result.retcode == TRADE_RETCODE_DONE)
             {
                 Print("✅ COMPRA A MERCADO EJECUTADA:");
                 Print("  Precio de entrada: ", result.price);
                 Print("  Referencia (máximo): ", entryReference);
                 Print("  Stop Loss: ", stopLoss);
                 Print("  Take Profit: ", takeProfit);
                 Print("  Riesgo calculado: ", DoubleToString(risk, _Digits));
                 Print("  Recompensa esperada: ", DoubleToString(risk * riskRewardRatio, _Digits));
                 Print("  Ratio R:R = 1:", riskRewardRatio);
                 return true;
             }
             else
             {
                 Print("❌ Error en ejecución: ", result.retcode);
                 return false;
             }
         }
         else
         {
             Print("❌ Error enviando orden: ", GetLastError());
             return false;
         }
      }
   }
   
   return true;
}


//+------------------------------------------------------------------+
//| Ejecutar operación de venta                                     |
//+------------------------------------------------------------------+

bool ExecuteSellTrade()
{
  MqlRates rates[];
  if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 10, rates) <= 0) return false;
  ArraySetAsSeries(rates, true);
  int i = 1;
  if(i >= ArraySize(rsiArray)) return false;
  
  double openPrice = rates[i].open;
  double closePrice = rates[i].close;
  double highPrice = rates[i].high;
  double lowPrice = rates[i].low;
  double rsiValue = rsiArray[i];
  
  // Verificar si es vela roja
  if(closePrice < openPrice) {
     // Verificar si es vela fuerte
     if(IsCandleStrong(i, rates)) {
     
     //--- 1. ENTRADA: A mercado (precio actual BID)
        double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        
        //--- 2. STOP LOSS: Por encima de la vela (usar el máximo)
        double stopLoss = highPrice;
        
        //--- 3. CALCULAR RIESGO usando el mínimo como referencia
        double entryReference = lowPrice;  // Referencia para cálculos
        double risk = stopLoss - entryReference;
        
        //--- Validar riesgo mínimo
        if(risk <= 0) 
        {
            Print("Error: Riesgo inválido");
            return false;
        }
        
        //--- 4. TAKE PROFIT: Relación 1:1 o 1.5:1 basada en referencia
        double riskRewardRatio = TakeProfitFactor;
        double takeProfit = currentBid - (risk * riskRewardRatio);
        
        //--- 5. EJECUTAR VENTA A MERCADO
        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        
        request.action = TRADE_ACTION_DEAL;
        request.symbol = _Symbol;
        if (!LotPer){
           request.volume = LotSize; // lote fijo
        }
        else{
            double lotSizecalc = (AccountInfoDouble(ACCOUNT_BALANCE) * LotSizePer) / (SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE) * SymbolInfoDouble(_Symbol, SYMBOL_BID));
            
            //--- NORMALIZAR EL LOTE SEGÚN ESPECIFICACIONES DEL BROKER
            double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
            double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            
            //--- Ajustar al step más cercano
            lotSizecalc = MathFloor(lotSizecalc / lotStep) * lotStep;
            
            //--- Validar límites
            if(lotSizecalc < minLot) lotSizecalc = minLot;
            if(lotSizecalc > maxLot) lotSizecalc = maxLot;
            
            request.volume = lotSizecalc;
        }
        request.type = ORDER_TYPE_SELL;          // VENTA A MERCADO
        request.price = currentBid;              // Precio actual de mercado
        request.sl = stopLoss;
        request.tp = takeProfit;
        request.deviation = Slippage;
        request.magic = MagicNumber;
        request.comment = StringFormat("Sell Market: Price=%.5f SL=%.5f TP=%.5f", 
                                       currentBid, stopLoss, takeProfit);
        
        //--- Enviar orden
        if(OrderSend(request, result))
        {
            if(result.retcode == TRADE_RETCODE_DONE)
            {
                Print("✅ VENTA A MERCADO EJECUTADA:");
                Print("  Precio de entrada: ", result.price);
                Print("  Referencia (mínimo): ", entryReference);
                Print("  Stop Loss: ", stopLoss);
                Print("  Take Profit: ", takeProfit);
                Print("  Riesgo calculado: ", DoubleToString(risk, _Digits));
                Print("  Recompensa esperada: ", DoubleToString(risk * riskRewardRatio, _Digits));
                Print("  Ratio R:R = 1:", riskRewardRatio);
                return true;
            }
            else
            {
                Print("❌ Error en ejecución: ", result.retcode);
                return false;
            }
        }
        else
        {
            Print("❌ Error enviando orden: ", GetLastError());
            return false;
        }
     }
  }
  
  return true;
}


//+------------------------------------------------------------------+
//| Verificar si una vela es fuerte                                 |
//+------------------------------------------------------------------+
bool IsCandleStrong(int index, const MqlRates &rates[])
{
   if(index >= ArraySize(rates)) return false;
   
   double currentCandleBody = MathAbs(rates[index].close - rates[index].open);
   
   // Calcular promedio de las últimas velas especificadas
   double totalBody = 0;
   int validCandles = 0;
   
   for(int i = index + 1; i <= index + CandleAveragePeriods && i < ArraySize(rates); i++) {
      totalBody += MathAbs(rates[i].close - rates[i].open);
      validCandles++;
   }
   
   if(validCandles == 0) return false;
   
   double averageBody = totalBody / validCandles;
   double threshold = averageBody * StrongCandleFactor;
   
   return (currentCandleBody >= threshold && currentCandleBody >= _Point*10);
}

//+------------------------------------------------------------------+
//| Contar posiciones abiertas                                      |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = 0; i < PositionsTotal(); i++) {
      if(positionInfo.SelectByIndex(i)) {
         if(positionInfo.Symbol() == _Symbol && positionInfo.Magic() == MagicNumber) {
            count++;
         }
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Función para debug y logging                                    |
//+------------------------------------------------------------------+
void DebugInfo()
{
   if(ArraySize(emaArray) > 0 && ArraySize(rsiArray) > 0 && ArraySize(adxArray) > 0) {
      Print("=== DEBUG INFO ===");
      Print("EMA50[0]: ", emaArray[0]);
      Print("RSI[0]: ", rsiArray[0]);
      Print("ADX[0]: ", adxArray[0]);
      Print("Current Time: ", TimeToString(TimeCurrent()));
      Print("Valid Session: ", IsValidTradingSession());
      Print("================");
   }
}