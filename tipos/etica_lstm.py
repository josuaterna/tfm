# etica_lstm_torch.py
import numpy as np
import pandas as pd
from sklearn.preprocessing import MinMaxScaler
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
from typing import Tuple, Dict, List

# --------------------------
# 1) ETICA: returns + decomposition
# --------------------------
def compute_returns_pct(prices: pd.DataFrame) -> pd.DataFrame:
    return prices.pct_change().fillna(0) * 100.0

def compute_a_i(p_returns: pd.DataFrame) -> pd.Series:
    numer = p_returns.sum(axis=0)
    denom = numer.sum() if numer.sum() != 0 else 1e-12
    return numer / denom

def compute_etica_components(p_returns: pd.DataFrame) -> Tuple[pd.DataFrame, pd.DataFrame]:
    a_i = compute_a_i(p_returns)
    cross_sum = p_returns.sum(axis=1)
    p_ext = pd.DataFrame(np.outer(cross_sum.values, a_i.values),
                         index=p_returns.index, columns=p_returns.columns)
    p_int = p_returns - p_ext
    return p_ext, p_int

def reconstruct_price_components(prices: pd.DataFrame,
                                 p_ext: pd.DataFrame,
                                 p_int: pd.DataFrame) -> Tuple[pd.DataFrame, pd.DataFrame]:
    P_prev = prices.shift(1).fillna(method='bfill')
    P_int = (p_int.div(100.0).values * P_prev.values) + (P_prev.values / 2.0)
    P_ext = (p_ext.div(100.0).values * P_prev.values) + (P_prev.values / 2.0)
    return (pd.DataFrame(P_int, index=prices.index, columns=prices.columns),
            pd.DataFrame(P_ext, index=prices.index, columns=prices.columns))

# --------------------------
# 2) Dataset + PyTorch Model
# --------------------------
def build_univariate_sequences(series: np.ndarray, seq_len:int):
    N = len(series)
    X, y = [], []
    for i in range(seq_len, N):
        X.append(series[i-seq_len:i])
        y.append(series[i])
    X = np.array(X).reshape(-1, seq_len, 1)
    y = np.array(y).reshape(-1,1)
    return X, y

class LSTMRegressor(nn.Module):
    def __init__(self, input_size=1, hidden_size=64, num_layers=1, dropout=0.2):
        super(LSTMRegressor, self).__init__()
        self.lstm = nn.LSTM(input_size, hidden_size, num_layers, batch_first=True, dropout=dropout)
        self.fc = nn.Linear(hidden_size, 1)

    def forward(self, x):
        out, _ = self.lstm(x)
        out = out[:, -1, :]  # última salida
        out = self.fc(out)
        return out

# --------------------------
# 3) Entrenar ETICA-LSTM con PyTorch
# --------------------------
def train_etica_lstm_torch(prices: pd.Series,
                           universe_prices: pd.DataFrame,
                           seq_len:int = 15,
                           epochs:int = 50,
                           batch_size:int = 32,
                           lr:float = 0.001,
                           device:str = "cuda"):
    # 1) ETICA decomposition
    p_returns = compute_returns_pct(universe_prices)
    p_ext_df, p_int_df = compute_etica_components(p_returns)
    P_int_df, P_ext_df = reconstruct_price_components(universe_prices, p_ext_df, p_int_df)

    symbol = prices.name
    P_int = P_int_df[symbol]
    P_ext = P_ext_df[symbol]

    # 2) Normalize
    scaler_int = MinMaxScaler((0,1))
    scaler_ext = MinMaxScaler((0,1))
    P_int_scaled = scaler_int.fit_transform(P_int.values.reshape(-1,1)).flatten()
    P_ext_scaled = scaler_ext.fit_transform(P_ext.values.reshape(-1,1)).flatten()

    # 3) Build sequences
    X_int, y_int = build_univariate_sequences(P_int_scaled, seq_len)
    X_ext, y_ext = build_univariate_sequences(P_ext_scaled, seq_len)
    n = min(len(X_int), len(X_ext))
    X_int, y_int = X_int[:n], y_int[:n]
    X_ext, y_ext = X_ext[:n], y_ext[:n]

    # 4) Tensors & DataLoader
    Xint_t = torch.tensor(X_int, dtype=torch.float32).to(device)
    yint_t = torch.tensor(y_int, dtype=torch.float32).to(device)
    Xext_t = torch.tensor(X_ext, dtype=torch.float32).to(device)
    yext_t = torch.tensor(y_ext, dtype=torch.float32).to(device)

    dloader_int = DataLoader(TensorDataset(Xint_t,yint_t), batch_size=batch_size, shuffle=True)
    dloader_ext = DataLoader(TensorDataset(Xext_t,yext_t), batch_size=batch_size, shuffle=True)

    # 5) Models
    model_int = LSTMRegressor().to(device)
    model_ext = LSTMRegressor().to(device)
    loss_fn = nn.MSELoss()
    opt_int = torch.optim.Adam(model_int.parameters(), lr=lr)
    opt_ext = torch.optim.Adam(model_ext.parameters(), lr=lr)

    # 6) Training loop
    model_int.train(); model_ext.train()
    for epoch in range(epochs):
        # --- Internal ---
        for xb,yb in dloader_int:
            xb,yb = xb.to(device), yb.to(device)
            opt_int.zero_grad()
            preds = model_int(xb)
            loss = loss_fn(preds,yb)
            loss.backward()
            opt_int.step()
        # --- External ---
        for xb,yb in dloader_ext:
            xb,yb = xb.to(device), yb.to(device)
            opt_ext.zero_grad()
            preds = model_ext(xb)
            loss = loss_fn(preds,yb)
            loss.backward()
            opt_ext.step()

    return {
        "model_int": model_int,
        "model_ext": model_ext,
        "scaler_int": scaler_int,
        "scaler_ext": scaler_ext,
        "seq_len": seq_len,
        "p_int_series": P_int,
        "p_ext_series": P_ext
    }

# --------------------------
# 4) Predicción + Señales
# --------------------------
def predict_and_generate_signals_torch(trained:dict,
                                       prices: pd.Series,
                                       threshold:float=0.002,
                                       device:str="cpu") -> List[Dict]:
    seq_len = trained["seq_len"]
    P_int, P_ext = trained["p_int_series"], trained["p_ext_series"]
    s_int, s_ext = trained["scaler_int"], trained["scaler_ext"]

    P_int_scaled = s_int.transform(P_int.values.reshape(-1,1)).flatten()
    P_ext_scaled = s_ext.transform(P_ext.values.reshape(-1,1)).flatten()

    X_int,_ = build_univariate_sequences(P_int_scaled, seq_len)
    X_ext,_ = build_univariate_sequences(P_ext_scaled, seq_len)
    n = min(len(X_int), len(X_ext))
    X_int, X_ext = X_int[:n], X_ext[:n]

    Xint_t = torch.tensor(X_int, dtype=torch.float32).to(device)
    Xext_t = torch.tensor(X_ext, dtype=torch.float32).to(device)

    model_int = trained["model_int"].to(device)
    model_ext = trained["model_ext"].to(device)
    model_int.eval(); model_ext.eval()

    with torch.no_grad():
        pred_int_scaled = model_int(Xint_t).cpu().numpy().flatten()
        pred_ext_scaled = model_ext(Xext_t).cpu().numpy().flatten()

    pred_int = s_int.inverse_transform(pred_int_scaled.reshape(-1,1)).flatten()
    pred_ext = s_ext.inverse_transform(pred_ext_scaled.reshape(-1,1)).flatten()
    P_pred = pred_int + pred_ext

    timestamps = prices.index[seq_len: seq_len+len(P_pred)]
    signals = []
    for ts,p_pred,p_curr in zip(timestamps,P_pred,prices.loc[timestamps].values):
        exp_ret = (p_pred - p_curr)/(p_curr+1e-12)
        if exp_ret > threshold:
            sig = 1
        elif exp_ret < -threshold:
            sig = -1
        else:
            sig = 0
        conf = float(min(1.0, abs(exp_ret)/0.01))
        signals.append({
            "timestamp": pd.to_datetime(ts).isoformat(),
            "datetime_mt5": int(pd.to_datetime(ts).timestamp()),
            "symbol": prices.name,
            "price": float(p_curr),
            "pred_price": float(p_pred),
            "expected_return": float(exp_ret),
            "signal": sig,
            "confidence": conf
        })
    return signals
