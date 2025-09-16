import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
import pandas as pd
import json
from src.train import Trainer
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score
from sklearn.preprocessing import StandardScaler
from sklearn.model_selection import train_test_split

class SVM_NN_class():
    
    def __init__(self, indicadores, hidden_dim=64, dropout=0.2, margin=1.0):
        self.margin = margin
        self.hidden_dim = hidden_dim
        self.dropout = dropout
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        self.entrenador = Trainer(indicadores)
        self.model = None

    def svmnn_train(self, simbolo, fecha_ini, fecha_fin):
        df_full = self.entrenador.obj_datamanager.get_data(simbolo, fecha_ini, fecha_fin)
        if df_full is None or len(df_full) < 500:
            print("ERROR: Insuficientes datos")
            return
        X, y = self.entrenador.preparar_datos(simbolo, fecha_ini, fecha_fin)
        input_dim = len(X)

        self.modelo = NeuralSVMModel(input_dim)
        best_val_acc, history = self.modelo.fit(X, y, return_history=True)
        self.modelo.save("modelos/neural_svm_eurusd.pth")
        print("Modelo guardado en modelos/neural_svm_eurusd.pth")
    
    def generar_json_senales(self, model, simbolo, fecha_ini, fecha_fin, output_file, seq_len=1):
        df = self.entrenador.obj_datamanager.get_data(simbolo, fecha_ini, fecha_fin)
        if df is None or df.empty:
            raise ValueError("No se obtuvieron datos del datamanager")
        
        X, y = self.entrenador.preparar_datos(simbolo, fecha_ini, fecha_fin)

        predicciones = model.predict(X)
        probabilidades = model.predict_proba(X)

        signals = []

        for i, pred in enumerate(predicciones):
            timestamp = df.index[i + seq_len]  # compensamos la ventana
            timestamp_str = str(timestamp)
            datetime_mt5 = int(pd.to_datetime(timestamp).timestamp())
            confidence = float(max(probabilidades[i]))

            signals.append({
                "timestamp": timestamp_str,
                "datetime_mt5": datetime_mt5,
                "signal": int(pred),
                "confidence": confidence,
                "price": float(df["close"].iloc[i + seq_len]),
                "symbol": simbolo
            })

        with open(output_file, "w") as f:
            json.dump(signals, f, indent=4)

        print(f"Archivo JSON generado con {len(signals)} señales en {output_file}")
        return signals


class NeuralSVMModel(nn.Module):
    
    def __init__(self, input_dim, hidden_dim=64, dropout=0.4, margin=1.0):
        super().__init__()
        self.margin = margin
        self.classifier = nn.Linear(32, 3)
        self.probability_layer = nn.Linear(32, 3)
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        self.to(self.device)
        self.label_map = {-1: 0, 0: 1, 1: 2}
        self.reverse_map = {0: -1, 1: 0, 2: 1}
        self.scaler = StandardScaler()
        self.to(self.device)
        self.feature_layers = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Dropout(dropout * 0.5),
            nn.Linear(hidden_dim // 2, 32),
            nn.ReLU()
        ).to(self.device)
 

    def forward(self, x):
        features = self.feature_layers(x)
        logits = self.classifier(features)
        probs = F.softmax(self.probability_layer(features), dim=1)
        return logits, probs, features
    
    def svm_loss(self, logits, targets):
        batch_size = logits.size(0)
        correct_class_scores = logits.gather(1, targets.view(-1, 1))
        
        margins = logits - correct_class_scores + self.margin
        margins[range(batch_size), targets] = 0
        
        loss = torch.clamp(margins, min=0)
        loss = loss.sum() / batch_size
        
        return loss
    
    def fit(self, X, y, epochs=100, lr=0.001, batch_size=32, validation_split=0.2, return_history=False):
        print(f"Entrenando Neural-SVM con {len(X)} muestras...")
        X_scaled = self.scaler.fit_transform(X)
        y_mapped = np.array([self.label_map[label] for label in y])
        
        X_train, X_val, y_train, y_val = train_test_split(
            X_scaled, y_mapped, test_size=validation_split, random_state=42, stratify=y_mapped
            #X, y_mapped, test_size=validation_split, random_state=42, stratify=y_mapped
        )

        X_train_tensor = torch.FloatTensor(X_train).to(self.device)
        y_train_tensor = torch.LongTensor(y_train).to(self.device)
        X_val_tensor = torch.FloatTensor(X_val).to(self.device)
        y_val_tensor = torch.LongTensor(y_val).to(self.device)
        
        optimizer = torch.optim.Adam(self.parameters(), lr=lr, weight_decay=1e-4)
        scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(optimizer, 'min', patience=10)
        
        best_val_acc = 0
        patience = 15
        patience_counter = 0
        
        history = {
            'train_losses': [],
            'train_accuracies': [],
            'test_losses': [],
            'test_accuracies': []
        }
        
        self.train()
        for epoch in range(epochs):
            total_loss = 0
            total_samples = 0
            correct_train = 0
            
            for i in range(0, len(X_train_tensor), batch_size):
                batch_X = X_train_tensor[i:i+batch_size]
                batch_y = y_train_tensor[i:i+batch_size]
                
                if len(batch_X) == 0:
                    continue
                
                optimizer.zero_grad()
                
                logits, probs, features = self.forward(batch_X)
                
                svm_loss = self.svm_loss(logits, batch_y)
                ce_loss = F.cross_entropy(logits, batch_y).to(self.device)
                total_loss_batch = 0.7 * svm_loss + 0.3 * ce_loss
                
                total_loss_batch.backward()
                torch.nn.utils.clip_grad_norm_(self.parameters(), 1.0)
                optimizer.step()
                
                total_loss += total_loss_batch.item() * len(batch_X)
                total_samples += len(batch_X)
                
                with torch.no_grad():
                    predictions = torch.argmax(logits, dim=1)
                    correct_train += (predictions == batch_y).sum().item()
            
            avg_train_loss = total_loss / total_samples
            train_accuracy = correct_train / len(X_train_tensor)
            
            val_loss, val_acc = self._validate_detailed(X_val_tensor, y_val_tensor)
            
            history['train_losses'].append(avg_train_loss)
            history['train_accuracies'].append(train_accuracy)
            history['test_losses'].append(val_loss)
            history['test_accuracies'].append(val_acc)
            
            if epoch % 5 == 0:
                print(f"Epoch {epoch:3d}: Train_Loss={avg_train_loss:.4f}, Train_Acc={train_accuracy:.3f}, Val_Loss={val_loss:.4f}, Val_Acc={val_acc:.3f}")
                
                scheduler.step(avg_train_loss)
                
                if val_acc > best_val_acc:
                    best_val_acc = val_acc
                    patience_counter = 0
                else:
                    patience_counter += 1
                    if patience_counter >= patience:
                        print(f"Early stopping en epoch {epoch}")
                        break
        
        print(f"Entrenamiento completado. Mejor accuracy: {best_val_acc:.3f}")
        
        if return_history:
            return best_val_acc, history
        return best_val_acc
    
    def _validate_detailed(self, X_val, y_val):
        self.eval()
        with torch.no_grad():
            logits, _, _ = self.forward(X_val)
            
            svm_loss = self.svm_loss(logits, y_val)
            ce_loss = F.cross_entropy(logits, y_val).to(self.device)
            val_loss = (0.7 * svm_loss + 0.3 * ce_loss).item()
            
            predictions = torch.argmax(logits, dim=1)
            accuracy = (predictions == y_val).float().mean().item()
        self.train()
        return val_loss, accuracy
    
    def _validate(self, X_val, y_val):
        self.eval()
        with torch.no_grad():
            logits, _, _ = self.forward(X_val)
            predictions = torch.argmax(logits, dim=1)
            accuracy = (predictions == y_val).float().mean().item()
        self.train()
        return accuracy
    
    def predict(self, X):
        self.eval()
        X_scaled = self.scaler.transform(X)
        X_tensor = torch.FloatTensor(X_scaled).to(self.device)
        #X_tensor = torch.FloatTensor(X).to(self.device)
        
        with torch.no_grad():
            logits, _, _ = self.forward(X_tensor)
            predictions = torch.argmax(logits, dim=1).cpu().numpy()
        
        return np.array([self.reverse_map[pred] for pred in predictions])
    
    def predict_proba(self, X):
        self.eval()
        X_scaled = self.scaler.transform(X)
        X_tensor = torch.FloatTensor(X_scaled).to(self.device)
        #X_tensor = torch.FloatTensor(X).to(self.device)
        
        with torch.no_grad():
            _, probs, _ = self.forward(X_tensor)
            probabilities = probs.cpu().numpy()
        
        return probabilities
    
    def get_decision_function(self, X):
        self.eval()
        X_scaled = self.scaler.transform(X)
        X_tensor = torch.FloatTensor(X_scaled).to(self.device)
        #X_tensor = torch.FloatTensor(X).to(self.device)
        
        with torch.no_grad():
            logits, _, _ = self.forward(X_tensor)
            decision_scores = logits.cpu().numpy()
        
        return decision_scores
    
    def save(self, filepath):
        save_dict = {
            'model_state': self.state_dict(),
            'scaler': self.scaler,
            'label_map': self.label_map,
            'reverse_map': self.reverse_map,
            'margin': self.margin,
            'input_dim': self.feature_layers[0].in_features,
            'hidden_dim': self.feature_layers[0].out_features,  # Guardar hidden_dim real
            'dropout': 0.2  # Valor usado durante entrenamiento
        }
        torch.save(save_dict, filepath)
    
    @classmethod
    def load(cls, filepath):
        save_dict = torch.load(filepath, map_location='cpu', weights_only=False)
        
        # Extraer parámetros del modelo guardado
        input_dim = save_dict['input_dim']
        hidden_dim = save_dict.get('hidden_dim', 64)  # Fallback a 64 si no existe
        margin = save_dict.get('margin', 1.0)
        
        # Si hidden_dim no fue guardado, inferirlo del state_dict
        if 'hidden_dim' not in save_dict:
            try:
                # Inferir hidden_dim del peso de la primera capa
                first_layer_weight = save_dict['model_state']['feature_layers.0.weight']
                hidden_dim = first_layer_weight.shape[0]
                print(f"Hidden dim inferido: {hidden_dim}")
            except:
                hidden_dim = 64  # Fallback
        
        model = cls(
            input_dim=input_dim,
            hidden_dim=hidden_dim,
            margin=margin
        )
        
        model.load_state_dict(save_dict['model_state'])
        model.scaler = save_dict['scaler']
        model.label_map = save_dict['label_map']
        model.reverse_map = save_dict['reverse_map']
        return model
    
    
class StandardNeuralModel(nn.Module):
    
    def __init__(self, input_dim, hidden_dim=64, dropout=0.2):
        super().__init__()
        self.scaler = StandardScaler()
        
        self.network = nn.Sequential(
            nn.Linear(input_dim, hidden_dim),
            nn.ReLU(),
            nn.Dropout(dropout),
            nn.Linear(hidden_dim, hidden_dim // 2),
            nn.ReLU(),
            nn.Dropout(dropout * 0.5),
            nn.Linear(hidden_dim // 2, 3)
        )
        
        self.device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        self.to(self.device)
        self.label_map = {-1: 0, 0: 1, 1: 2}
        self.reverse_map = {0: -1, 1: 0, 2: 1}
    
    def forward(self, x):
        return self.network(x)
    
    def fit(self, X, y, epochs=100, lr=0.001, batch_size=32, return_history=False):
        #X_scaled = self.scaler.fit_transform(X)
        y_mapped = np.array([self.label_map[label] for label in y])
        
        X_train, X_val, y_train, y_val = train_test_split(
            #X_scaled, y_mapped, test_size=0.2, random_state=42, stratify=y_mapped
            X, y_mapped, test_size=0.2, random_state=42, stratify=y_mapped
        )
        
        X_train_tensor = torch.FloatTensor(X_train).to(self.device)
        y_train_tensor = torch.LongTensor(y_train).to(self.device)
        X_val_tensor = torch.FloatTensor(X_val).to(self.device)
        y_val_tensor = torch.LongTensor(y_val).to(self.device)
        
        optimizer = torch.optim.Adam(self.parameters(), lr=lr)
        criterion = nn.CrossEntropyLoss()
        
        best_val_acc = 0
        
        history = {
            'train_losses': [],
            'train_accuracies': [],
            'test_losses': [],
            'test_accuracies': []
        }
        
        self.train()
        for epoch in range(epochs):
            total_loss = 0
            total_samples = 0
            correct_train = 0
            
            for i in range(0, len(X_train_tensor), batch_size):
                batch_X = X_train_tensor[i:i+batch_size]
                batch_y = y_train_tensor[i:i+batch_size]
                
                optimizer.zero_grad()
                outputs = self.forward(batch_X)
                loss = criterion(outputs, batch_y)
                loss.backward()
                optimizer.step()
                
                total_loss += loss.item() * len(batch_X)
                total_samples += len(batch_X)
                
                with torch.no_grad():
                    predictions = torch.argmax(outputs, dim=1)
                    correct_train += (predictions == batch_y).sum().item()
            
            avg_train_loss = total_loss / total_samples
            train_accuracy = correct_train / len(X_train_tensor)
            
            val_loss, val_acc = self._validate_detailed(X_val_tensor, y_val_tensor, criterion)
            
            history['train_losses'].append(avg_train_loss)
            history['train_accuracies'].append(train_accuracy)
            history['test_losses'].append(val_loss)
            history['test_accuracies'].append(val_acc)
            
            if val_acc > best_val_acc:
                best_val_acc = val_acc
            
            if epoch % 10 == 0:
                print(f"Epoch {epoch}: Train_Loss={avg_train_loss:.4f}, Train_Acc={train_accuracy:.3f}, Val_Loss={val_loss:.4f}, Val_Acc={val_acc:.3f}")
        
        if return_history:
            return best_val_acc, history
        return best_val_acc
    
    def _validate_detailed(self, X_val, y_val, criterion):
        self.eval()
        with torch.no_grad():
            outputs = self.forward(X_val)
            val_loss = criterion(outputs, y_val).item()
            predictions = torch.argmax(outputs, dim=1)
            accuracy = (predictions == y_val).float().mean().item()
        self.train()
        return val_loss, accuracy
    
    def _validate(self, X_val, y_val):
        self.eval()
        with torch.no_grad():
            outputs = self.forward(X_val)
            predictions = torch.argmax(outputs, dim=1)
            accuracy = (predictions == y_val).float().mean().item()
        self.train()
        return accuracy
    
    def predict(self, X):
        self.eval()
        #X_scaled = self.scaler.transform(X)
        #X_tensor = torch.FloatTensor(X_scaled).to(self.device)
        X_tensor = torch.FloatTensor(X).to(self.device)
        
        with torch.no_grad():
            outputs = self.forward(X_tensor)
            predictions = torch.argmax(outputs, dim=1).cpu().numpy()
        
        return np.array([self.reverse_map[pred] for pred in predictions])
    
    def predict_proba(self, X):
        self.eval()
        #X_scaled = self.scaler.transform(X)
        #X_tensor = torch.FloatTensor(X_scaled).to(self.device)
        X_tensor = torch.FloatTensor(X).to(self.device)
        
        with torch.no_grad():
            outputs = self.forward(X_tensor)
            probabilities = F.softmax(outputs, dim=1).cpu().numpy()
        
        return probabilities
    
    def save(self, filepath):
        save_dict = {
            'model_state': self.state_dict(),
            'scaler': self.scaler,
            'label_map': self.label_map,
            'reverse_map': self.reverse_map,
            'input_dim': self.network[0].in_features,
            'hidden_dim': self.network[0].out_features,  # Guardar hidden_dim real
            'dropout': 0.2  # Valor usado durante entrenamiento
        }
        torch.save(save_dict, filepath)
    
    @classmethod
    def load(cls, filepath):
        save_dict = torch.load(filepath, map_location='cpu', weights_only=False)
        
        # Extraer parámetros del modelo guardado
        input_dim = save_dict['input_dim']
        hidden_dim = save_dict.get('hidden_dim', 64)  # Fallback a 64 si no existe
        
        # Si hidden_dim no fue guardado, inferirlo del state_dict
        if 'hidden_dim' not in save_dict:
            try:
                # Inferir hidden_dim del peso de la primera capa
                first_layer_weight = save_dict['model_state']['network.0.weight']
                hidden_dim = first_layer_weight.shape[0]
                print(f"Hidden dim inferido: {hidden_dim}")
            except:
                hidden_dim = 64  # Fallback
        
        model = cls(input_dim=input_dim, hidden_dim=hidden_dim)
        model.load_state_dict(save_dict['model_state'])
        model.scaler = save_dict['scaler']
        model.label_map = save_dict['label_map']
        model.reverse_map = save_dict['reverse_map']
        return model