import sys, os
from src.train import Trainer


class RandomF_class():
    def __init__(self, indicadores, simbolo):
        self.entrenador = Trainer(indicadores)
        self.model = None
        self.scaler = None
        self.simbolo = simbolo
        ruta_model = os.path.join("..", "modelos", "lstm_model.pth")
        ruta_scaler = os.path.join("..", "modelos", "lstm_scaler.pkl")
        
    def randomf_train(self, simbolo, fecha_ini, fecha_fin):
        df_train = self.entrenador.obj_datamanager.get_data(simbolo, fecha_ini, fecha_fin, timeframe="M5")
        indicadores = self.entrenador.obj_indicadores.calculate_all(df_train)
        labels_train = self.entrenador.crear_labels(df_train)
        

