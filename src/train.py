import os
import json
import numpy as np
from data_manager import Datamanager
from indicadores import Indicadores_tecnicos
from numpy.lib.stride_tricks import sliding_window_view

class Trainer:
    def __init__(self, modelo, indicadores):
        self.tipo_modelo = modelo
        self.obj_indicadores = Indicadores_tecnicos(indicadores)
        self.obj_datamanager = Datamanager()

    
# Preparar datos
    def preparar_datos(self, simbolo, fecha_ini, fecha_fin):
        print(f"Preparando datos para {simbolo}...")
        df = self.obj_datamanager.get_data(simbolo, fecha_ini, fecha_fin, "M5")
        if df is None or len(df) < 500:
            print(f"WAR: Datos insuficientes para {simbolo}")
            return None, None
        features = self.obj_indicadores.get_feature_matrix(df)
        features.to_csv("features.csv", index=True)
        labels = self.crear_labels(df, future_bars=20)
        labels.to_csv("labels.csv", index=True)
        self._check_label_balance(labels)
        
        min_len = min(len(features), len(labels))
        X = features.iloc[:min_len].values
        y = labels.iloc[:min_len].values
        
        mask = y != 0
        X, y = X[mask], y[mask]
        
        if len(X) < 200:
            print(f"WAR: Muy pocas señales para {simbolo}: {len(X)}")
            return None, None
        
        print(f"INFO: Preparadas {len(X)} muestras para {simbolo}")
        return X, y


    def crear_labels(self, df, velas_futuro= 50):
        df["sl_buy"], df["tp_buy"], df["sl_sell"], df["tp_sell"] = self._sl_tp(df["close"])
        df = self._check_tp_sl(df, velas_futuro)
        conditions = [
            df['result_buy'] == 1,
            df['result_sell'] == 1
        ]
        df['signal'] = np.select(conditions, [1, -1], default=0)
        df.to_csv("datos_labels.csv", index=True)
        df = df.drop(columns=['result_buy', 'result_sell','sl_buy', 'tp_buy', 'sl_sell', 'tp_sell',"close_buy","close_buy_hor","m_buy","close_sell","close_sell_hor","m_sell"])

        return df['signal'].fillna(0)

    def _sl_tp(self, prices, com_per = 0.00007, wl_rate=2, lot=0.01, val_lot=100000,
        tick = 0.00001, balance = 500, risk = 0.01, alpha= 0.1):
        tick_val = lot * val_lot * tick / prices
        comision = 2 * val_lot * lot * com_per / prices 
        risk_net = (balance * risk - comision).clip(lower=0).fillna(0)
        sl_pip =  risk_net /  tick_val
        tp_pip = sl_pip * wl_rate
        sl_valb = prices - sl_pip * tick * alpha
        tp_valb = prices + tp_pip * tick * alpha
        sl_vals = prices + sl_pip * tick * alpha
        tp_vals = prices - tp_pip * tick * alpha

        return sl_valb, tp_valb, sl_vals, tp_vals
    
    def _check_tp_sl(self, df, horizon, m_val = 0):
        highs, lows = df["high"].values, df["low"].values
        slb, tpb = df["sl_buy"].values, df["tp_buy"].values
        sls, tps = df["sl_sell"].values, df["tp_sell"].values

        # Ventanas deslizantes
        hw, lw = sliding_window_view(highs, horizon), sliding_window_view(lows, horizon)

        # BUY
        hit_sl_b = (lw <= slb[:-horizon+1, None])
        hit_tp_b = (hw >= tpb[:-horizon+1, None])
        idx_sl_b = np.argmax(hit_sl_b, 1); idx_sl_b[~hit_sl_b.any(1)] = horizon
        idx_tp_b = np.argmax(hit_tp_b, 1); idx_tp_b[~hit_tp_b.any(1)] = horizon
        result_buy = np.where(idx_sl_b < idx_tp_b, 0, np.where(idx_tp_b < idx_sl_b, 1, 0))

        # SELL
        hit_sl_s = (hw >= sls[:-horizon+1, None])
        hit_tp_s = (lw <= tps[:-horizon+1, None])
        idx_sl_s = np.argmax(hit_sl_s, 1); idx_sl_s[~hit_sl_s.any(1)] = horizon
        idx_tp_s = np.argmax(hit_tp_s, 1); idx_tp_s[~hit_tp_s.any(1)] = horizon
        result_sell = np.where(idx_sl_s < idx_tp_s, 0, np.where(idx_tp_s < idx_sl_s, 1, 0))

        # Ajustar longitudes con padding
        result_buy = np.pad(result_buy, (0, len(df) - len(result_buy)), constant_values=0)
        result_sell = np.pad(result_sell, (0, len(df) - len(result_sell)), constant_values=0)

        # --- Procesar BUY ---
        df["result_buy"] = result_buy
        df["close_buy"] = df["result_buy"] * df["close"]
        df["close_buy_hor"] = (df["result_buy"] * df["close"].shift(-horizon)).fillna(0)
        df["m_buy"] = (df["close_buy_hor"] - df["close_buy"]) / horizon
        df["result_buy"] = (df["m_buy"] > m_val).astype("float32")

        # --- Procesar SELL ---
        df["result_sell"] = result_sell
        df["close_sell"] = df["result_sell"] * df["close"]
        df["close_sell_hor"] = (df["result_sell"] * df["close"].shift(-horizon)).fillna(0)
        df["m_sell"] = (df["close_sell"] - df["close_sell_hor"]) / horizon
        df["result_sell"] = (df["m_sell"] > m_val).astype("float32")

        return df        

# Verificar proporciones de clases
    def _check_label_balance(self, labels):
            buy_count = (labels == 1).sum()
            sell_count = (labels == -1).sum() 
            hold_count = (labels == 0).sum()
            
            print(f"Balance de etiquetas:")
            print(f"  BUY: {buy_count} ({buy_count/len(labels)*100:.1f}%)")
            print(f"  SELL: {sell_count} ({sell_count/len(labels)*100:.1f}%)")
            print(f"  HOLD: {hold_count} ({hold_count/len(labels)*100:.1f}%)")
            if hold_count/len(labels) > 0.8:
                print("HOLD muy dominante - considerar balanceo")