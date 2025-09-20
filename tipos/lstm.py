import sys, os
import json
import torch
import pandas as pd
import numpy as np
import joblib  
import os
import pywt # type: ignore
import torch.nn as nn
import matplotlib.pyplot as plt
import time
from typing import Tuple
from datetime import datetime, timedelta, timezone
from torch.utils.data import Dataset, DataLoader, TensorDataset
from sklearn.preprocessing import StandardScaler
from sklearn.preprocessing import MinMaxScaler
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, mean_absolute_error
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from src.train import Trainer

class LSTM_class():
    def __init__(self, indicadores, seq):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.entrenador = Trainer(indicadores)
        self.df_train = None
        self.model = None
        self.scaler = None
        self.seq_len = seq

    def lstm_train(self, simbolo, tiempo, fecha_ini, fecha_fin, ruta, th, fut_bar, bat):
        ventana_historica = int(input("Ventana histórica (días): ").strip())
        #ventana_historica = 30
        #1.M1  2.M5  3.M15  4.M30  5.H1  6.H4  7.D1"
        match tiempo:
            case 1:
                timeframe_var = "M1"
            case 2:
                timeframe_var = "M5"
            case 3:
                timeframe_var = "M15"
            case 4:
                timeframe_var = "M30"
            case 5:
                timeframe_var = "H1"
            case 6:
                timeframe_var = "H4"
            case 7:
                timeframe_var = "D1"
            case _:
                timeframe_var = "M5"


        actualizacion = int(input("Periodo de actualización (días): ").strip())
        #actualizacion = 7
        start_date, end_date = pd.to_datetime(fecha_ini), pd.to_datetime(fecha_fin)
        hist_start = start_date - timedelta(days=ventana_historica)
        all_signals = []
        current_train_end = start_date - timedelta(minutes=5)
        current_test_start = start_date
        self.df_train = self.entrenador.obj_datamanager.get_data(
            simbolo,
            hist_start.strftime("%Y-%m-%d"),
            end_date.strftime("%Y-%m-%d"),
            timeframe=timeframe_var
        )
        if self.df_train is None or len(self.df_train) < 500:
            print("ERROR: Insuficientes datos")
            return
        while current_test_start < end_date:
            current_test_end = min(current_test_start + timedelta(days=actualizacion), end_date)

            df_train = self.df_train.loc[current_train_end - timedelta(days=ventana_historica):current_train_end]
            df_test = self.df_train.loc[current_test_start:current_test_end]

            if len(df_train) < 500 or len(df_test) < 100:
                print(f"ERROR: Datos insuficientes en {current_test_start} → {current_test_end}")
                current_train_end = current_test_end
                current_test_start = current_test_end
                continue
            # Reentrenar modelo
            self.train_model(df_train, fut_bar, th, window_days=ventana_historica, batch_size=bat, verbose=False)    
            
            signals = self.generate_signals(df_test,simbolo)
            all_signals.extend(signals)
            print(f"✔ Bloque {current_test_start.date()} → {current_test_end.date()} ({len(signals)} señales)")

            current_train_end = current_test_end
            current_test_start = current_test_end

        # Guardar resultados
        #output_file = f"real_backtest_signals_{simbolo}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        output_file = os.path.join(ruta, f"real_backtest_signals_{simbolo}.json")
        with open(output_file, "w", encoding="utf-16-le") as f:
            json.dump(all_signals, f, indent=2)

        print(f"\n✅ Backtest terminado. Total señales: {len(all_signals)}")
        print(f"Archivo guardado en: {output_file}")
    
    def train_model(self, df, fut_bar, th, window_days=60, epochs=5, batch_size=256, verbose=False):

        df = df.tail(window_days * 288)  # 288 velas M5 ≈ 1 día
        features = self.build_feature_matrix_from_df(df)
        labels = self.create_labels_from_prices(df['close'], future_bars=fut_bar, threshold=th)
        
        if len(features) != len(labels):
            features, labels = features.align(pd.Series(labels, index=features.index), join="inner", axis=0)

        X = features.values
        self.model, self.scaler = self.train_lstm(
            X, labels, seq_len=self.seq_len,
            epochs=epochs, batch_size=batch_size,
            device=self.device, verbose=verbose
        )
        self.guardar(self.model,self.scaler)

    def guardar(self, modelo, scaler):
        torch.save(modelo.state_dict(), "lstm_model.pth")
        joblib.dump(scaler, "scaler.pkl")

    def cargar(self, modelo = "lstm_model.pth", scaler = "scaler.pkl"):
        self.scaler = joblib.load(scaler)
        self.model = LSTMClassifier(self.scaler.mean_.shape[0]).to(self.device)
        self.model.load_state_dict(torch.load(modelo, map_location=self.device))
        self.model.eval()

    def cargar_ii(self, modelo = "lstm_model.pth", scaler = "scaler.pkl"):
        self.scaler = joblib.load(scaler)
        # Cargar modelo
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.model = LSTMClassifier_ii(input_dim=1, output_dim=1, device=self.device).to(self.device)
        # Cargar pesos al modelo
        self.model.load_state_dict(torch.load(modelo, map_location=self.device))
        self.model.eval()
        
    def generate_signals(self, df, simbolo, confidence_threshold=0.6):
        """
        Genera señales sobre un dataframe de precios.
        """
        signals = []
        features = self.build_feature_matrix_from_df(df)

        if self.model is None or self.scaler is None:
            raise ValueError("El modelo no está entrenado. Llama primero a train_model.")

        X_scaled = self.scaler.transform(features.values)

        with torch.no_grad():
            for i in range(len(X_scaled) - self.seq_len):
                seq = torch.tensor(X_scaled[i:i+self.seq_len], dtype=torch.float32, device=self.device).unsqueeze(0)
                seq.to(self.device)
                output = self.model(seq)
                probs = torch.softmax(output, dim=1)
                signal = torch.argmax(output, dim=1).item() - 1  # {0:-1, 1:0, 2:1}
                confidence = torch.max(probs).item()
                #print("Pred:", signal, "Conf:", confidence, "Fecha:", df.index[i+self.seq_len])
                ts = df.index[i + self.seq_len]                       # pandas.Timestamp
                timestamp_str = ts.strftime("%Y-%m-%d %H:%M:%S")
                datetime_mt5 = int(ts.timestamp())                    # entero Unix seconds
                if confidence >= confidence_threshold and signal != 0:
                    signals.append({
                        "timestamp": timestamp_str,
                        "datetime_mt5": int(datetime_mt5),
                        "signal": int(signal),
                        "confidence": float(confidence),
                        "price": float(df["close"].iloc[i+self.seq_len]),
                        "symbol": simbolo
                    })
        return signals

    def run_realtime_lstm(self, simbolo, ruta, tiempo, modelo_path="lstm_model.pth", scaler_path="scaler.pkl"):
        """
        Ejecuta predicciones en vivo cada 5 minutos usando LSTM_class.
        Guarda las señales en un archivo JSON único por símbolo.
        """
        match tiempo:
            case 1:
                timeframe_var = "M1"
                lapso = 1
            case 2:
                timeframe_var = "M5"
                lapso = 5
            case 3:
                timeframe_var = "M15"
                lapso = 15
            case 4:
                timeframe_var = "M30"
                lapso = 30
            case 5:
                timeframe_var = "H1"
                lapso = 60
            case 6:
                timeframe_var = "H4"
                lapso = 240
            case 7:
                timeframe_var = "D1"
                lapso = 1440
            case _:
                timeframe_var = "M5"
                lapso = 5

        if self.model == None:
            self.cargar(modelo=modelo_path, scaler=scaler_path)

        print(f"✅ Modelo cargado en {self.device}. Esperando velas de {simbolo}...")

        # Nombre del archivo de salida
        output_file = os.path.join(ruta, f"signals_{simbolo.lower()}.json")

        # Si ya existe, cargar señales previas; si no, crear lista vacía
        # if os.path.exists(output_file):
            # with open(output_file, "r", encoding="utf-16-le") as f:
            #     try:
            #         all_signals = json.load(f)
            #     except json.JSONDecodeError:
            #         all_signals = []
        #else:
        #    all_signals = []
        all_signals = []
        while True:
            # Redondear al cierre de vela de 5m anterior en UTC
            now = datetime.now(timezone.utc).replace(second=0, microsecond=0)
            minute_offset = now.minute % lapso
            last_candle_time = now - timedelta(minutes=minute_offset)

            # Descargar datos recientes (ej: últimas 200 velas para features)
            #self.entrenador.obj_datamanager._simbolos_disponibles()
            df = self.entrenador.obj_datamanager.get_data_intervalos(
                simbolo,
                n=50,
                # (last_candle_time - timedelta(hours=20)).strftime("%Y-%m-%d %H:%M:%S"),
                # last_candle_time.strftime("%Y-%m-%d %H:%M:%S"),
                timeframe=timeframe_var
            )
            #df.to_csv(os.path.join(ruta_csv, "USDJPY_export.csv"))
            # df = pd.read_csv(os.path.join(ruta_csv, "USDJPY.csv"), index_col=0)
            # df.index = pd.to_datetime(df.index)
            # df = df.sort_index(ascending=True)

            if df is None or len(df) < self.seq_len:
                print("⚠️ No hay suficientes datos para generar secuencia.")
            else:
                # Generar señal solo para la última vela
                signals = self.generate_signals(df, simbolo)
                if signals:
                    ultima = signals[-1]
                    all_signals.append(ultima)

                    # Guardar en archivo
                    with open(output_file, "w", encoding="utf-16-le") as f:
                        json.dump(all_signals, f, indent=2)

                    print(f"📈 Señal guardada: {ultima['signal']} | "
                        f"Conf={ultima['confidence']:.2f} | "
                        f"Precio={ultima['price']} | "
                        f"{ultima['timestamp']}")
                else:
                    print(f"ℹ️ Sin señal válida en {last_candle_time}")

            # Esperar hasta el próximo cierre de vela
            next_check = last_candle_time + timedelta(minutes=lapso)
            sleep_seconds = (next_check - datetime.now(timezone.utc)).total_seconds()
            if sleep_seconds > 0:
                time.sleep(sleep_seconds)

    
    def train_lstm(self, X, y,
               seq_len=50,
               test_size=0.2,
               batch_size=128,
               epochs=20,
               lr=1e-3,
               device=None,
               verbose=True):
        if device is None:
            device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        X_seq, y_seq = self.create_sequences(X, y, seq_len=seq_len)
        idx = np.arange(len(X_seq))
        train_idx, val_idx = train_test_split(idx, test_size=test_size, shuffle=True, stratify=y_seq)
        # scale on training set
        scaler = StandardScaler()
        # flatten train features to fit scaler: (n_samples*seq_len, n_feats)
        n_feats = X_seq.shape[2]
        scaler.fit(X_seq[train_idx].reshape(-1, n_feats))
        X_seq = scaler.transform(X_seq.reshape(-1, n_feats)).reshape(X_seq.shape)
        # datasets
        train_ds = SequenceDataset(X_seq[train_idx], y_seq[train_idx])
        val_ds = SequenceDataset(X_seq[val_idx], y_seq[val_idx])
        train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
        val_loader = DataLoader(val_ds, batch_size=batch_size, shuffle=False)

        model = LSTMClassifier(n_features=n_feats).to(device)

        # Calcular distribución de clases
        y_mapped = y_seq + 1   # -1->0, 0->1, 1->2
        class_counts = np.bincount(y_mapped, minlength=3)
        class_weights = 1.0 / torch.tensor(class_counts, dtype=torch.float32)
        class_weights = class_weights / class_weights.sum()  # normalizar

        print("Distribución de clases:", class_counts)
        print("Pesos aplicados:", class_weights)

        criterion = nn.CrossEntropyLoss(weight=class_weights.to(device))
        optimizer = torch.optim.Adam(model.parameters(), lr=lr)

        best_val_acc = 0.0
        for epoch in range(1, epochs+1):
            model.train()
            total_loss = 0.0
            correct = 0
            total = 0
            for xb, yb in train_loader:
                xb = xb.to(device); yb = yb.to(device)
                optimizer.zero_grad()
                logits = model(xb)
                loss = criterion(logits, yb)
                loss.backward()
                optimizer.step()
                total_loss += loss.item() * xb.size(0)
                preds = logits.argmax(dim=1)
                correct += (preds == yb).sum().item()
                total += xb.size(0)
            train_loss = total_loss/total
            train_acc = correct/total
            # validation
            model.eval()
            vcorrect = 0; vtotal = 0; vloss = 0.0
            with torch.no_grad():
                for xb, yb in val_loader:
                    xb = xb.to(device); yb = yb.to(device)
                    logits = model(xb)
                    loss = criterion(logits, yb)
                    vloss += loss.item() * xb.size(0)
                    preds = logits.argmax(dim=1)
                    vcorrect += (preds == yb).sum().item()
                    vtotal += xb.size(0)
            val_loss = vloss / vtotal
            val_acc = vcorrect / vtotal
            if verbose:
                print(f"Epoch {epoch}/{epochs} - train_loss={train_loss:.4f} acc={train_acc:.4f} | val_loss={val_loss:.4f} val_acc={val_acc:.4f}")
            if val_acc > best_val_acc:
                best_val_acc = val_acc
                torch.save({
                    "model_state": model.state_dict(),
                    "scaler": scaler
                }, "best_lstm_wavelet.pth")
        return model, scaler
    
    def create_sequences(self, X: np.ndarray, y: np.ndarray, seq_len:int=50) -> Tuple[np.ndarray, np.ndarray]:
        seq_X = []
        seq_y = []
        N = len(X)
        print(f"len(X) {len(X)}")
        for i in range(seq_len-1, N):
            seq_X.append(X[i-seq_len+1:i+1])
            seq_y.append(y[i])
        return np.array(seq_X), np.array(seq_y)

    def build_feature_matrix_from_df(self, df: pd.DataFrame,
                                 wavelet='db4',
                                 level=1,
                                 add_features=True) -> pd.DataFrame:
        close = df['close'].values
        # Eliminar ruido de la serie usando wavelets:
        denoised = self.wavelet_denoise_series(close, wavelet, level)
        features_nobin = pd.DataFrame(index=df.index)
        features_bin = pd.DataFrame(index=df.index)
        features = pd.DataFrame(index=df.index)
        features_nobin['close'] = close
        features_nobin['denoised_close'] = denoised
        # Indicadores simples para probar
        features_nobin['ret_1'] = features_nobin['close'].pct_change().fillna(0)
        features_nobin['ma_10'] = pd.Series(features_nobin['close']).rolling(10, min_periods=1).mean().values
        features_nobin['ma_50'] = pd.Series(features_nobin['close']).rolling(50, min_periods=1).mean().values
        features_nobin['ma_diff'] = features_nobin['ma_10'] - features_nobin['ma_50']
        tech_ind = self.entrenador.obj_indicadores
        features_bin = tech_ind.get_feature_matrix(df)
        features = pd.concat([features_nobin, features_bin], axis=1)
        if add_features:
            # Normalizar algunos indicadores
            features['vol'] = pd.Series(features['ret_1']).rolling(20).std().fillna(0).values
        # Llenar con 0 los NaN
        features = features.bfill().fillna(0)
        return features

    def wavelet_denoise_series(self, series: np.ndarray, wavelet, level) -> np.ndarray:

        coeffs = pywt.wavedec(series, wavelet, mode='symmetric')
        # soft thresholding for detail coefficients
        sigma = np.median(np.abs(coeffs[-level])) / 0.6745 if level <= len(coeffs)-1 else 0
        uthresh = sigma * np.sqrt(2 * np.log(len(series))) if sigma > 0 else 0
        denoised_coeffs = coeffs[:]
        for i in range(1, level+1):
            denoised_coeffs[-i] = pywt.threshold(denoised_coeffs[-i], value=uthresh, mode='soft')
        rec = pywt.waverec(denoised_coeffs, wavelet, mode='symmetric')
        return rec[:len(series)]

    def create_labels_from_prices(self, prices: pd.Series, future_bars, threshold) -> np.ndarray:
        future = prices.shift(-future_bars)
        future_return = (future - prices) / prices
        labels = np.zeros(len(prices), dtype=int)
        labels[future_return > threshold] = 1
        labels[future_return < -threshold] = -1
        # Las últimas barras no pueden ser etiquetadas y quedan en 0
        return labels

    def lstm_train_ii(self, simbolo, fecha_ini, fecha_fin):        
        device = "cuda" if torch.cuda.is_available() else "cpu"

        # --------------------------
        # 1) cargar serie raw (sin escalar aún)
        # --------------------------
        self.df_train = self.entrenador.obj_datamanager.get_data(simbolo, fecha_ini, fecha_fin)
        series = self.df_train['close'].values.reshape(-1, 1)   # (N, 1)
        seq_len = 50

        if len(series) <= seq_len + 1:
            raise ValueError("Serie demasiado corta para seq_len")

        # --------------------------
        # 2) split temporal en RAW (no en secuencias)
        #    -> esto evita mezcla aleatoria de ventanas
        # --------------------------
        train_size = int(len(series) * 0.8)   # 80% tiempo para entrenamiento
        # opcional: definir test_size y val_size si lo deseas
        # train_raw = series[:train_size]
        # val_raw   = series[train_size:]

        # --------------------------
        # 3) scaler: FIT solo con train_raw, luego TRANSFORM toda la serie
        # --------------------------
        scaler = MinMaxScaler(feature_range=(0, 1))
        scaler.fit(series[:train_size])              # <- fit SOLO en train
        scaled_full = scaler.transform(series)       # <- transform de toda la serie con el scaler ajustado en train

        # --------------------------
        # 4) crear secuencias a partir de la serie escalada (sliding windows)
        # --------------------------
        X, y = self.create_sequences_ii(scaled_full, seq_len)   # X.shape = (N-seq_len, seq_len, features)
        print("X,y shapes (total):", X.shape, y.shape)

        # --------------------------
        # 5) SPLIT de secuencias de forma CONTIGUA (temporal)
        #    calculamos el índice correcto para que las secuencias de train terminen
        #    exactamente en train_size-1 del raw original
        # --------------------------
        split_idx = train_size - seq_len
        print("df index min/max:", self.df_train.index.min(), self.df_train.index.max())
        print("train_size:", train_size, "split_idx:", split_idx)
        print("y (scaled) stats -> min/max/mean/std:", y.min(), y.max(), y.mean(), y.std())

        if split_idx <= 0:
            raise ValueError("train_size demasiado pequeño respecto a seq_len")

        x_train, y_train = X[:split_idx], y[:split_idx]
        x_val,   y_val   = X[split_idx:], y[split_idx:]
        print(f"y_train = min {y_train.min()}, max {y_train.max()}")
        print("x_train, x_val shapes:", x_train.shape, x_val.shape)


        # --------------------------
        # 6) tensores y DataLoaders (batch_size=1 si quieres reproducir Keras)
        # --------------------------
        x_train_t = torch.tensor(x_train, dtype=torch.float32).to(device)
        y_train_t = torch.tensor(y_train, dtype=torch.float32).to(device)
        x_val_t   = torch.tensor(x_val,   dtype=torch.float32).to(device)
        y_val_t   = torch.tensor(y_val,   dtype=torch.float32).to(device)

        train_dataset = TensorDataset(x_train_t, y_train_t)
        val_dataset   = TensorDataset(x_val_t,   y_val_t)

        train_loader = DataLoader(train_dataset, batch_size=30, shuffle=True)   # shuffle ok SOLO en training
        val_loader   = DataLoader(val_dataset,   batch_size=30, shuffle=False)

        # --------------------------
        # 7) modelo, optim, loss, early stopping (igual a tu código)
        # --------------------------
        modelo = LSTMClassifier_ii().to(device)
        next(modelo.parameters()).device
        criterion = nn.MSELoss()
        optimizer = torch.optim.Adam(modelo.parameters(), lr=0.001)
        early_stopping = EarlyStopping(patience=10, restore_best_weights=True)

        # --------------------------
        # 8) loop de entrenamiento (igual que antes)
        # --------------------------
        epochs = 10
        for epoch in range(epochs):
            modelo.train()
            train_losses = []
            for X_batch, y_batch in train_loader:
                X_batch, y_batch = X_batch.to(device), y_batch.to(device)
                optimizer.zero_grad()
                outputs = modelo(X_batch)
                loss = criterion(outputs, y_batch.view(-1, 1))
                loss.backward()
                optimizer.step()
                outputs_np = outputs.detach().cpu().numpy()
                y_batch_np = y_batch.detach().cpu().numpy()
                # Reescalar a precios reales
                outputs_rescaled = scaler.inverse_transform(outputs_np.reshape(-1, 1))
                y_rescaled = scaler.inverse_transform(y_batch_np.reshape(-1, 1))
                # Calcular MSE en precios reales (fuera del grafo)
                loss_val = mean_squared_error(y_rescaled, outputs_rescaled)
                #train_losses.append(loss.item())
                train_losses.append(loss_val)  # aquí guardas el loss en escala real solo para monitoreo
            avg_train_loss = sum(train_losses) / len(train_losses)
            print(f"Epoch: {epoch} MSE {avg_train_loss}")
            modelo.eval()
            val_losses = []
            
            with torch.no_grad():
                for X_batch, y_batch in val_loader:
                    val_outputs = modelo(X_batch)
                    val_loss = criterion(val_outputs, y_batch)
                    val_losses.append(val_loss.item())

            avg_val_loss = sum(val_losses) / len(val_losses)
            print(f"Epoch {epoch+1}, Train Loss: {avg_train_loss:.6f}, Val Loss: {avg_val_loss:.6f}")

            if early_stopping.step(avg_val_loss, modelo):
                break
            print("\n--- Baseline vs Modelo (validación) ---")

            # Baseline: persistencia (último valor de la ventana)
            persistence_scaled = x_val[:, -1, 0].reshape(-1,1)   # último valor de cada ventana
            persistence_real = scaler.inverse_transform(persistence_scaled)
            y_val_real = scaler.inverse_transform(y_val.reshape(-1,1))

            rmse_persistence = np.sqrt(mean_squared_error(y_val_real, persistence_real))
            mae_persistence  = mean_absolute_error(y_val_real, persistence_real)
            print("Baseline persistence RMSE (precio):", rmse_persistence, "MAE:", mae_persistence)

            # Modelo en validación
            modelo.eval()
            with torch.no_grad():
                preds_scaled = modelo(torch.tensor(x_val, dtype=torch.float32).to(device)).cpu().numpy().reshape(-1,1)

            preds_real = scaler.inverse_transform(preds_scaled)
            rmse_model = np.sqrt(mean_squared_error(y_val_real, preds_real))
            mae_model  = mean_absolute_error(y_val_real, preds_real)
            print("Model RMSE (precio):", rmse_model, "MAE:", mae_model)

        # --------------------------
        # 9) guardar scaler y modelo si quieres
        # --------------------------
        torch.save(modelo.state_dict(), "lstm_model.pth")
        joblib.dump(scaler, "scaler.pkl")
    
    def create_sequences_ii(self, data, seq_len=50):
        X, y = [], []
        for i in range(seq_len, len(data)):
            X.append(data[i-seq_len:i])   # secuencia de precios
            y.append(data[i, 0])          # valor objetivo (ej: próximo cierre)
        return np.array(X), np.array(y)
    
    def forecast_future_range(self, model, df, scaler, fecha_pred_ini, fecha_pred_fin, seq_len=50, device="cpu", verbose=True):
        """
        Versión corregida y robusta:
        - Usa train_end = fecha_pred_ini - offset para construir la ventana inicial
        - Comprueba que el scaler corresponde al entrenamiento
        - Mantiene la entrada al modelo en escala normalizada y solo des-normaliza para graficar
        """
        model.eval()

        # 1) detectar freq
        freq = pd.infer_freq(df.index)
        if freq is None:
            diffs = df.index.to_series().diff().dropna()
            mode = diffs.mode()
            if len(mode) == 0:
                raise ValueError("No puedo inferir frecuencia del índice.")
            offset = mode[0]
        else:
            offset = pd.tseries.frequencies.to_offset(freq)

        # Prueba rápida del modelo en la ventana inicial:
        ultimos = df.loc[:pd.to_datetime(fecha_pred_ini) - pd.Timedelta(1, unit=freq)][-seq_len:]['close'].values.reshape(-1,1)
        scaled = scaler.transform(ultimos)
        X_test = torch.tensor(scaled.reshape(1, seq_len, 1), dtype=torch.float32).to(device)
        with torch.no_grad():
            out = model(X_test).cpu().numpy()
        print("sample model output (scaled):", out, " -> descaled:", scaler.inverse_transform(np.array(out).reshape(-1,1)).ravel())

        # Fin prueba
        
        fecha_pred_ini = pd.to_datetime(fecha_pred_ini)
        fecha_pred_fin = pd.to_datetime(fecha_pred_fin)
        train_end = fecha_pred_ini - offset

        if verbose:
            print("freq:", freq, "offset:", offset)
            print("train_end (última obs usada para generar forecast):", train_end)

        # 2) comprobar que existen suficientes datos anteriores a train_end
        if df.index[df.index < fecha_pred_ini].empty:
            raise ValueError("No hay datos anteriores a fecha_pred_ini en el df.")
        # usar sólo datos hasta train_end para construir la ventana inicial
        train_df = df.loc[:train_end]
        if len(train_df) < seq_len:
            raise ValueError(f"No hay suficientes observaciones hasta {train_end} para seq_len={seq_len}")

        # 3) comprobar tipo de scaler (diagnóstico)
        if verbose:
            print("Scaler type:", type(scaler))
            if hasattr(scaler, "min_"):
                print("scaler.data_min_ (first 3):", getattr(scaler, "data_min_", None))
                print("scaler.data_max_ (first 3):", getattr(scaler, "data_max_", None))

        # 4) construir ventana inicial en ESCALA normalizada (lista de floats)
        ultimos_precios = train_df['close'].values[-seq_len:].reshape(-1, 1)
        scaled_window = scaler.transform(ultimos_precios).flatten().tolist()  # lista de floats

        # 5) preparar fechas/pasos
        fechas_futuras = pd.date_range(start=fecha_pred_ini, end=fecha_pred_fin, freq=freq)
        pasos = len(fechas_futuras)
        if pasos <= 0:
            raise ValueError("El rango de fechas no genera pasos futuros válidos.")

        preds = []

        # 6) bucle predictivo (auto-regresivo)
        for step in range(pasos):
            # Entrada con la forma correcta: (1, seq_len, 1)
            X_input = torch.tensor(scaled_window[-seq_len:], dtype=torch.float32).view(1, seq_len, 1).to(device)

            with torch.no_grad():
                 pred_scaled = model(X_input).cpu().numpy()  # shape (1,1) o (1,) según modelo

            # Asegurarnos formato (1,1)
            pred_scaled = np.array(pred_scaled).reshape(1, 1)

            # Desnormalizar SOLO para almacenar/plot (no para alimentar)
            pred_scaled = np.clip(pred_scaled, 0.0, 1.0)
            pred_real = scaler.inverse_transform(pred_scaled)[0, 0]
            preds.append(pred_real)

            # Alimentar la siguiente ventana CON la predicción en escala normalizada
            scaled_window.append(float(pred_scaled[0, 0]))

            if verbose and step < 5:
                print(f"step {step}: pred_scaled={pred_scaled[0,0]:.6f}, pred_real={pred_real:.6f}")

        # 7) construir DataFrame y graficar (histórico hasta train_end)
        df_preds = pd.DataFrame({"fecha": fechas_futuras, "prediccion": preds}).set_index("fecha")

        plt.figure(figsize=(12,6))
        df.loc[:train_end]['close'].tail(200).plot(label="Histórico (hasta corte)", color="blue")
        df_preds['prediccion'].plot(label="Pronóstico", color="red", linestyle="--")
        plt.axvline(train_end, color="gray", linestyle="dashed", label="Corte (train_end)")
        plt.title(f"Forecast desde {fecha_pred_ini} hasta {fecha_pred_fin}")
        plt.xlabel("Fecha"); plt.ylabel("Precio"); plt.legend(); plt.show()

        return df_preds

class LSTMClassifier(nn.Module):
    def __init__(self, n_features:int, hidden_size=64, n_layers=2, dropout=0.2, num_classes=3):
        super().__init__()
        self.lstm = nn.LSTM(input_size=n_features, hidden_size=hidden_size,
                            num_layers=n_layers, batch_first=True, dropout=dropout)
        self.fc = nn.Sequential(
            nn.Linear(hidden_size, 64),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(64, num_classes)
        )

    def forward(self, x):
        # x: (batch, seq_len, features)
        out, (hn, cn) = self.lstm(x)
        # take last timestep
        last = out[:, -1, :]
        return self.fc(last)       
    
class SequenceDataset(Dataset):
    def __init__(self, X: np.ndarray, y: np.ndarray):
        self.X = torch.tensor(X, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.long)  # classes -1/0/1 -> we'll remap to 0/1/2
    def __len__(self): return len(self.X)
    def __getitem__(self, idx):
        return self.X[idx], self.y[idx] + 1  # remap: -1->0,0->1,1->2
    
# Predicción de precios
class LSTMClassifier_ii(nn.Module):
    def __init__(self, input_dim=1, hidden_dim=128, output_dim=1, dropout=0.2, device="cpu"):
        super(LSTMClassifier_ii, self).__init__()
        self.device = device
        # LSTM con 2 capas (128 y 64 unidades como en tu Keras)
        self.lstm1 = nn.LSTM(input_size=input_dim, hidden_size=hidden_dim, batch_first=True, dropout=0, num_layers=1)
        self.lstm2 = nn.LSTM(input_size=hidden_dim, hidden_size=64, batch_first=True, dropout=dropout, num_layers=1)
        # Capa fully connected equivalente a Dense(25) y Dense(1)
        self.fc1 = nn.Linear(64, 25)
        self.fc2 = nn.Linear(25, output_dim)

    def forward(self, x):
        # LSTM devuelve (output, (h_n, c_n))
        out, _ = self.lstm1(x)
        out, (hn, cn) = self.lstm2(out)
        # Como return_sequences=False en la última capa de Keras → usar la última salida
        out = out[:, -1, :]  # última capa oculta
        # Pasar por las capas fully connected
        out = torch.relu(self.fc1(out))
        #out = self.fc2(out)
        #out = torch.sigmoid(self.fc2(torch.relu(self.fc1(out))))
        out = torch.sigmoid(self.fc2(out)) # (batch, 1), en [0,1]
        return out

class TimeSeriesDataset(Dataset):
    def __init__(self, X, y):
        self.X = torch.tensor(X, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.float32)

    def __len__(self):
        return len(self.X)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]
    
class EarlyStopping:
    def __init__(self, patience=10, restore_best_weights=True):
        self.patience = patience
        self.restore_best_weights = restore_best_weights
        self.best_loss = np.inf
        self.counter = 0
        self.best_state = None

    def step(self, val_loss, model):
        if val_loss < self.best_loss:  # mejora
            self.best_loss = val_loss
            self.counter = 0
            if self.restore_best_weights:
                self.best_state = {k: v.cpu().clone() for k, v in model.state_dict().items()}
        else:
            self.counter += 1

        if self.counter >= self.patience:
            print("⏹️ Early stopping triggered")
            if self.restore_best_weights and self.best_state is not None:
                model.load_state_dict(self.best_state)
            return True  # detener entrenamiento
        return False
