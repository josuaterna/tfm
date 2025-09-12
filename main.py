import sys
import os
from datetime import datetime
from src.train import Trainer
from

def entrenamiento(modelo, indicadores, fecha_ini, fecha_fin, ventana_historica, actualizacion):
    entrenador = Trainer(modelo, indicadores, fecha_ini, fecha_fin, ventana_historica, actualizacion)
    X, y = entrenador.preparar_datos()



    
    
def seniales_back(modelo, indicadores, fecha_ini, fecha_fin, ventana_historica, actualizacion):

def seniales_tr(modelo, indicadores, ventana_historica, actualizacion):


def select_modelo():
    print("\nSeleccione modelo:")
    print("1. Random forest 2. Neuronal network svm 3. LSTM Neuronal network")
    select = input("Opción: ")
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
    return select

def select_simbolo():
    print("\nSeleccione símbolo:")
    print("1. NASDAQ 100  ||  2. EURUSD  ||  3. S&P 500")
    select = input("Opción: ")
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
    select = input("Opción: ")
    return select

def main():
    modelo = select_modelo()
    ventana_historica = None
    actualizacion = None
    if modelo == "lstm":
        ventana_historica = int(input("Ventana histórica (días): ").strip())
        actualizacion = int(input("Periodo de actualización (días): ").strip())
    if accion != 3:
        print(f"\nFecha actual: {datetime.now().strftime('%Y-%m-%d')}")
        fecha_ini = input("Fecha inicio (YYYY-MM-DD): ").strip()
        fecha_fin = input("Fecha fin (YYYY-MM-DD): ").strip()

    accion = select_accion()
    indicadores = select_indicadores()
    if accion == 1:
        entrenamiento(modelo, indicadores, fecha_ini, fecha_fin, ventana_historica, actualizacion)
    elif accion == 2:
        seniales_back(modelo, indicadores, fecha_ini, fecha_fin, ventana_historica, actualizacion)
    elif accion == 3:
        seniales_tr(modelo, indicadores, ventana_historica, actualizacion)
    elif accion == 4:
        seniales_tr(modelo, indicadores, fecha_ini, fecha_fin, ventana_historica, actualizacion)        
    else:
        return

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nProceso interrumpido por el usuario")
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)