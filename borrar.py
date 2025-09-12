#borrar.py
import MetaTrader5 as mt5

import pandas as pd
from datetime import datetime

class Pruebas:
    def __init__(self):
        self.conectado = False
        self.simbolos_broker = {}
        self._conectar()

    def _conectar(self):
        if not mt5.initialize():
            print(f"ERROR: Falla inicialización MT5 - {mt5.last_error()}")
            return False
        
        info_cuenta = mt5.account_info()
        if info_cuenta is None:
            print("ERROR: Ninguna cuenta conectada a MT5")
            return False
        
        print(f"MT5 conectado - Version: {mt5.version()}")
        print(f"Info: {info_cuenta.login} - {info_cuenta.server}")
        self.conectado = True
        return True
    
    def simbolos_disponibles(self):
        simbolos = mt5.symbols_get()
        if simbolos:
            for simbolo in simbolos:
                nombre_sim = simbolo.name.replace('.', '').replace('-', '').replace('_', '')[:6]
                self.simbolos_broker[nombre_sim] = simbolo.name
            print(f"Símbolos disponibles: {len(self.simbolos_broker)}")
            print(self.simbolos_broker)
        else:
            print("WAR: No hay símbolos disponibles")

def main():
    prueba = Pruebas()
    prueba.simbolos_disponibles()

if __name__== '__main__':
    main()