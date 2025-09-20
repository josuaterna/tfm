import MetaTrader5 as mt5
import pandas as pd
from datetime import datetime


class Datamanager:
    def __init__(self):
        self.conectado = False
        self.simbolos_broker = {}
        self._conectar()

#Validar conexión         
    def _conectar(self):
        if not mt5.initialize():
            print(f"ERROR: Falla inicialización MT5 - {mt5.last_error()}")
            return False
        
        info_cuenta = mt5.account_info()
        if info_cuenta is None:
            print("ERROR: Ninguna cuenta conectada a MT5")
            return False
        
        print(f"MT5 conectado - Version: {mt5.version()}")
        print(f"INFO: {info_cuenta.login} - {info_cuenta.server}")
        self.conectado = True
        return True

#Descargar datos históricos    
    def get_data(self, simbolo, fecha_ini, fecha_fin, timeframe='M5'):
        if not self.conectado:
            if not self._conectar():
                return None
        
        inicio, fin = self._validar_fechas(fecha_ini, fecha_fin)
        if not inicio or not fin:
            return None
        
        try:
            timeframe_map = {
                'M1': mt5.TIMEFRAME_M1,
                'M5': mt5.TIMEFRAME_M5,
                'M15': mt5.TIMEFRAME_M15,
                'M30': mt5.TIMEFRAME_M30,
                'H1': mt5.TIMEFRAME_H1,
                'H4': mt5.TIMEFRAME_H4,
                'D1': mt5.TIMEFRAME_D1
            }
            
            mt5_timeframe = timeframe_map.get(timeframe, mt5.TIMEFRAME_M5)
            
            print(f"Descargando: {simbolo} from {fecha_ini} to {fecha_fin}")
            rates = mt5.copy_rates_range(simbolo, mt5_timeframe, inicio, fin)
            
            if rates is None:
                error = mt5.last_error()
                print(f"ERROR: Datos no disponibles {simbolo} - MT5 Error: {error}")
                
                recent_rates = mt5.copy_rates_from_pos(simbolo, mt5_timeframe, 0, 10)
                if recent_rates is not None:
                    print("INFO: Datos recientes disponibles. Revisar fechas")
                else:
                    print("INFO: No hay datos recientes disponibles")
                return None
            
            if len(rates) == 0:
                print(f"ERROR: Datos no recibidos {simbolo}")
                return None
            
            df = pd.DataFrame(rates)
            df['time'] = pd.to_datetime(df['time'], unit='s')
            df.set_index('time', inplace=True)
            
            print(f"Recibidos {len(df)} registros de {simbolo}")
            return df
            
        except Exception as e:
            print(f"ERROR: Error descargando datos {simbolo}: {e}")
            return None

    def get_data_intervalos(self, simbolo, n=20, timeframe='M5'):
        if not self.conectado:
            if not self._conectar():
                return None
        
        try:
            timeframe_map = {
                'M1': mt5.TIMEFRAME_M1,
                'M5': mt5.TIMEFRAME_M5,
                'M15': mt5.TIMEFRAME_M15,
                'M30': mt5.TIMEFRAME_M30,
                'H1': mt5.TIMEFRAME_H1,
                'H4': mt5.TIMEFRAME_H4,
                'D1': mt5.TIMEFRAME_D1
            }
            
            mt5_timeframe = timeframe_map.get(timeframe, mt5.TIMEFRAME_M5)
            mt5.symbol_select(simbolo, True)
            # print("symbol_info:", mt5.symbol_info(simbolo))
            # print("symbol_tick:", mt5.symbol_info_tick(simbolo))
            print(f"Descargando últimos {n} registros de {simbolo}.")
            rates = mt5.copy_rates_from_pos(simbolo, mt5_timeframe, 0, n)
            
            if rates is None:
                error = mt5.last_error()
                print(f"ERROR: Datos no disponibles {simbolo} - MT5 Error: {error}")
                
            if len(rates) == 0:
                print(f"ERROR: Datos no recibidos {simbolo}")
                return None
            
            df = pd.DataFrame(rates)
            df['time'] = pd.to_datetime(df['time'], unit='s')
            df.set_index('time', inplace=True)
            
            print(f"Recibidos {len(df)} registros de {simbolo}")
            return df
            
        except Exception as e:
            print(f"ERROR: Error descargando datos {simbolo}: {e}")
            return None
        
# Traer símbolos disponibles del broker
    def _simbolos_disponibles(self):
        simbolos = mt5.symbols_get()
        if simbolos:
            for simbolo in simbolos:
                nombre_sim = simbolo.name.replace('.', '').replace('-', '').replace('_', '')[:6]
                self.simbolos_broker[nombre_sim] = simbolo.name
            print(f"Símbolos disponibles: {len(self.simbolos_broker)}")
            print(self.simbolos_broker)
        else:
            print("WAR: No hay símbolos disponibles")

    
# Validar formato de fechas ingresadas
    def _validar_fechas(self, fecha_ini, fecha_fin):
            try:
                inicio = datetime.strptime(fecha_ini, '%Y-%m-%d')
                fin = datetime.strptime(fecha_fin, '%Y-%m-%d')
                
                if inicio >= fin:
                    print("ERROR: Fecha inicio debe ser menor a fecha fin")
                    return None, None
                    
                if fin > datetime.now():
                    print("ERROR: Fecha fin debe ser menor a fecha actual")
                    return None, None
                    
                return inicio, fin
            except ValueError as e:
                print(f"ERROR: Formato inválido de fechas - {e}")
                return None, None