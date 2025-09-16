import numpy as np
import pandas as pd
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from sklearn.preprocessing import StandardScaler
import joblib
import matplotlib.pyplot as plt

# -----------------------------
# 1. Dataset para series de tiempo
# -----------------------------
class TimeSeriesDataset(Dataset):
    def __init__(self, X, y):
        self.X = torch.tensor(X, dtype=torch.float32)
        self.y = torch.tensor(y, dtype=torch.float32)

    def __len__(self):
        return len(self.X)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]

# -----------------------------
# 2. Modelo LSTM para retornos
# -----------------------------
class LSTMReturns(nn.Module):
    def __init__(self, input_size=1, hidden_size=64, num_layers=2):
        super().__init__()
        self.lstm = nn.LSTM(input_size, hidden_size, num_layers, batch_first=True, dropout=0.2)
        self.fc = nn.Linear(hidden_size, 1)  # salida: retorno
    def forward(self, x):
        out, _ = self.lstm(x)
        out = self.fc(out[:, -1, :])  # solo último paso
        return out

# -----------------------------
# 3. Crear secuencias (X = precios escalados, y = retornos REALES)
# -----------------------------
def create_sequences_returns(prices_scaled, returns_scaled, seq_len=50):
    X, y = [], []
    for i in range(seq_len, len(returns_scaled)):
        X.append(prices_scaled[i-seq_len:i])   # ventana de precios
        y.append(returns_scaled[i])            # retorno (escalado)
    return np.array(X), np.array(y)

# -----------------------------
# 4. Entrenamiento + guardado
# -----------------------------
def train_and_save_returns(df, simbolo, seq_len=50, epochs=30, batch_size=32, device="cuda"):
    # --- precios reales
    prices = df["close"].values.reshape(-1, 1)
    returns = (prices[1:] - prices[:-1]) / prices[:-1]

    # --- escaladores separados
    scaler_prices = StandardScaler()
    scaler_returns = StandardScaler()
    prices_scaled = scaler_prices.fit_transform(prices)
    returns_scaled = scaler_returns.fit_transform(returns)

    # --- construir dataset
    X, y = create_sequences_returns(prices_scaled[:-1], returns_scaled, seq_len)
    split = int(len(X) * 0.8)
    x_train, x_val = X[:split], X[split:]
    y_train, y_val = y[:split], y[split:]

    train_loader = DataLoader(TimeSeriesDataset(x_train, y_train), batch_size=batch_size, shuffle=True)
    val_loader   = DataLoader(TimeSeriesDataset(x_val, y_val), batch_size=batch_size, shuffle=False)

    # --- modelo
    model = LSTMReturns().to(device)
    criterion = nn.MSELoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.001)

    # --- entrenamiento
    for epoch in range(epochs):
        model.train()
        train_losses = []
        for Xb, yb in train_loader:
            Xb, yb = Xb.to(device), yb.to(device).view(-1, 1)
            optimizer.zero_grad()
            outputs = model(Xb)
            loss = criterion(outputs, yb)
            loss.backward()
            optimizer.step()
            train_losses.append(loss.item())

        model.eval()
        val_losses = []
        with torch.no_grad():
            for Xb, yb in val_loader:
                Xb, yb = Xb.to(device), yb.to(device).view(-1, 1)
                outputs = model(Xb)
                val_losses.append(criterion(outputs, yb).item())

        print(f"Epoch {epoch+1}/{epochs}, Train Loss: {np.mean(train_losses):.6f}, Val Loss: {np.mean(val_losses):.6f}")

    # --- guardar modelo y scalers
    torch.save(model.state_dict(), f"lstm_returns_{simbolo}.pth")
    joblib.dump(scaler_prices, f"scaler_prices_{simbolo}.pkl")
    joblib.dump(scaler_returns, f"scaler_returns_{simbolo}.pkl")
    print(f"✅ Modelo y scalers guardados para {simbolo}")

    return model, scaler_prices, scaler_returns

# -----------------------------
# 5. Forecast autoregresivo
# -----------------------------
def load_and_forecast_returns(df, simbolo, fecha_pred_ini, fecha_pred_fin, seq_len=50, device="cuda"):
    # --- cargar modelo y scalers
    scaler_prices = joblib.load(f"scaler_prices_{simbolo}.pkl")
    scaler_returns = joblib.load(f"scaler_returns_{simbolo}.pkl")

    model = LSTMReturns().to(device)
    model.load_state_dict(torch.load(f"lstm_returns_{simbolo}.pth", map_location=device))
    model.eval()

    # --- precios históricos
    prices = df["close"].values.reshape(-1, 1)
    last_prices = prices[-seq_len:]  # últimos N precios reales
    last_scaled = scaler_prices.transform(last_prices)

    # --- fechas futuras
    freq = pd.infer_freq(df.index)
    if freq is None:
        freq = df.index.to_series().diff().mode()[0]
    fechas_futuras = pd.date_range(start=fecha_pred_ini, end=fecha_pred_fin, freq=freq)

    preds = []
    scaled_window = last_scaled.tolist()
    last_real_price = last_prices[-1, 0]

    for _ in range(len(fechas_futuras)):
        X_input = torch.tensor([scaled_window[-seq_len:]], dtype=torch.float32).to(device)
        with torch.no_grad():
            pred_ret_scaled = model(X_input).cpu().numpy()
        pred_ret_real = scaler_returns.inverse_transform(pred_ret_scaled)[0, 0]

        # convertir retorno en próximo precio
        next_price = last_real_price * (1 + pred_ret_real)
        preds.append(next_price)

        # actualizar ventana
        scaled_window.append(scaler_prices.transform([[next_price]])[0])
        last_real_price = next_price

    # --- DataFrame resultado
    df_preds = pd.DataFrame({"fecha": fechas_futuras, "prediccion": preds}).set_index("fecha")

    # --- plot
    plt.figure(figsize=(12,6))
    df["close"].plot(label="Histórico (hasta corte)", color="blue")
    df_preds["prediccion"].plot(label="Pronóstico", color="red", linestyle="--")
    plt.axvline(df.index.max(), color="gray", linestyle="--", label="Corte (train_end)")
    plt.title(f"Forecast {simbolo}: {fecha_pred_ini} → {fecha_pred_fin}")
    plt.legend()
    plt.show()

    return df_preds
