import sys
import os
import pandas as pd
import inspect
from datetime import datetime
from tipos.lstm import LSTM_class
from tipos.randomf import RandomF_class
from tipos.svm_nn import SVM_NN_class

def entrenamiento(modelo, simbolo, indicadores, fecha_ini, fecha_fin):
    print(f"Línea {inspect.currentframe().f_lineno}")
    if modelo == "lstm":
        obj_lstm = LSTM_class(indicadores. simbolo)
        obj_lstm.lstm_train(simbolo, fecha_ini, fecha_fin)
    elif modelo == "random":
        obj_randomf = RandomF_class(indicadores, simbolo)
        obj_randomf.randomf_train(simbolo, fecha_ini, fecha_fin)
        

  
def seniales_back(modelo, indicadores, fecha_ini, fecha_fin, ventana_historica, actualizacion):
    pass

def seniales_tr(modelo, indicadores, ventana_historica, actualizacion):
    pass

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
    
def select_accion():
    print("\nSeleccione modo:")
    print("1. Train  ||  2. Backtesting  ||  3. Tiempo real  || 4. Train + Tiempo real")
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
    #select = int(input("Opción: "))
    select = 3
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

def main():
    #modelo = select_modelo()
    modelo = "lstm"
    #accion = select_accion()
    accion = 1
    print(f"Línea {inspect.currentframe().f_lineno}")
    if accion != 3:
        print(f"\nFecha actual: {datetime.now().strftime('%Y-%m-%d')}")
        # fecha_ini = input("Fecha inicio (YYYY-MM-DD): ").strip()
        # fecha_fin = input("Fecha fin (YYYY-MM-DD): ").strip()
        fecha_ini = "2025-06-01"
        fecha_fin = "2025-08-31"
    print(f"Línea {inspect.currentframe().f_lineno}")
    #simbolo = select_simbolo()
    simbolo = "NQ"
    print(f"Línea {inspect.currentframe().f_lineno}")
    indicadores = select_indicadores()
    print(f"Línea {inspect.currentframe().f_lineno}")

    if accion == 1:
        print(f"Línea {inspect.currentframe().f_lineno}")
        entrenamiento(modelo, simbolo, indicadores, fecha_ini, fecha_fin)
        print(f"Línea {inspect.currentframe().f_lineno}")
    elif accion == 2:
        seniales_back(modelo, simbolo, indicadores, fecha_ini, fecha_fin)
    elif accion == 3:
        seniales_tr(modelo, simbolo, indicadores)
    elif accion == 4:
        seniales_tr(modelo, simbolo, indicadores, fecha_ini, fecha_fin)        
    else:
        return

if __name__ == "__main__":
    #try:
        main()
    #except KeyboardInterrupt:
    #    print("\n\nProceso interrumpido por el usuario")
    #except Exception as e:
    #    print(f"\nError: {e}")
    #    sys.exit(1)