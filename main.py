import sys
import os
import pandas as pd
import inspect
import torch
from tipos.lstm2 import train_and_save_returns, load_and_forecast_returns
from datetime import datetime
from tipos.lstm import LSTM_class
from tipos.lstm2 import LSTMReturns
from tipos.randomf import RandomF_class
from tipos.svm_nn import SVM_NN_class
import torch.nn as nn

def entrenamiento(modelo, simbolo, indicadores, fecha_ini, fecha_fin):
    if modelo == "lstm":
        obj = LSTM_class(indicadores)
        #fecha_pred_ini = "2025-09-01 00:00:00"
        #fecha_pred_fin = "2025-09-10 23:59:00"
        #obj.cargar()
        obj.lstm_train(simbolo,fecha_ini, fecha_fin)
        #df = obj.entrenador.obj_datamanager.get_data(simbolo,fecha_ini,fecha_fin)
        # Entrenar
        #model, sp, sr = train_and_save_returns(df, "NQ", seq_len=50, epochs=30, batch_size=32)

        # Forecast
        #df_preds = load_and_forecast_returns(df, "NQ", fecha_pred_ini, fecha_pred_fin, seq_len=50)  
        #df_preds.info()
        

    elif modelo == "randomf":
        obj_randomf = RandomF_class(indicadores)
        obj_randomf.randomf_train(simbolo, fecha_ini, fecha_fin)
    elif modelo == "svm_nn":
        obj_svmnn = SVM_NN_class(indicadores, hidden_dim=64, dropout=0.2, margin=1.0)
        obj_svmnn.svmnn_train(simbolo, fecha_ini, fecha_fin)
        print(f"\nFechas para backtesting: {datetime.now().strftime('%Y-%m-%d')}")
        # fecha_ini = input("Fecha inicio (YYYY-MM-DD): ").strip()
        # fecha_fin = input("Fecha fin (YYYY-MM-DD): ").strip()
        fecha_ini_back = "2025-08-01"
        fecha_fin_back = "2025-08-31"
        obj_svmnn.generar_json_senales(obj_svmnn.model, simbolo, fecha_ini_back, fecha_fin_back)

  
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
        fecha_ini = "2025-07-01"
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