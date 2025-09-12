import sys, os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

class RandomF_class():
    def __init__(self):
        ruta_model = os.path.join("..", "modelos", "lstm_model.pth")
        ruta_scaler = os.path.join("..", "modelos", "lstm_scaler.pkl")
        pass