import sys
import os
import pandas as pd
import inspect
import dotenv
from datetime import datetime
from tipos.lstm import LSTM_class
from tipos.randomf import RandomF_class
from tipos.svm_nn import SVM_NN_class
import torch.nn as nn

dotenv.load_dotenv()
r_common = os.getenv('RUTA_COMMON')
r_realt = os.getenv('RUTA_REAL_TIME')
r_csv = os.getenv('RUTA_CSV')
obj = None

def select_accion():
    print("\nSeleccione modo:")
    print("1. Train  ||  2. Backtesting  ||  3. Tiempo real  || 4. Train + Tiempo real || 5. Salir")
    select = input("Opción: ")
    return int(select)

def select_simbolo():
    print("\nSeleccione símbolo:")
    print("1. NASDAQ 100  ||  2. EURUSD  ||  3. S&P 500")
    select = int(input("Opción: "))
    if select == 1:
        simbolo = "NQ"
    elif select == 2:
        simbolo = "EURUSD"
    elif select == 3:
        simbolo = "ES"
    else:
        return None
    return simbolo

def select_indicadores():
    print("\nSeleccione indicadores:")
    print("1. Binarios  ||  2. Calculados  ||  3. Binarios y calculados")
    select = int(input("Opción: "))
    #select = 3
    if select == 1:
        indicadores = [
            'str_cdl','aw_os','rsi_3','chand','zlsma', 'ema_50_an', 'adx',
        ]
    elif select == 2:
        indicadores = [
            'rsi_3_ind', 'ema_50_ind', 'zlsma_ind',
            'rsi','macd', 'sma_20', 'sma_50', 'ema_20', 'ema_50',
            'bb_upper', 'bb_lower', 'stoch_k', 'stoch_d', 'atr',
            'williams_r', 'cci', 'momentum', 'roc'
        ]
    elif select == 3:
        indicadores = [
            'str_cdl','aw_os','rsi_3','chand','zlsma', 'ema_50_an', 'adx',
            'rsi_3_ind', 'ema_50_ind', 'zlsma_ind',
            'rsi','macd', 'sma_20', 'sma_50', 'ema_20', 'ema_50',
            'bb_upper', 'bb_lower', 'stoch_k', 'stoch_d', 'atr',
            'williams_r', 'cci', 'momentum', 'roc'
        ]
    return indicadores

def select_modelo():
    print("\nSeleccione modelo:")
    print("1. Random forest 2. Neuronal network svm 3. LSTM Neuronal network")
    select = int(input("Opción: "))
    if select == 1:
        modelo = "randomf"
    elif select == 2:
        modelo = "svm_nn"
    elif select == 3:
        modelo = "lstm"
    else:
        return None
    return modelo

def entrenamiento(modelo, simbolo, indicadores, tiempo, fecha_ini, fecha_fin):
    if modelo == "lstm":
        seq = int(input("Secuencia lstm: "))
        th = int(input("Threshold: "))
        fut_bar = int(input("Future bars: "))
        obj = LSTM_class(indicadores, seq)
        obj.lstm_train(simbolo, tiempo, fecha_ini, fecha_fin, r_common, th, fut_bar)
    elif modelo == "randomf":
        obj_randomf = RandomF_class(indicadores)
        obj_randomf.randomf_train(simbolo, fecha_ini, fecha_fin)
    elif modelo == "svm_nn":
        obj = SVM_NN_class(indicadores, hidden_dim=64, dropout=0.2, margin=1.0)
        obj.svmnn_train(simbolo, fecha_ini, fecha_fin)
        print(f"\nFechas para backtesting: {datetime.now().strftime('%Y-%m-%d')}")
        fecha_ini_back = input("Fecha inicio (YYYY-MM-DD): ").strip()
        fecha_fin_back = input("Fecha fin (YYYY-MM-DD): ").strip()
        # fecha_ini_back = "2025-09-01"
        # fecha_fin_back = "2025-09-15"
        
  
def seniales_back(modelo, simbolo, indicadores, fecha_ini, fecha_fin):
    obj.generar_json_senales(modelo, simbolo, fecha_ini, fecha_fin)
    pass

def seniales_tr(modelo, simbolo, indicadores):
    if modelo == "lstm":
        obj.run_realtime_lstm(simbolo, indicadores, r_realt, r_csv)

def main():
    modelo = None
    accion = 0
    simbolo = None
    indicadores = []
    
    while accion != 5:
        accion = select_accion()
        #accion = 1
        simbolo = select_simbolo()
        #simbolo = "EURUSD"
        indicadores = select_indicadores()
        modelo = select_modelo()
        #modelo = "lstm"        
    #    
        if accion != 3:
            print(f"\nFecha actual: {datetime.now().strftime('%Y-%m-%d')}")
            fecha_ini = input("Fecha inicio (YYYY-MM-DD): ").strip()
            fecha_fin = input("Fecha fin (YYYY-MM-DD): ").strip()
            tiempo = int(input("Intervalo (1.M1  2.M5  3.M15  4.M30  5.H1  6.H4  7.D1): "))
            #fecha_ini = "2025-09-10"
            #fecha_fin = "2025-09-18"
        if accion == 1:
            entrenamiento(modelo, simbolo, indicadores, tiempo, fecha_ini, fecha_fin)
        elif accion == 2:
            seniales_back(modelo, simbolo, indicadores, fecha_ini, fecha_fin)
        elif accion == 3:
            seniales_tr(modelo, simbolo, indicadores)
        elif accion == 4:
            seniales_tr(modelo, simbolo, indicadores, fecha_ini, fecha_fin)        
        else:
            pass

if __name__ == "__main__":
    #try:
        main()
    #except KeyboardInterrupt:
    #    print("\n\nProceso interrumpido por el usuario")
    #except Exception as e:
    #    print(f"\nError: {e}")
    #    sys.exit(1)