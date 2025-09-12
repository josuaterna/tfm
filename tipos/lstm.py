import sys, os
import json
import torch
import pandas as pd
import numpy as np
import joblib  
import os
import pywt # type: ignore
import torch.nn as nn
from typing import Tuple
from datetime import datetime, timedelta
from torch.utils.data import Dataset, DataLoader
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
from src.train import Trainer

class LSTM_class():
    def __init__(self, indicadores):
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.entrenador = Trainer(indicadores)
        self.model = None
        self.scaler = None
        self.seq_len = 50

    def lstm_train(self, simbolo, fecha_ini, fecha_fin):
        # ventana_historica = int(input("Ventana histórica (días): ").strip())
        ventana_historica = 60
        # actualizacion = int(input("Periodo de actualización (días): ").strip())
        actualizacion = 7
        start_date, end_date = pd.to_datetime(fecha_ini), pd.to_datetime(fecha_fin)
        hist_start = start_date - timedelta(days=ventana_historica)
        all_signals = []
        current_train_end = start_date - timedelta(minutes=5)
        current_test_start = start_date
        df_full = self.entrenador.obj_datamanager.get_data(
            simbolo,
            hist_start.strftime("%Y-%m-%d"),
            end_date.strftime("%Y-%m-%d"),
            timeframe="M5"
        )
        if df_full is None or len(df_full) < 500:
            print("ERROR: Insuficientes datos")
            return
        while current_test_start < end_date:
            current_test_end = min(current_test_start + timedelta(days=actualizacion), end_date)

            df_train = df_full.loc[current_train_end - timedelta(days=ventana_historica):current_train_end]
            df_test = df_full.loc[current_test_start:current_test_end]

            if len(df_train) < 500 or len(df_test) < 100:
                print(f"ERROR: Datos insuficientes en {current_test_start} → {current_test_end}")
                current_train_end = current_test_end
                current_test_start = current_test_end
                continue
            # Reentrenar modelo
            self.train_model(df_train, window_days=ventana_historica, verbose=False)    
            
            signals = self.generate_signals(df_test,simbolo)
            all_signals.extend(signals)
            print(f"✔ Bloque {current_test_start.date()} → {current_test_end.date()} ({len(signals)} señales)")

            current_train_end = current_test_end
            current_test_start = current_test_end

        # Guardar resultados
        output_file = f"real_backtest_signals_{simbolo}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(output_file, "w", encoding="utf-16-le") as f:
            json.dump(all_signals, f, indent=2)

        print(f"\n✅ Backtest terminado. Total señales: {len(all_signals)}")
        print(f"Archivo guardado en: {output_file}")

    
    def train_model(self, df, window_days=60, epochs=5, batch_size=256, verbose=False):

        df = df.tail(window_days * 288)  # 288 velas M5 ≈ 1 día
        features = self.build_feature_matrix_from_df(df)
        labels = self.create_labels_from_prices(df['close'], future_bars=5, threshold=0.0001)

        if len(features) != len(labels):
            features, labels = features.align(pd.Series(labels, index=features.index), join="inner", axis=0)

        X = features.values
        self.model, self.scaler = self.train_lstm(
            X, labels, seq_len=self.seq_len,
            epochs=epochs, batch_size=batch_size,
            device=self.device, verbose=verbose
        )
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
        # scale features (fit on train split later)
        # Build sequences
        X_seq, y_seq = self.create_sequences(X, y, seq_len=seq_len)
        # drop samples where label is 0 if you prefer binary (here keep all classes)
        # split by indices to avoid leakage
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