//+------------------------------------------------------------------+
//|                                        Scalping_Pro_Extended.mq5|
//|                        Copyright 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.01"

#include <Performance_Analyzer.mqh>
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

// Objetos de trading
CTrade trade;
CPositionInfo positionInfo;
COrderInfo orderInfo;

// Parámetros de entrada configurables
input group "=== ANÁLISIS DE PERFORMANCE ==="
input bool EnablePerformanceAnalysis = true;  // Activar análisis de performance
input int PerformanceReportInterval = 500;    // Intervalo para reportes (ticks)
input bool ExportPerformanceCSV = true;       // Exportar reporte a CSV al finalizar

input group "=== CONFIGURACIÓN BÁSICA ==="
input bool LotPer = false;                       // Activar tamaño lote porcentaje
input double LotSize = 0.1;                    // Tamaño de lote
input double LotSizePer= 0.01;                 // Tamaño de lote en porcentaje   
input ulong MagicNumber = 12345;               // Número mágico
input uint Slippage = 10;                       // Deslizamiento en puntos

input group "=== MODO DE OPERACIÓN ==="
input bool UseChandelierExit = false;            // Usar Chandelier Exit en lugar de indicadores normales
input bool ValidateSchedule = true;              // Activar validación de horarios
input bool ValidateActivePos = true;             // Activar cantidad de posiciones activas

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

input group "=== PARÁMETROS CHANDELIER EXIT ==="
input int CE_ATR_Period = 1;                   // Período ATR para Chandelier Exit
input double CE_ATR_Multiplier = 2.0;          // Multiplicador ATR para Chandelier Exit
input bool CE_UseCloseForExtremums = true;     // Usar cierre para extremos en Chandelier Exit
input int CE_lookback = 25;                     // SWING Número de velas hacia atrás a analizar
input int CE_strength = 2;                      // SWING Número de velas a cada lado que deben ser menores/mayores
input int CE_minDistance = 5;                   // SWING Distancia mínima desde la vela actual
input bool CE_AOMACD = false;                   // Activar validación de cruce MACD

input group "=== PARÁMETROS ZLSMA ==="
input int ZLSMA_Length = 32;                   // Período ZLSMA
input ENUM_APPLIED_PRICE ZLSMA_Source = PRICE_CLOSE; // Fuente de precio ZLSMA

input group "=== PARÁMETROS AO_MACD ==="
input int AO_MACD_FastLength = 20;             // Fast Length AO_MACD
input int AO_MACD_SlowLength = 30;             // Slow Length AO_MACD
input int AO_MACD_SignalLength = 10;           // Signal Length AO_MACD
input int CrossLookback = 2;                   // Velas hacia atrás para buscar cruces

input group "=== PARÁMETROS DE GESTIÓN ==="
input bool OneTradePerCandle = true;           // Solo una operación por vela
input double TakeProfitFactor = 1.5;           // Factor Take Profit
input int CandleAveragePeriods = 30;           // Períodos para promedio velas grandes
input double StrongCandleFactor = 2;         // Factor para determinar vela grande
input int MaxPosActivas = 3;                   // Cantidad de posiciones activas máxima permitida
input int SupResThreshold = 60;                // Factor de gap para soporte / resistencia 

input group "===PARÁMETROS SWING POR DEFECTO===";
input int deflookback = 50;                     // Número de velas hacia atrás a analizar
input int defstrength = 2;                      // Número de velas a cada lado que deben ser menores/mayores
input int defminDistance = 10;                  // Distancia mínima desde la vela actual

input group "=== CONFIGURACIÓN GRÁFICA ==="
input bool ShowChandelierVisuals = false;      // Mostrar gráficos Chandelier Exit
input bool ShowZLSMAVisuals = false;           // Mostrar gráficos ZLSMA
input bool ShowAOMACDVisuals = false;          // Mostrar gráficos AO_MACD

// Variables para handles de indicadores tradicionales
int emaHandle;
int rsiHandle;
int adxHandle;

// Arrays para datos de indicadores tradicionales
double emaArray[];
double rsiArray[];
double adxArray[];
double diPlusArray[];
double diMinusArray[];

// Variables para Chandelier Exit
int chandelierIndicatorHandle;
double chandelierLongStopArray[];
double chandelierShortStopArray[];
double chandelierBuySignalArray[];
double chandelierSellSignalArray[];

// Variables para ZLSMA
int zlsmaHandle;
double zlsmaArray[];

// Variables para AO_MACD
int aoMacdHandle;
double aoMacdBuySignalArray[];
double aoMacdSellSignalArray[];

// Variables para Chandelier Exit con estado persistente
int prevDirection = 1;
datetime lastTradeTime = 0;

// Nuevas variables para lógica del indicador
datetime g_lastCalculatedTime = 0;
bool g_firstCalculation = true;
datetime g_lastTradeDirection = 0;
int g_lastExecutedDirection = 0;

// Variables globales para conteo
static int g_tickCounter = 0;

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
   // Inicializar el sistema de performance
   SetPerformanceLogging(EnablePerformanceAnalysis);
   if(EnablePerformanceAnalysis) {
      ResetPerformanceStats();
      Print("🔍 Sistema de análisis de performance inicializado");
      Print("📊 Reportes cada ", PerformanceReportInterval, " ticks");
   }
   
   // Configurar magic number para el objeto trade
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   // Inicializar handles según el modo seleccionado
   if(UseChandelierExit)
   {
      // Crear handle para Chandelier Exit
      chandelierIndicatorHandle = iCustom(_Symbol, PERIOD_CURRENT, "Chandelier_Exit", 
                                         CE_ATR_Period, CE_ATR_Multiplier, CE_UseCloseForExtremums,
                                         ShowChandelierVisuals, ShowChandelierVisuals, true);
      
      if(chandelierIndicatorHandle == INVALID_HANDLE) {
         Print("Error al crear handle del indicador Chandelier Exit");
         return(INIT_FAILED);
      }
      
      // Crear handle para ZLSMA
      zlsmaHandle = iCustom(_Symbol, PERIOD_CURRENT, "ZLSMA", ZLSMA_Length, 0, ZLSMA_Source);
      
      if(zlsmaHandle == INVALID_HANDLE) {
         Print("Error al crear handle del indicador ZLSMA");
         return(INIT_FAILED);
      }
      
      // Crear handle para AO_MACD
      aoMacdHandle = iCustom(_Symbol, PERIOD_CURRENT, "AO_MACD", 
                            AO_MACD_FastLength, AO_MACD_SlowLength, AO_MACD_SignalLength, !ShowAOMACDVisuals);
      
      if(aoMacdHandle == INVALID_HANDLE) {
         Print("Error al crear handle del indicador AO_MACD");
         return(INIT_FAILED);
      }
      
      // Configurar arrays para Chandelier Exit
      ArraySetAsSeries(chandelierLongStopArray, true);
      ArraySetAsSeries(chandelierShortStopArray, true);
      ArraySetAsSeries(chandelierBuySignalArray, true);
      ArraySetAsSeries(chandelierSellSignalArray, true);
      
      // Configurar arrays para ZLSMA
      ArraySetAsSeries(zlsmaArray, true);
      
      // Configurar arrays para AO_MACD
      ArraySetAsSeries(aoMacdBuySignalArray, true);
      ArraySetAsSeries(aoMacdSellSignalArray, true);
      
      Print("EA inicializado con modo Chandelier Exit + ZLSMA + AO_MACD");
      Print("- Gráficos Chandelier: ", ShowChandelierVisuals ? "Activados" : "Desactivados");
      Print("- Gráficos ZLSMA: ", ShowZLSMAVisuals ? "Activados" : "Desactivados");
      Print("- Gráficos AO_MACD: ", ShowAOMACDVisuals ? "Activados" : "Desactivados");
   }
   else
   {
      // Inicializar handles de indicadores normales
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
      
      Print("EA inicializado con indicadores tradicionales");
   }
   
   Print("Parámetros configurados:");
   Print("- Modo Chandelier Exit: ", UseChandelierExit ? "Activado" : "Desactivado");
   Print("- Porcentaje tendencia: ", TrendPercentage, "%");
   Print("- Períodos tendencia: ", TrendPeriods);
   Print("- Factor TP: ", TakeProfitFactor);
   Print("- Posiciones activas máx: ", MaxPosActivas);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Liberar handles según el modo usado
   if(UseChandelierExit)
   {
      if(chandelierIndicatorHandle != INVALID_HANDLE) IndicatorRelease(chandelierIndicatorHandle);
      if(zlsmaHandle != INVALID_HANDLE) IndicatorRelease(zlsmaHandle);
      if(aoMacdHandle != INVALID_HANDLE) IndicatorRelease(aoMacdHandle);
   }
   else
   {
      if(emaHandle != INVALID_HANDLE) IndicatorRelease(emaHandle);
      if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
      if(adxHandle != INVALID_HANDLE) IndicatorRelease(adxHandle);
   }
   
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
   if(ValidateActivePos){
      if(CountOpenPositions() > MaxPosActivas) {
         return;
      }
   }

   if(OneTradePerCandle && !IsNewCandle()) {
   return;
   }
   
   if(UseChandelierExit)
   {
      // Modo Chandelier Exit con validaciones adicionales
      if(!UpdateChandelierData()) {
         return;
      }
      
      if(!UpdateZLSMAData()) {
         return;
      }
      
      if(!UpdateAOMACDData()) {
         return;
      }
      
      // Detectar señal de tendencia con Chandelier Exit
      TrendDirection trend = DetectChandelierTrend();
      if(trend == TREND_NONE) {
         return;
      }
      
      // Ejecutar operación basada en señal de Chandelier Exit con validaciones adicionales
      ExecuteChandelierTradeEnhanced(trend);
   }
   else
   {
      // Modo tradicional (original)
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
}

//+------------------------------------------------------------------+
//| Actualizar datos de ZLSMA                                       |
//+------------------------------------------------------------------+
bool UpdateZLSMAData()
{
   if(CopyBuffer(zlsmaHandle, 0, 0, 10, zlsmaArray) <= 0) {
      Print("Error copiando datos ZLSMA");
      return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Actualizar datos de AO_MACD                                     |
//+------------------------------------------------------------------+
bool UpdateAOMACDData()
{
   // Buffer 4: Cross (Circles) - Buy signals (Aqua)
   if(CopyBuffer(aoMacdHandle, 5, 0, CrossLookback + 5, aoMacdBuySignalArray) <= 0) {
      Print("Error copiando datos AO_MACD Buy Signal");
      return false;
   }
   
   // Buffer 5: Cross Color - Sell signals (Red) 
   if(CopyBuffer(aoMacdHandle, 6, 0, CrossLookback + 5, aoMacdSellSignalArray) <= 0) {
      Print("Error copiando datos AO_MACD Sell Signal");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Verificar si la vela actual o las últimas 2 tienen cruce AO_MACD|
//+------------------------------------------------------------------+
bool HasAOMACDCross(TrendDirection direction)
{
   if(CE_AOMACD){   
      for(int i = 0; i <= CrossLookback; i++) {
         if(direction == TREND_BULLISH) {
            // Buscar señal BUY (color aqua)
            if(aoMacdBuySignalArray[i] != EMPTY_VALUE && aoMacdSellSignalArray[i] == 0) {
               Print("Cruce BULLISH AO_MACD encontrado en vela ", i, " valor: ", aoMacdBuySignalArray[i]);
               return true;
            }
         }
         else if(direction == TREND_BEARISH) {
            // Buscar señal SELL (color red)
            if(aoMacdBuySignalArray[i] != EMPTY_VALUE && aoMacdSellSignalArray[i] == 1) {
               Print("Cruce BEARISH AO_MACD encontrado en vela ", i, " valor: ", aoMacdBuySignalArray[i]);
               return true;
            }
         }
      }
      return false;
   }
   else{
      return true;
   }
}

//+------------------------------------------------------------------+
//| Verificar si el cierre está por encima/debajo del ZLSMA         |
//+------------------------------------------------------------------+
bool IsClosePriceValidForZLSMA(TrendDirection direction)
{
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, 3, rates) <= 0) {
      Print("Error copiando datos de precios para ZLSMA");
      return false;
   }
   ArraySetAsSeries(rates, true);
   
   double currentClose = rates[0].close;
   double zlsmaValue = zlsmaArray[0];
   
   if(direction == TREND_BULLISH) {
      bool isValid = currentClose > zlsmaValue;
      Print("Validación ZLSMA BUY: Close=", currentClose, " ZLSMA=", zlsmaValue, " Válido=", isValid);
      return isValid;
   }
   else if(direction == TREND_BEARISH) {
      bool isValid = currentClose < zlsmaValue;
      Print("Validación ZLSMA SELL: Close=", currentClose, " ZLSMA=", zlsmaValue, " Válido=", isValid);
      return isValid;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Actualizar datos de Chandelier Exit                             |
//+------------------------------------------------------------------+
bool UpdateChandelierData()
{
   // Copiar datos del indicador (4 buffers)
   if(CopyBuffer(chandelierIndicatorHandle, 0, 0, 10, chandelierLongStopArray) <= 0) {
      Print("Error copiando LongStop buffer");
      return false;
   }
   
   if(CopyBuffer(chandelierIndicatorHandle, 1, 0, 10, chandelierShortStopArray) <= 0) {
      Print("Error copiando ShortStop buffer");
      return false;
   }
   
   if(CopyBuffer(chandelierIndicatorHandle, 2, 0, 10, chandelierBuySignalArray) <= 0) {
      Print("Error copiando BuySignal buffer");
      return false;
   }
   
   if(CopyBuffer(chandelierIndicatorHandle, 3, 0, 10, chandelierSellSignalArray) <= 0) {
      Print("Error copiando SellSignal buffer");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Calcular Chandelier Exit y detectar cambio de tendencia         |
//+------------------------------------------------------------------+
TrendDirection DetectChandelierTrend()
{
   if(ArraySize(chandelierBuySignalArray) < 2 || ArraySize(chandelierSellSignalArray) < 2) {
      return TREND_NONE;
   }
   
   // Método más directo: solo verificar si hay una nueva señal
   bool newBuySignal = (chandelierBuySignalArray[0] != EMPTY_VALUE && 
                        chandelierBuySignalArray[1] == EMPTY_VALUE);
                        
   bool newSellSignal = (chandelierSellSignalArray[0] != EMPTY_VALUE && 
                         chandelierSellSignalArray[1] == EMPTY_VALUE);
   
   if(newBuySignal) {
      Print("🔵 NUEVA SEÑAL BUY - Valor: ", DoubleToString(chandelierBuySignalArray[0], _Digits));
      return TREND_BULLISH;
   }
   
   if(newSellSignal) {
      Print("🔴 NUEVA SEÑAL SELL - Valor: ", DoubleToString(chandelierSellSignalArray[0], _Digits));
      return TREND_BEARISH;
   }
   
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| Ejecutar operación con validaciones adicionales (Enhanced)      |
//+------------------------------------------------------------------+
void ExecuteChandelierTradeEnhanced(TrendDirection trend)
{
   // Evitar múltiples operaciones en la misma dirección
   if(trend == TREND_BULLISH && g_lastExecutedDirection == 1) {
      Print("⚠️ Ya hay operación BUY ejecutada en esta tendencia");
      return;
   }
   if(trend == TREND_BEARISH && g_lastExecutedDirection == -1) {
      Print("⚠️ Ya hay operación SELL ejecutada en esta tendencia");
      return;
   }
   
   // VALIDACIÓN 1: Verificar si la vela es fuerte
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, CandleAveragePeriods + 5, rates) <= 0) {
      Print("Error copiando datos para validación de vela fuerte");
      return;
   }
   ArraySetAsSeries(rates, true);
   
   if(!IsCandleStrong(1, rates)) {
      Print("❌ Validación 1 FALLIDA: La vela no es suficientemente fuerte");
      return;
   }
   Print("✅ Validación 1 EXITOSA: Vela fuerte detectada");
   
   // VALIDACIÓN 2: Verificar posición del cierre respecto al ZLSMA
   if(!IsClosePriceValidForZLSMA(trend)) {
      Print("❌ Validación 2 FALLIDA: Cierre no válido respecto a ZLSMA");
      return;
   }
   Print("✅ Validación 2 EXITOSA: Cierre válido respecto a ZLSMA");
   
   // VALIDACIÓN 3: Verificar cruce de AO_MACD en las últimas velas
   if(!HasAOMACDCross(trend)) {
      Print("❌ Validación 3 FALLIDA: No hay cruce de AO_MACD en el sentido correcto");
      return;
   }
   Print("✅ Validación 3 EXITOSA: Cruce de AO_MACD confirmado");
   
   // Si todas las validaciones pasan, ejecutar la operación
   Print("🚀 TODAS LAS VALIDACIONES EXITOSAS - Ejecutando operación");
   
   if(trend == TREND_BULLISH) {
      if(ExecuteBuyTrade()) {
         g_lastExecutedDirection = 1;
         g_lastTradeDirection = iTime(_Symbol, PERIOD_CURRENT, 0);
      }
   }
   else if(trend == TREND_BEARISH) {
      if(ExecuteSellTrade()) {
         g_lastExecutedDirection = -1;
         g_lastTradeDirection = iTime(_Symbol, PERIOD_CURRENT, 0);
      }
   }
}

//+------------------------------------------------------------------+
//| Ejecutar operación basada en señal de Chandelier Exit           |
//+------------------------------------------------------------------+
void ExecuteChandelierTrade(TrendDirection trend)
{
   // Evitar múltiples operaciones en la misma dirección
   if(trend == TREND_BULLISH && g_lastExecutedDirection == 1) {
      Print("⚠️ Ya hay operación BUY ejecutada en esta tendencia");
      return;
   }
   if(trend == TREND_BEARISH && g_lastExecutedDirection == -1) {
      Print("⚠️ Ya hay operación SELL ejecutada en esta tendencia");
      return;
   }
   
   if(trend == TREND_BULLISH) {
      if(ExecuteBuyTrade()) {
         g_lastExecutedDirection = 1;
         g_lastTradeDirection = iTime(_Symbol, PERIOD_CURRENT, 0);
      }
   }
   else if(trend == TREND_BEARISH) {
      if(ExecuteSellTrade()) {
         g_lastExecutedDirection = -1;
         g_lastTradeDirection = iTime(_Symbol, PERIOD_CURRENT, 0);
      }
   }
}

//+------------------------------------------------------------------+
//| Verificar si es sesión de trading válida                        |
//+------------------------------------------------------------------+
bool IsValidTradingSession()
{
  if(!ValidateSchedule){
      return true;
   }
   
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
//| Actualizar datos de indicadores (modo tradicional)              |
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
   
      
   // Determinar tendencia
   if(indicio1Alcista) {
      return TREND_BULLISH;
   }
   else if(indicio1Bajista) {
      return TREND_BEARISH;
   }
   
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| Evaluar RSI para determinar condición de mercado                |
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
//| Verificar si ADX es suficientemente fuerte                      |
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
//| Ejecutar operación según las condiciones                        |
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
      
   if (!UseChandelierExit){
      if(i >= ArraySize(rsiArray)) return false;
      double rsiValue = rsiArray[i];
   }
   
   double openPrice = rates[i].open;
   double closePrice = rates[i].close;
   double highPrice = rates[i].high;
   double lowPrice = rates[i].low;
   
   Print("🔵 Ejecutando BUY Trade - Close: ", closePrice, " Open: ", openPrice);
   
    bool canExecute = false;
      
    if(UseChandelierExit) {
       canExecute = true; // Chandelier Exit ya validó la señal
    }
    else {
       // Modo tradicional: validar vela verde y fuerte
       canExecute = (closePrice > openPrice) && IsCandleStrong(i, rates);
    }         
      
    if(canExecute) {
         double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         
         double stopLoss, entryReference, risk;
         
         if(UseChandelierExit) {
            // Para BUY: usar LongStop como referencia
            double swingLow = (chandelierLongStopArray[0] != EMPTY_VALUE) ? 
                              chandelierLongStopArray[0] - (10 * _Point) : 
                              FindSwingLow(CE_lookback, CE_strength, CE_minDistance) - (10 * _Point);
            
            if(swingLow <= 0) {
               Print("No se pudo calcular stop loss para BUY");
               return false;
            }
            stopLoss = swingLow;
            entryReference = closePrice;
            risk = entryReference - stopLoss;
         }
         else {
            // Modo tradicional
            stopLoss = lowPrice;
            entryReference = closePrice;
            risk = entryReference - stopLoss;
            // Validar riesgo mínimo
            double minRisk = _Point * 50; // 50 puntos mínimo
            if(risk < minRisk) {
               stopLoss = entryReference - minRisk;
               risk = minRisk;
               Print("⚠️ Riesgo ajustado a mínimo: ", DoubleToString(risk, _Digits));
            }
         }
       
         double riskRewardRatio = TakeProfitFactor;
         double takeProfit = entryReference + (risk * riskRewardRatio);
         
         Print("💰 Risk: ", DoubleToString(risk, _Digits), " SL: ", DoubleToString(stopLoss, _Digits));
                  
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
         request.type = ORDER_TYPE_BUY;
         request.price = currentAsk;
         request.sl = stopLoss;
         request.tp = takeProfit;
         request.deviation = Slippage;
         request.magic = MagicNumber;
         request.comment = StringFormat("Buy Market: Price=%.5f SL=%.5f TP=%.5f", 
                                        currentAsk, stopLoss, takeProfit);
         
         if(OrderSend(request, result)) {
             if(result.retcode == TRADE_RETCODE_DONE) {
                 lastTradeTime = iTime(_Symbol, PERIOD_CURRENT, 0);
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
             else {
                 Print("❌ Error en ejecución: ", result.retcode);
                 return false;
             }
         }
         else {
             Print("❌ Error enviando orden: ", GetLastError());
             return false;
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
      
   if (!UseChandelierExit){
      if(i >= ArraySize(rsiArray)) return false;
      double rsiValue = rsiArray[i];
   }
   
   double openPrice = rates[i].open;
   double closePrice = rates[i].close;
   double highPrice = rates[i].high;
   double lowPrice = rates[i].low;
   
   Print("🔴 Ejecutando SELL Trade - Close: ", closePrice, " Open: ", openPrice);

   bool canExecute = false;
   
   if(UseChandelierExit) {
      canExecute = true; // Chandelier Exit ya validó la señal
   }
   else {
      // Modo tradicional: validar vela roja y fuerte
      canExecute = (closePrice < openPrice) && IsCandleStrong(i, rates);
   }
   
   if(canExecute) {
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      double stopLoss, entryReference, risk;
      
      if(UseChandelierExit) {
         // Para SELL: usar ShortStop como referencia
         double swingHigh = (chandelierShortStopArray[0] != EMPTY_VALUE) ? 
                            chandelierShortStopArray[0] + (10 * _Point) : 
                            FindSwingHigh(CE_lookback, CE_strength, CE_minDistance) + (10 * _Point);
         
         if(swingHigh <= 0) {
            Print("No se pudo calcular stop loss para SELL");
            return false;
         }
         stopLoss = swingHigh;
         entryReference = closePrice;
         risk = stopLoss - entryReference;
      }
      else {
         // Modo tradicional
         stopLoss = highPrice;
         entryReference = closePrice;
         risk = stopLoss - entryReference;
         // Validar riesgo mínimo
         double minRisk = _Point * 50;
         if(risk < minRisk) {
            stopLoss = entryReference + minRisk;
            risk = minRisk;
            Print("⚠️ Riesgo ajustado a mínimo: ", DoubleToString(risk, _Digits));
         }
      }
      
      double riskRewardRatio = TakeProfitFactor;
      double takeProfit = entryReference - (risk * riskRewardRatio);
      
      Print("💰 Risk: ", DoubleToString(risk, _Digits), " SL: ", DoubleToString(stopLoss, _Digits));      
        
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
      request.type = ORDER_TYPE_SELL;
      request.price = currentBid;
      request.sl = stopLoss;
      request.tp = takeProfit;
      request.deviation = Slippage;
      request.magic = MagicNumber;
      request.comment = StringFormat("Sell Market: Price=%.5f SL=%.5f TP=%.5f", 
                                     currentBid, stopLoss, takeProfit);
      
      if(OrderSend(request, result)) {
          if(result.retcode == TRADE_RETCODE_DONE) {
              lastTradeTime = iTime(_Symbol, PERIOD_CURRENT, 0);
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
          else {
              Print("❌ Error en ejecución: ", result.retcode);
              return false;
          }
      }
      else {
          Print("❌ Error enviando orden: ", GetLastError());
          return false;
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
   Print("Current body: ", currentCandleBody, " Threshold: ", threshold, " Points*10: ", _Point*10);
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
//| Verificar si es una nueva vela                                  |
//+------------------------------------------------------------------+
bool IsNewCandle()
{
   datetime currentTime = iTime(_Symbol, PERIOD_CURRENT, 0);
   
   return (lastTradeTime != currentTime);  // Just check, don't update
}

//+------------------------------------------------------------------+
//| Encontrar el último Swing High                                   |
//+------------------------------------------------------------------+
double FindSwingHigh(int lookback, int strength, int minDistance)
{
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, lookback + strength, rates) <= 0) {
      Print("Error copiando datos para Swing High");
      return 0;
   }
   
   ArraySetAsSeries(rates, true);
   
   for(int i = strength; i < lookback - strength; i++)
   {
      // Saltar si está muy cerca del precio actual
      if(i < minDistance) continue;
      
      bool isSwingHigh = true;
      double currentHigh = rates[i].high;
      
      // Verificar que sea más alto que 'strength' velas a cada lado
      for(int j = 1; j <= strength; j++)
      {
         // Verificar velas anteriores
         if(currentHigh <= rates[i - j].high) {
            isSwingHigh = false;
            break;
         }
         
         // Verificar velas posteriores
         if(currentHigh <= rates[i + j].high) {
            isSwingHigh = false;
            break;
         }
      }
      
      if(isSwingHigh) {
         Print("Swing High encontrado: ", DoubleToString(currentHigh, _Digits), 
               " en vela ", i, " (", TimeToString(rates[i].time), ")");
         return currentHigh;
      }
   }
   
   Print("No se encontró Swing High válido");
   return 0;
}

//+------------------------------------------------------------------+
//| Encontrar el último Swing Low                                    |
//+------------------------------------------------------------------+
double FindSwingLow(int lookback = 50, int strength = 2, int minDistance = 10)
{
   MqlRates rates[];
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, lookback + strength, rates) <= 0) {
      Print("Error copiando datos para Swing Low");
      return 0;
   }
   
   ArraySetAsSeries(rates, true);
   
   for(int i = strength; i < lookback - strength; i++)
   {
      // Saltar si está muy cerca del precio actual
      if(i < minDistance) continue;
      
      bool isSwingLow = true;
      double currentLow = rates[i].low;
      
      // Verificar que sea más bajo que 'strength' velas a cada lado
      for(int j = 1; j <= strength; j++)
      {
         // Verificar velas anteriores
         if(currentLow >= rates[i - j].low) {
            isSwingLow = false;
            break;
         }
         
         // Verificar velas posteriores
         if(currentLow >= rates[i + j].low) {
            isSwingLow = false;
            break;
         }
      }
      
      if(isSwingLow) {
         Print("Swing Low encontrado: ", DoubleToString(currentLow, _Digits), 
               " en vela ", i, " (", TimeToString(rates[i].time), ")");
         return currentLow;
      }
   }
   
   Print("No se encontró Swing Low válido");
   return 0;
}

//+------------------------------------------------------------------+
//| Debug Info                                                       |
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