//+------------------------------------------------------------------+
//|                      EA Universal para Múltiples Tipos de Modelo |
//+------------------------------------------------------------------+

#property copyright "Multi-Model Trading System v2.1"
#property version   "2.10"
#property strict

// Enumeración para tipos de modelo (DEBE ir antes de los inputs)
enum ENUM_MODEL_TYPE
{
   MODEL_AUTO,          // Detección automática
   MODEL_HYBRID,        // Modelo híbrido Neural-SVM
   MODEL_NEURAL_SVM,    // Red neuronal con comportamiento SVM
   MODEL_NEURAL_STD,    // Red neuronal estándar
   MODEL_MIXED          // Mejor modelo disponible
};

// Parámetros de entrada
input group "=== Configuración Básica ==="
input double LotSize = 0.1;                    // Tamaño del lote
input int MagicNumber = 12345;                 // Número mágico
input double StopLoss = 50;                    // Stop Loss en pips
input double TakeProfit = 100;                 // Take Profit en pips
input double MinConfidence = 0.65;             // Confianza mínima

input group "=== Configuración de Modelo ==="
input ENUM_MODEL_TYPE ModelTypePreference = MODEL_AUTO;  // Preferencia de modelo
input bool ShowModelInfo = true;              // Mostrar info del modelo

input group "=== Configuración Avanzada ==="
input bool AutoMode = true;                    // Detectar modo automáticamente
input int MaxSpread = 3;                       // Spread máximo
input bool UseTrailingStop = false;           // Usar trailing stop
input double TrailingDistance = 30;           // Distancia trailing

// Estructura de señal
struct SignalData
{
   int signal;
   double confidence;
   double price;
   datetime timestamp;
   string symbol;
   string model_type;
   
   // Constructor por defecto
   SignalData()
   {
      signal = 0;
      confidence = 0.0;
      price = 0.0;
      timestamp = 0;
      symbol = "";
      model_type = "";
   }
   
   // Constructor de copia
   SignalData(const SignalData& other)
   {
      signal = other.signal;
      confidence = other.confidence;
      price = other.price;
      timestamp = other.timestamp;
      symbol = other.symbol;
      model_type = other.model_type;
   }
};

// Variables globales
bool g_isBacktest = false;
bool g_isLive = false;
string g_signalFile = "";
string g_backtestFile = "";
string g_detectedModelType = "";
datetime g_lastSignalTime = 0;

//+------------------------------------------------------------------+
//| Inicialización                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== MULTI-MODEL TRADER v2.1 INICIANDO ===");
   
   // Configurar archivos
   string symbol = StringSubstr(Symbol(), 0, 6);
   StringToLower(symbol);
   g_signalFile = "signals_" + symbol + ".json";
   g_backtestFile = "real_backtest_signals_" + symbol + ".json";
   
   // Detectar tipo de modelo disponible
   DetectAvailableModel();
   
   // Detectar modo de operación
   g_isBacktest = MQLInfoInteger(MQL_TESTER);
   
   if(AutoMode)
   {
      if(g_isBacktest || FileIsExist(g_backtestFile))
      {
         Print("Modo: BACKTESTING");
         return InitBacktestMode();
      }
      else
      {
         Print("Modo: TRADING EN VIVO");
         return InitLiveMode();
      }
   }
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Detectar modelo disponible                                      |
//+------------------------------------------------------------------+
void DetectAvailableModel()
{
   string symbol = StringSubstr(Symbol(), 0, 6);
   StringToLower(symbol);
   
   // Archivos de modelo a buscar (en orden de prioridad)
   string modelFiles[] = {
      "models/" + symbol + "_hybrid.pth",
      "models/" + symbol + "_neural_svm.pth", 
      "models/" + symbol + "_neural_standard.pth",
      "models/" + symbol + ".pth"  // Legacy
   };
   
   string modelTypes[] = {
      "hybrid",
      "neural_svm",
      "neural_standard", 
      "legacy"
   };
   
   // Buscar modelo según preferencia del usuario
   if(ModelTypePreference != MODEL_AUTO)
   {
      string preferredFile = "";
      string preferredType = "";
      
      switch(ModelTypePreference)
      {
         case MODEL_HYBRID:
            preferredFile = "models/" + symbol + "_hybrid.pth";
            preferredType = "hybrid";
            break;
         case MODEL_NEURAL_SVM:
            preferredFile = "models/" + symbol + "_neural_svm.pth";
            preferredType = "neural_svm";
            break;
         case MODEL_NEURAL_STD:
            preferredFile = "models/" + symbol + "_neural_standard.pth";
            preferredType = "neural_standard";
            break;
         case MODEL_MIXED:
            preferredFile = "";
            preferredType = "mixed";
            break;
      }
      
      if(StringLen(preferredFile) > 0 && FileIsExist(preferredFile))
      {
         g_detectedModelType = preferredType;
         Print("Modelo preferido encontrado: " + preferredType);
         return;
      }
   }
   
   // Búsqueda automática en orden de prioridad
   for(int i = 0; i < ArraySize(modelFiles); i++)
   {
      if(FileIsExist(modelFiles[i]))
      {
         g_detectedModelType = modelTypes[i];
         Print("Modelo detectado: " + modelTypes[i] + " (" + modelFiles[i] + ")");
         
         if(ShowModelInfo)
         {
            ShowModelTypeInfo(modelTypes[i]);
         }
         
         return;
      }
   }
   
   // No se encontró ningún modelo
   g_detectedModelType = "none";
   Print("ADVERTENCIA: No se encontró ningún modelo para " + Symbol());
   Print("   Asegúrate de entrenar modelos antes de usar el EA");
}

//+------------------------------------------------------------------+
//| Mostrar información del tipo de modelo                         |
//+------------------------------------------------------------------+
void ShowModelTypeInfo(string modelType)
{
   Print("=== INFORMACIÓN DEL MODELO ===");
   
   if(modelType == "hybrid")
   {
      Print("Tipo: Modelo Híbrido Neural-SVM");
      Print("Descripción: Red neuronal extrae características -> SVM clasifica");
      Print("Ventajas: Máximo rendimiento, combina fortalezas de ambas técnicas");
      Print("Recomendado para: Trading en vivo de alta precisión");
   }
   else if(modelType == "neural_svm")
   {
      Print("Tipo: Red Neuronal con Comportamiento SVM");
      Print("Descripción: Red neuronal con hinge loss tipo SVM");
      Print("Ventajas: Arquitectura neuronal pura con lógica SVM");
      Print("Recomendado para: Balance entre simplicidad y rendimiento");
   }
   else if(modelType == "neural_standard")
   {
      Print("Tipo: Red Neuronal Estándar");
      Print("Descripción: Red neuronal tradicional con cross-entropy");
      Print("Ventajas: Simplicidad, velocidad de ejecución");
      Print("Recomendado para: Backtesting rápido y comparaciones");
   }
   else if(modelType == "legacy")
   {
      Print("Tipo: Modelo Legacy");
      Print("Descripción: Formato anterior detectado automáticamente");
      Print("Recomendación: Considera reentrenar con nuevos tipos");
   }
   
   Print("==============================");
}

//+------------------------------------------------------------------+
//| Inicializar modo backtesting                                    |
//+------------------------------------------------------------------+
int InitBacktestMode()
{
   if(!FileIsExist(g_backtestFile))
   {
      Alert("Archivo de backtesting no encontrado: " + g_backtestFile);
      return INIT_FAILED;
   }
   
   Print("Archivo de backtesting: " + g_backtestFile);
   Print("Modelo utilizado: " + g_detectedModelType);
   g_isBacktest = true;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Inicializar modo en vivo                                        |
//+------------------------------------------------------------------+
int InitLiveMode()
{
   if(g_detectedModelType == "none")
   {
      Alert("No hay modelo disponible para trading en vivo");
      return INIT_FAILED;
   }
   
   Print("Archivo de señales: " + g_signalFile);
   Print("Modelo utilizado: " + g_detectedModelType);
   g_isLive = true;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick principal                                                |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_isBacktest)
   {
      ProcessBacktest();
   }
   else if(g_isLive)
   {
      ProcessLiveTrading();
   }
   
   if(UseTrailingStop)
   {
      UpdateTrailingStops();
   }
}

//+------------------------------------------------------------------+
//| Procesar trading en vivo                                        |
//+------------------------------------------------------------------+
void ProcessLiveTrading()
{
   static datetime lastCheck = 0;
   datetime currentTime = TimeCurrent();
   
   // Verificar cada minuto
   if(currentTime - lastCheck < 60)
      return;
   
   lastCheck = currentTime;
   
   // Leer señal
   SignalData signal;
   if(ReadLiveSignal(signal))
   {
      if(IsValidSignal(signal))
      {
         ExecuteSignal(signal);
      }
   }
}

//+------------------------------------------------------------------+
//| Procesar backtesting                                            |
//+------------------------------------------------------------------+
void ProcessBacktest()
{
   static int signalIndex = 0;
   static SignalData signals[];
   static bool signalsLoaded = false;
   
   // Cargar señales una sola vez
   if(!signalsLoaded)
   {
      int count = LoadBacktestSignals(signals);
      if(count == 0)
      {
         Print("No se pudieron cargar señales de backtesting");
         return;
      }
      signalsLoaded = true;
      Print("Cargadas " + IntegerToString(count) + " señales (modelo: " + g_detectedModelType + ")");
   }
   
   // Procesar señales por tiempo
   datetime currentTime = TimeCurrent();
   
   while(signalIndex < ArraySize(signals))
   {
      SignalData signal = signals[signalIndex];
      
      // Verificar si es tiempo de ejecutar esta señal
      int timeDiff = (int)MathAbs(currentTime - signal.timestamp);
      
      if(timeDiff <= 900) // 15 minutos de tolerancia
      {
         if(IsValidSignal(signal))
         {
            ExecuteSignal(signal);
         }
         signalIndex++;
         return;
      }
      
      if(signal.timestamp < currentTime - 900)
      {
         signalIndex++;
      }
      else
      {
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Leer señal de archivo en vivo                                   |
//+------------------------------------------------------------------+
bool ReadLiveSignal(SignalData &signal)
{
   if(!FileIsExist(g_signalFile))
      return false;
   
   int file = FileOpen(g_signalFile, FILE_READ | FILE_TXT);
   if(file == INVALID_HANDLE)
      return false;
   
   string content = "";
   while(!FileIsEnding(file))
   {
      content += FileReadString(file);
   }
   FileClose(file);
   
   return ParseSignalJSON(content, signal);
}

//+------------------------------------------------------------------+
//| Parsear JSON de señal mejorado                                 |
//+------------------------------------------------------------------+
bool ParseSignalJSON(string json, SignalData &signal)
{
   if(StringLen(json) == 0)
      return false;
   
   // Extraer valores básicos
   signal.signal = ExtractIntValue(json, "signal");
   signal.confidence = ExtractDoubleValue(json, "confidence");
   signal.price = ExtractDoubleValue(json, "price");
   signal.timestamp = TimeCurrent();
   signal.model_type = ExtractStringValue(json, "model_type");
   
   // Validar tipo de modelo con el detectado
   if(StringLen(signal.model_type) > 0 && signal.model_type != g_detectedModelType)
   {
      if(g_detectedModelType != "legacy") // Legacy puede ser cualquiera
      {
         Print("Advertencia: Tipo de modelo en señal (" + signal.model_type + 
               ") difiere del detectado (" + g_detectedModelType + ")");
      }
   }
   
   return (signal.signal != 0 && signal.confidence > 0);
}

//+------------------------------------------------------------------+
//| Cargar señales de backtesting mejorado                         |
//+------------------------------------------------------------------+
int LoadBacktestSignals(SignalData &signals[])
{
   int file = FileOpen(g_backtestFile, FILE_READ | FILE_TXT);
   if(file == INVALID_HANDLE)
      return 0;
   
   string content = "";
   while(!FileIsEnding(file))
   {
      content += FileReadString(file);
   }
   FileClose(file);
   
   // Contar objetos JSON
   int count = 0;
   int pos = 0;
   while((pos = StringFind(content, "{", pos + 1)) >= 0)
   {
      count++;
   }
   
   if(count == 0)
      return 0;
   
   ArrayResize(signals, count);
   
   // Parsear cada señal
   pos = 0;
   int index = 0;
   string detectedModelTypes = "";
   
   while(index < count && pos < StringLen(content))
   {
      int start = StringFind(content, "{", pos);
      int end = StringFind(content, "}", start);
      
      if(start < 0 || end < 0)
         break;
      
      string signalJson = StringSubstr(content, start, end - start + 1);
      
      signals[index].signal = ExtractIntValue(signalJson, "signal");
      signals[index].confidence = ExtractDoubleValue(signalJson, "confidence");
      signals[index].price = ExtractDoubleValue(signalJson, "price");
      signals[index].timestamp = (datetime)ExtractIntValue(signalJson, "datetime_mt5");
      signals[index].model_type = ExtractStringValue(signalJson, "model_type");
      
      // Recopilar tipos de modelo encontrados
      if(StringLen(signals[index].model_type) > 0)
      {
         if(StringFind(detectedModelTypes, signals[index].model_type) < 0)
         {
            if(StringLen(detectedModelTypes) > 0) detectedModelTypes += ", ";
            detectedModelTypes += signals[index].model_type;
         }
      }
      
      pos = end + 1;
      index++;
   }
   
   if(StringLen(detectedModelTypes) > 0)
   {
      Print("Tipos de modelo en señales de backtesting: " + detectedModelTypes);
   }
   
   return index;
}

//+------------------------------------------------------------------+
//| Validar señal mejorada                                         |
//+------------------------------------------------------------------+
bool IsValidSignal(const SignalData &signal)
{
   // Verificar confianza
   if(signal.confidence < MinConfidence)
      return false;
   
   // Verificar spread
   double spread = (SymbolInfoDouble(Symbol(), SYMBOL_ASK) - 
                   SymbolInfoDouble(Symbol(), SYMBOL_BID)) / 
                   SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   if(spread > MaxSpread)
      return false;
   
   // Evitar señales duplicadas en vivo
   if(g_isLive)
   {
      datetime currentTime = TimeCurrent();
      if(currentTime - g_lastSignalTime < 300) // 5 minutos
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Ejecutar señal mejorada                                        |
//+------------------------------------------------------------------+
void ExecuteSignal(const SignalData &signal)
{
   string signalType = (signal.signal == 1) ? "BUY" : "SELL";
   string modelInfo = "";
   
   if(StringLen(signal.model_type) > 0)
   {
      modelInfo = " [" + signal.model_type + "]";
   }
   
   Print("Ejecutando señal: " + signalType + " (conf: " + 
         DoubleToString(signal.confidence, 3) + ")" + modelInfo);
   
   // Cerrar posiciones opuestas
   CloseOppositePositions(signal.signal);
   
   // Abrir nueva posición
   if(signal.signal == 1)
      OpenBuyPosition();
   else if(signal.signal == -1)
      OpenSellPosition();
   
   g_lastSignalTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Abrir posición de compra                                       |
//+------------------------------------------------------------------+
void OpenBuyPosition()
{
   if(HasPositionType(POSITION_TYPE_BUY))
      return;
   
   double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   
   double sl = NormalizeDouble(ask - StopLoss * point * 10, digits);
   double tp = NormalizeDouble(ask + TakeProfit * point * 10, digits);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = LotSize;
   request.type = ORDER_TYPE_BUY;
   request.price = ask;
   request.sl = sl;
   request.tp = tp;
   request.magic = MagicNumber;
   request.comment = "MultiModel_BUY_" + g_detectedModelType;
   
   bool success = OrderSend(request, result);
   if(success && result.retcode == TRADE_RETCODE_DONE)
   {
      Print("BUY abierto - Ticket: " + IntegerToString(result.order) + 
            " [" + g_detectedModelType + "]");
   }
   else
   {
      Print("Error BUY: " + IntegerToString(result.retcode) + " - " + result.comment);
   }
}

//+------------------------------------------------------------------+
//| Abrir posición de venta                                        |
//+------------------------------------------------------------------+
void OpenSellPosition()
{
   if(HasPositionType(POSITION_TYPE_SELL))
      return;
   
   double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
   
   double sl = NormalizeDouble(bid + StopLoss * point * 10, digits);
   double tp = NormalizeDouble(bid - TakeProfit * point * 10, digits);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = LotSize;
   request.type = ORDER_TYPE_SELL;
   request.price = bid;
   request.sl = sl;
   request.tp = tp;
   request.magic = MagicNumber;
   request.comment = "MultiModel_SELL_" + g_detectedModelType;
   
   bool success = OrderSend(request, result);
   if(success && result.retcode == TRADE_RETCODE_DONE)
   {
      Print("SELL abierto - Ticket: " + IntegerToString(result.order) + 
            " [" + g_detectedModelType + "]");
   }
   else
   {
      Print("Error SELL: " + IntegerToString(result.retcode) + " - " + result.comment);
   }
}

//+------------------------------------------------------------------+
//| Verificar si existe posición de tipo específico                |
//+------------------------------------------------------------------+
bool HasPositionType(ENUM_POSITION_TYPE type)
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == Symbol())
      {
         if(PositionSelect(Symbol()))
         {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
               PositionGetInteger(POSITION_TYPE) == type)
            {
               return true;
            }
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Cerrar posiciones opuestas                                     |
//+------------------------------------------------------------------+
void CloseOppositePositions(int newSignal)
{
   ENUM_POSITION_TYPE oppositeType = (newSignal == 1) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == Symbol())
      {
         if(PositionSelect(Symbol()))
         {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
               PositionGetInteger(POSITION_TYPE) == oppositeType)
            {
               ulong ticket = PositionGetInteger(POSITION_TICKET);
               ClosePositionByTicket(ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cerrar posición por ticket                                     |
//+------------------------------------------------------------------+
void ClosePositionByTicket(ulong ticket)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   if(!PositionSelectByTicket(ticket))
      return;
   
   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = Symbol();
   request.volume = PositionGetDouble(POSITION_VOLUME);
   request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                  ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ?
                   SymbolInfoDouble(Symbol(), SYMBOL_BID) :
                   SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   request.magic = MagicNumber;
   
   OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Actualizar trailing stops                                      |
//+------------------------------------------------------------------+
void UpdateTrailingStops()
{
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetSymbol(i) == Symbol())
      {
         if(PositionSelect(Symbol()))
         {
            if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
               double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
               double trailingPips = TrailingDistance * point * 10;
               
               if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
               {
                  double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
                  double currentSL = PositionGetDouble(POSITION_SL);
                  double newSL = currentPrice - trailingPips;
                  
                  if(newSL > currentSL + point)
                  {
                     ModifyPosition(PositionGetInteger(POSITION_TICKET), newSL, 0);
                  }
               }
               else
               {
                  double currentPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
                  double currentSL = PositionGetDouble(POSITION_SL);
                  double newSL = currentPrice + trailingPips;
                  
                  if(newSL < currentSL - point)
                  {
                     ModifyPosition(PositionGetInteger(POSITION_TICKET), newSL, 0);
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modificar posición                                             |
//+------------------------------------------------------------------+
void ModifyPosition(ulong ticket, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.sl = sl;
   request.tp = tp;
   
   OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Funciones auxiliares de parsing                                |
//+------------------------------------------------------------------+
int ExtractIntValue(string json, string key)
{
   string searchKey = "\"" + key + "\":";
   int keyPos = StringFind(json, searchKey);
   if(keyPos < 0) return 0;
   
   keyPos += StringLen(searchKey);
   string valueStr = "";
   
   for(int i = keyPos; i < StringLen(json); i++)
   {
      string ch = StringSubstr(json, i, 1);
      if(ch == "," || ch == "}" || ch == "]") break;
      if(ch != " " && ch != "\"") valueStr += ch;
   }
   
   return (int)StringToInteger(valueStr);
}

double ExtractDoubleValue(string json, string key)
{
   string searchKey = "\"" + key + "\":";
   int keyPos = StringFind(json, searchKey);
   if(keyPos < 0) return 0;
   
   keyPos += StringLen(searchKey);
   string valueStr = "";
   
   for(int i = keyPos; i < StringLen(json); i++)
   {
      string ch = StringSubstr(json, i, 1);
      if(ch == "," || ch == "}" || ch == "]") break;
      if(ch != " " && ch != "\"") valueStr += ch;
   }
   
   return StringToDouble(valueStr);
}

string ExtractStringValue(string json, string key)
{
   string searchKey = "\"" + key + "\":\"";
   int keyPos = StringFind(json, searchKey);
   if(keyPos < 0) return "";
   
   keyPos += StringLen(searchKey);
   int endPos = StringFind(json, "\"", keyPos);
   
   if(endPos < 0) return "";
   
   return StringSubstr(json, keyPos, endPos - keyPos);
}

//+------------------------------------------------------------------+
//| Desinicialización                                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== MULTI-MODEL TRADER v2.1 FINALIZADO ===");
   Print("Modelo utilizado: " + g_detectedModelType);
   Print("Motivo: " + IntegerToString(reason));
}