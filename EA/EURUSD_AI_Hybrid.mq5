//+------------------------------------------------------------------+
//|                                    EURUSD_AI_Hybrid.mq5        |
//|                                                                  |
//|        EA Híbrido: Trading en Vivo + Backtesting Automático     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
CTrade trade;
CPositionInfo positionInfo;
#property copyright "AI Trading System - Hybrid Version"
#property version   "3.00"
#property strict
#import "shell32.dll" 
int ShellExecuteW(int hwnd,string operation,string file,string parameters,string directory,int showCmd);
#import 
#define SW_SHOWNORMAL       1


// Parámetros de entrada
input group "=== Configuración Principal ==="
input double LotSize = 0.01;                    // Tamaño del lote
input double risk = 0.01;                       // Riesgo por operación
input double comision_f = 0.00007;              // Comisión broker
input double unid_x_lote = 100000;              // Unidades por lote
input int MagicNumber = 2610446;                 // Número mágico
input double StopLoss = 5;                    // Stop Loss en pips
input double TakeProfit = 100;                 // Take Profit en pips
input double MinConfidence = 0.6;             // Confianza mínima para operar
//input double alpha= 0.1;                       // Factor SL / TP
input bool closeopposite = false;               // Cerrar operaciones contrarias
input int MaxPosActivas = 3;                   // Cantidad de posiciones activas máxima permitida
input bool invert = true;                       // Invertir lógica

input group "=== Señales ==="
input bool AutoDetectMode = true;              // Detectar modo automáticamente

input group "=== Configuración de Backtesting ==="
input bool UseTimeBasedSignals = true;        // Usar señales basadas en tiempo
input int TicksPerSignal = 50;                // Ticks entre señales (modo secuencial)
input int TimePerSignal = 300;                // Tiempo entre señales

input group "=== Configuración Avanzada ==="
input bool DebugMode = true;                  // Modo debug
input double MaxSpread = 3;                      // Spread máximo permitido
input double MaxSEURUSD = 2;                      // Spread máximo EURUDS
input double MaxSBTCUSD = 100;                      // Spread máximo BTCUSD
input double MaxSUSDJPY = 2.5;                      // Spread máximo USDJPY
input double MaxSXAUUSD = 50;                      // Spread máximo XAUUSD
input double MaxSGBPUSD = 2;                      // Spread máximo GBPUSD
input double MaxSNDAQ100 = 10;                      // Spread máximo NDAQ 100

input bool UseTrailingStop = false;          // Usar trailing stop
input double TrailingStop = 200;   // Distancia inicial en puntos
input double TrailingStep = 50;    // Paso mínimo para mover el stop en puntos

input group "=== Configuración contingencia ==="
input double LotStep      = 0.01;   // incremento de lote después de cada pérdida
input double MaxLot       = 0.05;   // límite máximo de lote permitido

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
input int ny_friOpen = 0;               // Incremento hora inicio Nueva York Viernes
input int lo_monOpen = 0;                 // Incremento hora inicio Londres Lunes
input int lo_tueOpen = 0;                // Incremento hora inicio Londres Martes
input int lo_wedOpen = 0;                // Incremento hora inicio Londres Miércoles
input int lo_thuOpen = 0;                 // Incremento hora inicio Londres Jueves
input int lo_friOpen = 0;                // Incremento hora inicio Londres Viernes
input int ny_monClose = 0;                 // Incremento hora fin Nueva York Lunes
input int ny_tueClose = 0;               // Incremento hora fin Nueva York Martes
input int ny_wedClose = 0;                // Incremento hora fin Nueva York Miércoles
input int ny_thuClose = 0;                 // Incremento hora fin Nueva York Jueves
input int ny_friClose = 0;                // Incremento hora fin Nueva York Viernes
input int lo_monClose = 0;                 // Incremento hora fin Londres Lunes
input int lo_tueClose = 0;                // Incremento hora fin Londres Martes
input int lo_wedClose = 0;                // Incremento hora fin Londres Miércoles
input int lo_thuClose = 0;                 // Incremento hora fin Londres Jueves
input int lo_friClose = 0;                // Incremento hora fin Londres Viernes


double CurrentLot = LotSize;       // lote actual que se usará en la próxima operación
int ConsecutiveLosses = 0;          // contador de pérdidas
ulong last_deal_ticket = 0; // variable global

datetime lastWarning = 0;

// Enumeración para modo de operación
enum ENUM_TRADING_MODE
{
    MODE_LIVE,          // Trading en vivo
    MODE_BACKTEST       // Backtesting
};

// Variables globales
ENUM_TRADING_MODE g_tradingMode = MODE_LIVE;
bool g_isStrategyTester = false;
string LiveSignalFile = "signals_";        // Archivo para trading en vivo
string BacktestSignalFile = "real_backtest_signals_";  // Archivo para backtesting

// Variables para trading en vivo
datetime g_lastSignalTime = 0;
int g_currentSignal = 0;
double g_currentPrice = 0;
double g_confidence = 0;

// Variables para backtesting
string g_backtestSignals[];
int g_totalBacktestSignals = 0;
int g_currentSignalIndex = 0;
int g_tickCounter = 0;

//+------------------------------------------------------------------+
//| Función de inicialización                                        |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("=== INICIANDO AI HYBRID v3.00 ===");
   string activo = Symbol();
   StringToLower(activo);
   LiveSignalFile = LiveSignalFile + activo + ".json";
   BacktestSignalFile = BacktestSignalFile + activo + ".json";
    // Detectar entorno
    g_isStrategyTester = MQLInfoInteger(MQL_TESTER);
    
    if(AutoDetectMode)
    {
        DetectTradingMode();
    }
    else
    {
        g_tradingMode = g_isStrategyTester ? MODE_BACKTEST : MODE_LIVE;
    }
    
    // Información del modo
    string modeStr = (g_tradingMode == MODE_LIVE) ? "TRADING EN VIVO" : "BACKTESTING";
    string envStr = g_isStrategyTester ? "Strategy Tester" : "Terminal Live";
    
    Print("Modo detectado: ", modeStr);
    Print("Entorno: ", envStr);
    
    // Inicialización específica por modo
    if(g_tradingMode == MODE_LIVE)
    {
        return InitializeLiveMode();
    }
    else
    {
        return InitializeBacktestMode();
    }
}

//+------------------------------------------------------------------+
//| Detectar modo de trading automáticamente                        |
//+------------------------------------------------------------------+
void DetectTradingMode()
{
    Print("Detectando modo de trading...");
    
    // 1. Si estamos en Strategy Tester, es backtesting
    if(g_isStrategyTester)
    {
        g_tradingMode = MODE_BACKTEST;
        Print("   Strategy Tester detectado → BACKTESTING");
        return;
    }
    
    // 2. Verificar si existe archivo de backtesting
    if(FileIsExist(BacktestSignalFile))
    {
        Print("   Archivo de backtesting encontrado → BACKTESTING");
        g_tradingMode = MODE_BACKTEST;
        return;
    }
    
    // 3. Por defecto, trading en vivo
    Print("   Modo por defecto → TRADING EN VIVO");
    g_tradingMode = MODE_LIVE;
}

//+------------------------------------------------------------------+
//| Inicializar modo trading en vivo                               |
//+------------------------------------------------------------------+
int InitializeLiveMode()
{
    Print("Inicializando modo TRADING EN VIVO");
    Print("Archivo de señales: ", LiveSignalFile);
    
    if(!FileIsExist(LiveSignalFile))
    {
        Print("️ Archivo de señales no encontrado: ", LiveSignalFile);
        Print("  El EA esperará hasta que se cree el archivo");
    }
    
    Print("Modo trading en vivo inicializado");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Inicializar modo backtesting                                   |
//+------------------------------------------------------------------+
int InitializeBacktestMode()
{
    Print("Inicializando modo BACKTESTING");
    Print("Archivo de señales: ", BacktestSignalFile);
    
    if(!LoadBacktestSignals())
    {
        Alert("ERROR: No se pudieron cargar señales de backtesting");
        return INIT_FAILED;
    }
    
    Print("Modo backtesting inicializado");
    Print("Total señales cargadas: ", g_totalBacktestSignals);
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Función principal OnTick                                        |
//+------------------------------------------------------------------+
void OnTick()
{
    if(g_tradingMode == MODE_LIVE)
    {
        // Verificar si es horario de trading válido
        if(!IsValidTradingSession()) {
           return;
        }
        ProcessLiveTrading();
        if(UseTrailingStop)
         {
            UpdateTrailingStops();
         }

    }
    else
    {    
         // Verificar si es horario de trading válido
        if(!IsValidTradingSession()) {
           return;
        }
        ProcessBacktesting();
        
        CheckClosedDeals();
        if(UseTrailingStop)
         {
            UpdateTrailingStops();
         }
   }
}
    
    // Gestión común


void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Solo nos interesan transacciones de DEAL (ejecuciones reales)
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   // Verificar que la operación cerrada pertenece a este EA
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(magic != MagicNumber) return;

   // Verificar que fue una operación cerrada (entrada/salida)
   int entry = (int)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT) return;  // solo cuando se cierra

   // Revisar resultado
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);

   if(profit < 0) // 🚩 Pérdida
   {
      ConsecutiveLosses++;
      CurrentLot = LotSize + ConsecutiveLosses * LotStep;

      if(CurrentLot > MaxLot) CurrentLot = MaxLot;
      PrintFormat("Pérdida detectada. Lote siguiente = %.2f", CurrentLot);
   }
   else if(profit > 0) // 🚩 Ganancia
   {
      ConsecutiveLosses = 0;
      CurrentLot = LotSize;
      PrintFormat("Ganancia detectada. Reiniciando lote a %.2f", CurrentLot);
   }
}

//+------------------------------------------------------------------+
//| Procesar trading en vivo                                       |
//+------------------------------------------------------------------+
void ProcessLiveTrading()
{
    // Leer señal actual desde archivo
    if(ReadLiveSignal())
    {
        if(IsNewLiveSignal())
        {
            ProcessSignal(g_currentSignal, g_confidence, g_currentPrice);
            g_lastSignalTime = TimeCurrent();
        }
    }
}

//+------------------------------------------------------------------+
//| Procesar backtesting                                           |
//+------------------------------------------------------------------+
void ProcessBacktesting()
{
    g_tickCounter++;
    
    if(UseTimeBasedSignals)
    {
        ProcessTimeBasedBacktest();
    }
    else
    {
        ProcessSequentialBacktest();
    }
}

//+------------------------------------------------------------------+
//| Leer señal de trading en vivo                                  |
//+------------------------------------------------------------------+
bool ReadLiveSignal()
{
    if(!FileIsExist(LiveSignalFile))
    {
        if(TimeCurrent() - lastWarning > 300) // Cada 5 minutos
        {
            if(DebugMode)
                Print("Esperando archivo de señales: ", LiveSignalFile);
            lastWarning = TimeCurrent();
        }
        return false;
    }
    
    int file = FileOpen(LiveSignalFile, FILE_READ | FILE_TXT);
    if(file == INVALID_HANDLE)
    {
        if(DebugMode)
            Print("Error abriendo archivo: ", LiveSignalFile);
        return false;
    }
    
    string jsonData = "";
    while(!FileIsEnding(file))
    {
        jsonData += FileReadString(file);
    }
    FileClose(file);
    
    return ParseLiveSignalJSON(jsonData);
}

//+------------------------------------------------------------------+
//| Parsear JSON de señal en vivo                                  |
//+------------------------------------------------------------------+
bool ParseLiveSignalJSON(string jsonData)
{
    if(StringLen(jsonData) == 0 || StringFind(jsonData, "signal") < 0)
        return false;
    
    // Extraer campos
    g_currentSignal = ExtractIntValue(jsonData, "signal");
    g_confidence = ExtractDoubleValue(jsonData, "confidence");
    g_currentPrice = ExtractDoubleValue(jsonData, "price");
    
    if(DebugMode)
    {
        Print("Señal leída - Signal: ", g_currentSignal, 
              " Confidence: ", g_confidence, 
              " Price: ", g_currentPrice);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Verificar si hay nueva señal en vivo                           |
//+------------------------------------------------------------------+
bool IsNewLiveSignal()
{
    datetime currentTime = TimeCurrent();
    
    // Evitar procesar la misma señal múltiples veces
    if(int(currentTime - g_lastSignalTime) < 300) // 5 minutos
    
        return false;
    
    // Verificar confianza mínima
    if(g_confidence < MinConfidence)
    {
        if(DebugMode)
            Print("Señal rechazada por baja confianza: ", g_confidence);
        return false;
    }
    
    // Verificar señal válida
    if(g_currentSignal == 0)
        return false;
    
    // Verificar spread
    double spread = GetCurrentSpread();
    
    double maxSp = 0;
    
    maxSp = GetOptimalSpread();
    
    if(spread > maxSp)
    {
        if(DebugMode)
            Print("Spread muy alto: ", spread);
        return false;
    }
    
    return true;
}

double GetOptimalSpread()
{
    string symbol = Symbol();
    
    if(symbol == "EURUSD") return MaxSEURUSD;
    if(symbol == "GBPUSD") return MaxSGBPUSD;
    if(symbol == "USDJPY") return MaxSUSDJPY;
    if(symbol == "XAUUSD") return MaxSXAUUSD;
    if(symbol == "BTCUSD") return MaxSBTCUSD;
    if(symbol == "NQ") return MaxSNDAQ100;
    
    return MaxSpread;
}

//+------------------------------------------------------------------+
//| Cargar señales de backtesting                                  |
//+------------------------------------------------------------------+
bool LoadBacktestSignals()
{
    Print("📖 Cargando señales de backtesting...");
    
    if(!FileIsExist(BacktestSignalFile))
    {
        Print("❌ Archivo no encontrado: ", BacktestSignalFile);
        return CreateDefaultBacktestFile();
    }
    
    int file = FileOpen(BacktestSignalFile, FILE_READ | FILE_BIN);
    if(file == INVALID_HANDLE)
    {
        FileClose(file);
        file = FileOpen(BacktestSignalFile, FILE_READ | FILE_TXT);
        if(file == INVALID_HANDLE)    
            Print("❌ Error abriendo archivo: ", BacktestSignalFile);
            return false;
    }
    
    string fileContent = "";
    while(!FileIsEnding(file))
    {
        fileContent += FileReadString(file);
    }
    FileClose(file);
    
    return ParseBacktestSignals(fileContent);
}

//+------------------------------------------------------------------+
//| Parsear señales de backtesting                                 |
//+------------------------------------------------------------------+
bool ParseBacktestSignals(string jsonContent)
{
    if(StringLen(jsonContent) == 0)
        return false;
    
    // Buscar objetos JSON en el array
    int objectCount = 0;
    int pos = 0;
    
    while(pos < StringLen(jsonContent))
    {
        pos = StringFind(jsonContent, "{", pos + 1);
        if(pos < 0) break;
        objectCount++;
    }
    
    if(objectCount == 0)
    {
        Print("❌ No se encontraron señales en el archivo");
        return false;
    }
    
    ArrayResize(g_backtestSignals, objectCount);
    g_totalBacktestSignals = objectCount;
    
    // Extraer cada objeto
    pos = 0;
    int signalIndex = 0;
    
    while(signalIndex < objectCount && pos < StringLen(jsonContent))
    {
        int objStart = StringFind(jsonContent, "{", pos);
        int objEnd = StringFind(jsonContent, "}", objStart);
        
        if(objStart < 0 || objEnd < 0) break;
        
        g_backtestSignals[signalIndex] = StringSubstr(jsonContent, objStart, objEnd - objStart + 1);
        
        pos = objEnd + 1;
        signalIndex++;
    }
    
    g_totalBacktestSignals = signalIndex;
    Print("Señales de backtesting cargadas: ", g_totalBacktestSignals);
    
    return g_totalBacktestSignals > 0;
}

//+------------------------------------------------------------------+
//| Procesar backtesting secuencial                                |
//+------------------------------------------------------------------+
void ProcessSequentialBacktest()
{
    if(g_tickCounter % TicksPerSignal != 0)
        return;
    
    if(g_currentSignalIndex >= g_totalBacktestSignals)
    {
        static bool finished = false;
        if(!finished && DebugMode)
        {
            Print("Todas las señales procesadas (", g_totalBacktestSignals, ")");
            finished = true;
        }
        return;
    }
    
    ProcessBacktestSignal(g_currentSignalIndex);
    g_currentSignalIndex++;
}

//+------------------------------------------------------------------+
//| Procesar backtesting basado en tiempo                          |
//+------------------------------------------------------------------+
void ProcessTimeBasedBacktest()
{
    datetime currentTime = TimeCurrent();
    
    for(int i = g_currentSignalIndex; i < g_totalBacktestSignals; i++)
    {
        datetime signalTime = ExtractSignalTimestamp(g_backtestSignals[i]);
        
        if(signalTime == 0) continue;
        
        int timeDiff = (int)MathAbs(currentTime - signalTime);
        
        if(timeDiff <= TimePerSignal) 
        {
            ProcessBacktestSignal(i);
            g_currentSignalIndex = i + 1;
            return;
        }
        
        if(signalTime < currentTime - TimePerSignal)
        {
            g_currentSignalIndex = i + 1;
        }
        else
        {
            break;
        }
    }
}

//+------------------------------------------------------------------+
//| Procesar señal de backtesting específica                       |
//+------------------------------------------------------------------+
void ProcessBacktestSignal(int index)
{
    if(index >= g_totalBacktestSignals)
        return;
    
    string signalData = g_backtestSignals[index];
    
    int signal = ExtractIntValue(signalData, "signal");
    double confidence = ExtractDoubleValue(signalData, "confidence");
    double price = ExtractDoubleValue(signalData, "price");
    
    if(confidence >= MinConfidence && signal != 0)
    {
        if(DebugMode)
        {
            string signalType = (signal == 1) ? "BUY" : "SELL";
            Print("📊 Backtesting ", index + 1, "/", g_totalBacktestSignals, 
                  ": ", signalType, " (conf: ", confidence, ")");
        }
        
        ProcessSignal(signal, confidence, price);
    }
}

//+------------------------------------------------------------------+
//| Procesar señal (común para ambos modos)                        |
//+------------------------------------------------------------------+
void ProcessSignal(int signal, double confidence, double price)
{
    string signalType = (signal == 1) ? "BUY" : "SELL";
    
    if(DebugMode)
    {
        Print(" Procesando ", signalType, " - Confianza: ", 
              DoubleToString(confidence, 3));
    }
    
    if(closeopposite){
       // Cerrar posiciones opuestas
      CloseOppositePositions(signal);
      }
   
   // Verificar si ya hay posiciones abiertas
   if(CountOpenPositions() > MaxPosActivas) {
      return;
   }
    
    // Abrir nueva posición
    if(invert){
      signal = -1 * signal;
    }
    if(signal == 1)
        OpenBuyPosition();
    else if(signal == -1)
        OpenSellPosition();
}

//+------------------------------------------------------------------+
//| Crear archivo de backtesting por defecto                       |
//+------------------------------------------------------------------+
bool CreateDefaultBacktestFile()
{
    Print("🔧 Creando archivo de backtesting...");
    
    // Source file name
   string source_file = BacktestSignalFile;
   
   // Destination file name
   string destination_file = BacktestSignalFile;
   
   // Copy the file from the shared folder to the local folder
   bool success = FileCopy(source_file, FILE_COMMON, destination_file, 0);
  
   // Check if the copy was successful
   if (success)
     if(!FileIsExist(BacktestSignalFile))
         Print("File copied successfully!");
         return LoadBacktestSignals();
     int file = FileOpen(BacktestSignalFile, FILE_WRITE | FILE_BIN);
     if(file == INVALID_HANDLE)
         FileClose(file);
         Print("File NOT copied!-Error open BIN - ", GetLastError());
         file = FileOpen(BacktestSignalFile, FILE_WRITE | FILE_TXT);
         if(file == INVALID_HANDLE)
             FileClose(file);
             Print("File NOT copied!-Error open DEFAULT - ", GetLastError());
            // Crear algunas señales de ejemplo
             file = FileOpen(BacktestSignalFile, FILE_WRITE | FILE_TXT);
             FileWrite(file, "[");
             FileWrite(file, "  {\"timestamp\":\"2024-01-15T10:00:00\",\"datetime_mt5\":1705315200,\"signal\":1,\"confidence\":0.75,\"price\":1.0850,\"high\":1.0860,\"low\":1.0840,\"volume\":100},");
             FileWrite(file, "  {\"timestamp\":\"2024-01-15T10:15:00\",\"datetime_mt5\":1705316100,\"signal\":-1,\"confidence\":0.68,\"price\":1.0845,\"high\":1.0850,\"low\":1.0835,\"volume\":150}");
             FileWrite(file, "]");
             FileClose(file);
             Print("✅ Archivo de ejemplo creado: ", BacktestSignalFile);
                   
             return LoadBacktestSignals();
   Print("Failed to copy file: ", _LastError);     
   return false;
}

//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Función de copia integrada en el EA                             |
//+------------------------------------------------------------------+
bool CopyFileFromEA(string source, string destination)
{
   string strParameters = "/c copy " + source + " " + destination;
   
   int result = ShellExecuteW(0, "open", "cmd.exe", strParameters, NULL, SW_SHOWNORMAL);
   if (result <= 32)
   {
      Alert("Shell Execute Failed: ", result);
      return false;
   }
   return true;
}


//+------------------------------------------------------------------+
//| Funciones auxiliares comunes                                   |
//+------------------------------------------------------------------+
double GetCurrentSpread()
{
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    return (ask - bid) / point;
}

int ExtractIntValue(string json, string key)
{
    string searchKey = "\"" + key + "\":";
    int keyPos = StringFind(json, searchKey);
    if(keyPos < 0) return 0;
    
    keyPos += StringLen(searchKey);
    string valueStr = "";
    
    for(int i = keyPos; i < StringLen(json); i++)
    {
        string chara = StringSubstr(json, i, 1);
        if(chara == "," || chara == "}" || chara == "]") break;
        if(chara != " " && chara != "\"") valueStr += chara;
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
        string chara = StringSubstr(json, i, 1);
        if(chara == "," || chara == "}" || chara == "]") break;
        if(chara != " " && chara != "\"") valueStr += chara;
    }
    
    return StringToDouble(valueStr);
}

datetime ExtractSignalTimestamp(string signalJson)
{
    int timestampInt = ExtractIntValue(signalJson, "datetime_mt5");
    return (datetime)timestampInt;
}

void OpenBuyPosition()
{
    // Implementación estándar de apertura BUY
    if(HasPosition(POSITION_TYPE_BUY)) return;
    
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    Print("ask: ", ask);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    string activo = Symbol();
    double sl = 0;
    double tp = 0;
   
     
   if(activo == "EURUSD" || activo == "GBPUSD" || activo == "XAUUSD" || activo == "USDJPY")
    {
          sl = NormalizeDouble(ask - StopLoss * point * 10, digits);
          tp = NormalizeDouble(ask + TakeProfit * point * 10, digits);
    }      
    //if(activo == "BTCUSD")
    else if(activo == "BTCUSD") {
          sl = NormalizeDouble(ask - StopLoss * point, digits);
          tp = NormalizeDouble(ask + TakeProfit * point, digits);
     }
     else{
          sl = NormalizeDouble(ask - StopLoss * point * 100, digits);
          tp = NormalizeDouble(ask + TakeProfit * point * 100, digits);
     
     }
          
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    //request.volume = LotSize;
    request.volume = CurrentLot;
    request.type = ORDER_TYPE_BUY;
    request.price = ask;
    request.sl = sl;
    request.tp = tp;
    request.magic = MagicNumber;
    request.comment = "AI_BUY_Hybrid";
    
    if(OrderSend(request, result))
    {
        Print("✅ BUY - Ticket: ", result.order);
    }
    else
    {
        Print("❌ Error BUY: ", result.retcode);
    }
}

void OpenSellPosition()
{
    // Implementación estándar de apertura SELL
    if(HasPosition(POSITION_TYPE_SELL)) return;
    
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    Print("bid: ", bid);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    string activo = Symbol();

    //double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE); // margen libre
    //double tick_value = SymbolInfoDouble(activo, SYMBOL_TRADE_TICK_VALUE) * LotSize;
    //double comision = 2 * LotSize * unid_x_lote * comision_f / bid;
    double sl = 0;
    double tp = 0;
   
    if(activo == "EURUSD" || activo == "GBPUSD" || activo == "XAUUSD" || activo == "USDJPY")
    {
          sl = NormalizeDouble(bid + StopLoss * point * 10, digits);
          tp = NormalizeDouble(bid - TakeProfit * point * 10, digits);
    }      
    else if(activo == "BTCUSD")
    {
        
          sl = NormalizeDouble(bid + StopLoss * point, digits);
          tp = NormalizeDouble(bid - TakeProfit * point, digits);
    }
    else
    {
        
          sl = NormalizeDouble(bid + StopLoss * point * 100, digits);
          tp = NormalizeDouble(bid - TakeProfit * point * 100, digits);
    }
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    //request.volume = LotSize;
    request.volume = CurrentLot;
    request.type = ORDER_TYPE_SELL;
    request.price = bid;
    request.sl = sl;
    request.tp = tp;
    request.magic = MagicNumber;
    request.comment = "AI_SELL_Hybrid";
    
    if(OrderSend(request, result))
    {
        Print("✅ SELL - Ticket: ", result.order);
    }
    else
    {
        Print("❌ Error SELL: ", result.retcode);
    }
}

bool HasPosition(ENUM_POSITION_TYPE type)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        string symbol = PositionGetSymbol(i);
        if(symbol == Symbol())
        {
            if(PositionSelect(symbol))
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

void CloseOppositePositions(int newSignal)
{
    ENUM_POSITION_TYPE oppositeType = (newSignal == 1) ? POSITION_TYPE_SELL : POSITION_TYPE_BUY;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        string symbol = PositionGetSymbol(i);
        if(symbol == Symbol())
        {
            if(PositionSelect(symbol))
            {
                if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
                   PositionGetInteger(POSITION_TYPE) == oppositeType)
                {
                    ulong ticket = PositionGetInteger(POSITION_TICKET);
                    ClosePosition(ticket);
                }
            }
        }
    }
}

void ClosePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.position = ticket;
    request.symbol = Symbol();
    request.volume = PositionGetDouble(POSITION_VOLUME);
    request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.price = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                    SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                    SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    request.magic = MagicNumber;
    
    OrderSend(request, result);
}

void UpdateTrailingStops()
{ 
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue; // no hay posición válida

      // ahora la posición está seleccionada
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic != MagicNumber) continue; // saltar posiciones que no son de este EA

      string symbol     = PositionGetString(POSITION_SYMBOL);
      long   type       = PositionGetInteger(POSITION_TYPE);
      double sl         = PositionGetDouble(POSITION_SL);
      double tp         = PositionGetDouble(POSITION_TP);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);

      double point      = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int    digits     = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      int    stop_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);

      double price = (type == POSITION_TYPE_BUY)
                     ? SymbolInfoDouble(symbol, SYMBOL_BID)
                     : SymbolInfoDouble(symbol, SYMBOL_ASK);

      // --- BUY ---
      if(type == POSITION_TYPE_BUY)
      {
         if(price - open_price > TrailingStop * point)
         {
            double new_sl = NormalizeDouble(price - TrailingStop * point, digits);
            if(MathAbs(price - new_sl) < stop_level * point)
               new_sl = price - stop_level * point;

            if(sl == 0.0 || new_sl > sl + TrailingStep * point)
               trade.PositionModify(ticket, new_sl, tp);
         }
      }

      // --- SELL ---
      if(type == POSITION_TYPE_SELL)
      {
         if(open_price - price > TrailingStop * point)
         {
            double new_sl = NormalizeDouble(price + TrailingStop * point, digits);
            if(MathAbs(price - new_sl) < stop_level * point)
               new_sl = price + stop_level * point;

            if(sl == 0.0 || new_sl < sl - TrailingStep * point)
               trade.PositionModify(ticket, new_sl, tp);
         }
      }
   }
}

void UpdateLotSize()
{
   // Recorremos el historial para encontrar la última operación cerrada del MagicNumber
   ulong deal_ticket = HistoryDealGetTicket(HistoryDealsTotal() - 1);
   if(deal_ticket == 0) return;

   // Verificamos que sea de nuestro EA
   long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   if(magic != MagicNumber) return;

   double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);

   if(profit < 0) // si fue pérdida
   {
      ConsecutiveLosses++;
      CurrentLot = LotSize + ConsecutiveLosses * LotStep;

      // respetar límite máximo
      if(CurrentLot > MaxLot) CurrentLot = MaxLot;
   }
   else if(profit > 0) // si fue ganancia
   {
      ConsecutiveLosses = 0;
      CurrentLot = LotSize;
   }
}



void CheckClosedDeals()
{
   HistorySelect(0, TimeCurrent());
   int total_deals = HistoryDealsTotal();

   for(int i = total_deals - 1; i >= 0; i--)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      if(deal_ticket == 0) continue;

      if(deal_ticket <= last_deal_ticket) break; // 👈 ya procesamos hasta aquí

      long magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
      if(magic != MagicNumber) continue;

      int entry = (int)HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;

      double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);

      if(profit < 0)
      {
         ConsecutiveLosses++;
         CurrentLot = LotSize + ConsecutiveLosses * LotStep;
         if(CurrentLot > MaxLot) CurrentLot = MaxLot;
      }
      else if(profit > 0)
      {
         ConsecutiveLosses = 0;
         CurrentLot = LotSize;
      }

      // guardamos el último ticket procesado
      if(deal_ticket > last_deal_ticket)
         last_deal_ticket = deal_ticket;
   }

   // normalizar lote
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   CurrentLot = MathFloor(CurrentLot / step) * step;
}

//+------------------------------------------------------------------+
//| Verificar si es sesión de trading válida                        |
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
   
   // Evitar fines de semana
   if(timeStruct.day_of_week == 0 || timeStruct.day_of_week == 6) {
      return false;
   }

   if(ValidarHorarioDia){
   
      if(timeStruct.day_of_week == 5) {
         bool nySession = (hour >= StartHourNY+ny_friOpen && hour < (EndHourNY - ny_friClose));
         // Sesión de Londres
         bool londonSession = (hour >= StartHourLondon+lo_friOpen && hour < EndHourLondon - lo_friClose);
         return (nySession || londonSession);
      }
      if(timeStruct.day_of_week == 4) {
         bool nySession = (hour >= StartHourNY+ny_thuOpen && hour < EndHourNY - ny_thuClose);
         // Sesión de Londres
         bool londonSession = (hour >= StartHourLondon+lo_thuOpen && hour < EndHourLondon - lo_thuClose);
         return (nySession || londonSession);      
      }
      if(timeStruct.day_of_week == 3) {
         bool nySession = (hour >= StartHourNY+ny_wedOpen && hour < EndHourNY - ny_wedClose);
         // Sesión de Londres
         bool londonSession = (hour >= StartHourLondon+lo_wedOpen && hour < EndHourLondon - lo_wedClose);
         return (nySession || londonSession);
      }
      if(timeStruct.day_of_week == 2) {
         bool nySession = (hour >= StartHourNY+ny_tueOpen && hour < EndHourNY - ny_tueClose);
         // Sesión de Londres
         bool londonSession = (hour >= StartHourLondon+lo_tueOpen && hour < EndHourLondon - lo_tueClose);
         return (nySession || londonSession);      
      }
      if(timeStruct.day_of_week == 1) {
         bool nySession = (hour >= StartHourNY+ny_monOpen && hour < EndHourNY - ny_monClose);
         // Sesión de Londres
         bool londonSession = (hour >= StartHourLondon+lo_monOpen && hour < EndHourLondon - lo_monClose);
         return (nySession || londonSession);
      }
   }
      
   // Sesión de Nueva York
   bool nySession = (hour >= StartHourNY && hour < EndHourNY);
   // Sesión de Londres
   bool londonSession = (hour >= StartHourLondon && hour < (EndHourLondon));
   
   return (nySession || londonSession);
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
//| Desinicialización                                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    string modeStr = (g_tradingMode == MODE_LIVE) ? "LIVE" : "BACKTEST";
    Print("=== FINALIZANDO EA HYBRID (", modeStr, ") ===");
    Print("Motivo: ", reason);
}