import sys, os
import joblib 
import json 
from datetime import datetime
from src.train import Trainer
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import classification_report, confusion_matrix


class RandomF_class():
    def __init__(self, indicadores):
        self.entrenador = Trainer(indicadores)
        self.modelo = None
                
    def randomf_train(self, simbolo, fecha_ini, fecha_fin):
        print("Ingrese fechas para backtesting:")
        print(f"\nFecha actual: {datetime.now().strftime('%Y-%m-%d')}")
        # fecha_ini_back = input("Fecha inicio (YYYY-MM-DD): ").strip()
        # fecha_fin_back = input("Fecha fin (YYYY-MM-DD): ").strip()
        fecha_ini_back = "2025-07-01"
        fecha_fin_back = "2025-08-31"
        df_train = self.entrenador.obj_datamanager.get_data(simbolo, fecha_ini, fecha_fin, timeframe="M5")
        X = self.entrenador.obj_indicadores.calculate_all(df_train)
        y = self.entrenador.crear_labels(df_train)
        
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=0.2, random_state=42, stratify=y
            )
        
        self.modelo = RandomForestClassifier(
            n_estimators=1000,        
            max_depth=None,          
            class_weight="balanced", 
            random_state=42
        )

        self.modelo.fit(X_train, y_train)
        y_pred = self.modelo.predict(X_test)
        probs = self.modelo.predict_proba(X_test)

        print("Orden de clases:", self.modelo.classes_)
        print("\nMatriz de confusión:")
        print(confusion_matrix(y_test, y_pred))
        print("\nReporte de clasificación:")
        print(classification_report(y_test, y_pred))
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        model_filename = os.path.join("..", "modelos","rf_model_.pkl")
        joblib.dump(self.modelo, "rf_model_.pkl")
        print(f"Modelo entrenado y guardado: {model_filename}")

        df_back = self.entrenador.obj_datamanager.get_data(simbolo, fecha_ini_back, fecha_fin_back, timeframe="M5")
        X_back = self.entrenador.obj_indicadores.calculate_all(df_back)

        predictions = self.modelo.predict(X_back)
        probabilities = self.modelo.predict_proba(X_back)

        signals = []

        for i in range(len(predictions)):
            signal = int(predictions[i])
            confidence = float(probabilities[i].max())
            min_confidence = 0.6
            
            if confidence >= min_confidence and signal != 0:
                timestamp = X_back.index[i]
                candle = df_back.loc[timestamp]
                
                signal_data = {
                    'timestamp': timestamp.strftime('%Y-%m-%d %H:%M:%S'),
                    'datetime_mt5': int(timestamp.timestamp()),
                    'signal': signal,
                    'confidence': confidence,
                    'price': float(candle['close']),
                    'high': float(candle['high']),
                    'low': float(candle['low']),
                    'volume': int(candle.get('tick_volume', 100)),
                    'model_type': 'random_forest'
                }
                signals.append(signal_data)

        filename = f"real_backtest_signals_{simbolo}.json"
        with open(filename, 'w', encoding='utf-16-le') as f:
            json.dump(signals, f, indent=2)

        print(f"Señales backtesting guardadas: {filename}")
        print(f"Señales generadas: {len(signals)}")  


