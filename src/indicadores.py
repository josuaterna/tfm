import pandas as pd
import numpy as np

class Indicadores_tecnicos:
    
    @staticmethod
    def get_available():
        return [
            'str_cdl','aw_os','rsi_3','chand','zlsma', 'ema_50_an', 'adx',
            'rsi_3_ind', 'ema_50_ind', 'zlsma_ind',
            'rsi','macd', 'sma_20', 'sma_50', 'ema_20', 'ema_50',
            'bb_upper', 'bb_lower', 'stoch_k', 'stoch_d', 'atr',
            'williams_r', 'cci', 'momentum', 'roc'
        ]
    
    def __init__(self, selected_indicators):
        self.indicators = selected_indicators
        
    def calculate_all(self, df):
        result_df = df.copy()
        
        for indicator in self.indicators:
            if indicator == 'str_cdl':
                result_df['str_cdl'] = self._str_cdl(df['open'], df['close'])
            elif indicator == 'aw_os':
               result_df['macd_ao_u'], result_df['macd_ao_u_1'], result_df['macd_ao_u_2'], result_df['macd_ao_u_3'], result_df['macd_ao_d'], result_df['macd_ao_d_1'], result_df['macd_ao_d_2'], result_df['macd_ao_d_3'] = self._aw_os(df['high'], df['low'])
               #result_df['macd_ao'], result_df['macds_ao'], result_df['macd_ao_u'], result_df['macd_ao_u_1'], result_df['macd_ao_u_2'], result_df['macd_ao_u_3'], result_df['macd_ao_d'], result_df['macd_ao_d_1'], result_df['macd_ao_d_2'], result_df['macd_ao_d_3'] = self._aw_os(df['high'], df['low'])
            elif indicator == 'rsi_3':
                result_df['rsi_3_20'], result_df['rsi_3_20_1'], result_df['rsi_3_20_2'], result_df['rsi_3_20_3'], result_df['rsi_3_30'], result_df['rsi_3_30_1'], result_df['rsi_3_30_2'], result_df['rsi_3_30_3'], result_df['rsi_3_80'], result_df['rsi_3_80_1'], result_df['rsi_3_80_2'], result_df['rsi_3_80_3'], result_df['rsi_3_70'], result_df['rsi_3_70_1'], result_df['rsi_3_70_2'], result_df['rsi_3_70_3'] = self._rsi_3(df['close'])
                #result_df['rsi_3'], result_df['rsi_3_20'], result_df['rsi_3_20_1'], result_df['rsi_3_20_2'], result_df['rsi_3_20_3'], result_df['rsi_3_30'], result_df['rsi_3_30_1'], result_df['rsi_3_30_2'], result_df['rsi_3_30_3'], result_df['rsi_3_80'], result_df['rsi_3_80_1'], result_df['rsi_3_80_2'], result_df['rsi_3_80_3'], result_df['rsi_3_70'], result_df['rsi_3_70_1'], result_df['rsi_3_70_2'], result_df['rsi_3_70_3']= self._rsi_3(df['close'])
                result_df.to_csv("rsi.csv", index=True)
            elif indicator == 'chand':
                result_df['chandb'], result_df['chands'], result_df['chandb_sig'],  result_df['chands_sig'], result_df['chandb_1'], result_df['chandb_2'], result_df['chandb_3'], result_df['chands_1'], result_df['chands_2'], result_df['chands_3'], result_df['chandb_sig_1'], result_df['chandb_sig_2'], result_df['chandb_sig_3'], result_df['chands_sig_1'], result_df['chands_sig_2'], result_df['chands_sig_3'] = self._chand(df['high'],df['low'],df['close'])
            elif indicator == 'zlsma':
                result_df['zlsmau'], result_df['zlsmau_1'], result_df['zlsmau_2'], result_df['zlsmau_3'], result_df['zlsmad'], result_df['zlsmad_1'], result_df['zlsmad_2'], result_df['zlsmad_3'] = self._zlsma(df['close'])
                #result_df['zlsma'], result_df['zlsmau'], result_df['zlsmau_1'], result_df['zlsmau_2'], result_df['zlsmau_3'], result_df['zlsmad'], result_df['zlsmad_1'], result_df['zlsmad_2'], result_df['zlsmad_3'] = self._zlsma(df['close'])
            elif indicator == 'ema_50_an':
                result_df['ema_50u'], result_df['ema_50u_1'], result_df['ema_50u_2'], result_df['ema_50u_3'], result_df['ema_50d'], result_df['ema_50d_1'], result_df['ema_50d_2'], result_df['ema_50d_3'] = self._ema_50_an(df['close'])
                #result_df['ema_50'], result_df['ema_50u'], result_df['ema_50u_1'], result_df['ema_50u_2'], result_df['ema_50u_3'], result_df['ema_50d'], result_df['ema_50d_1'], result_df['ema_50d_2'], result_df['ema_50d_3'] = self._ema_50_an(df['close'])
            elif indicator == 'adx':
                result_df['adx_30'], result_df['adx_30_1'], result_df['adx_30_2'], result_df['adx_30_3'], result_df['adx_25'], result_df['adx_25_1'], result_df['adx_25_2'], result_df['adx_25_3'] = self._adx(df['high'], df['low'],df['close'])
                #result_df['adx'], result_df['adx_30'], result_df['adx_30_1'], result_df['adx_30_2'], result_df['adx_30_3'], result_df['adx_25'], result_df['adx_25_1'], result_df['adx_25_2'], result_df['adx_25_3'] = self._adx(df['high'], df['low'],df['close'])
            elif indicator == 'rsi_3_ind':
                result_df['rsi_3'] = self._rsi(df['close'], period=3)
            elif indicator == 'ema_50_ind':
                result_df['ema_50'] = self._ema(df['close'], 50)
            elif indicator == 'zlsma_ind':
                result_df['zlsma'] = self._zlsma_calc(df['close'], 32)
            elif indicator == 'rsi':
                result_df['rsi'] = self._rsi(df['close'])
            elif indicator == 'macd':
                macd, signal = self._macd(df['close'])
                result_df['macd'] = macd
                result_df['macd_signal'] = signal
            elif indicator == 'sma_20':
                result_df['sma_20'] = df['close'].rolling(20).mean()
            elif indicator == 'sma_50':
                result_df['sma_50'] = df['close'].rolling(50).mean()
            elif indicator == 'ema_20':
                result_df['ema_20'] = df['close'].ewm(span=20).mean()
            elif indicator == 'ema_50':
                result_df['ema_50'] = df['close'].ewm(span=50).mean()
            elif indicator in ['bb_upper', 'bb_lower']:
                upper, lower = self._bollinger_bands(df['close'])
                result_df['bb_upper'] = upper
                result_df['bb_lower'] = lower
            elif indicator in ['stoch_k', 'stoch_d']:
                k, d = self._stochastic(df['high'], df['low'], df['close'])
                result_df['stoch_k'] = k
                result_df['stoch_d'] = d
            elif indicator == 'atr':
                result_df['atr'] = self._atr(df['high'], df['low'], df['close'])
            elif indicator == 'williams_r':
                result_df['williams_r'] = self._williams_r(df['high'], df['low'], df['close'])
            elif indicator == 'cci':
                result_df['cci'] = self._cci(df['high'], df['low'], df['close'])
            elif indicator == 'momentum':
                result_df['momentum'] = self._momentum(df['close'])
            elif indicator == 'roc':
                result_df['roc'] = self._roc(df['close'])
        return result_df

    def _str_cdl(self, open, close):
        size = (open - close).abs()
        size_avg = size.rolling(25).mean().fillna(size)
        str_cdl = (size >= 2 * size_avg).astype("float32")
        return str_cdl
        #return str_cdl, size_avg, size

    def _aw_os(self, high, low):
        med = (high + low) / 2
        macd_ao, macds_ao = self._macd_aw(med)
        macd_ao_u = ((macd_ao.shift(1) < macds_ao.shift(1)) & (macd_ao > macds_ao))                     
        macd_ao_u = macd_ao_u.fillna(0).astype("float32")
        macd_ao_d = ((macd_ao.shift(1) > macds_ao.shift(1)) & (macd_ao < macds_ao))
        macd_ao_d = macd_ao_d.fillna(0).astype("float32")
        macd_ao_u_1 = macd_ao_u.shift(1).fillna(0).astype("float32")
        macd_ao_u_2 = macd_ao_u.shift(2).fillna(0).astype("float32")
        macd_ao_u_3 = macd_ao_u.shift(3).fillna(0).astype("float32")
        macd_ao_d_1 = macd_ao_d.shift(1).fillna(0).astype("float32")
        macd_ao_d_2 = macd_ao_d.shift(2).fillna(0).astype("float32")
        macd_ao_d_3 = macd_ao_d.shift(3).fillna(0).astype("float32")

        return (
            #macd_ao, macds_ao,
            macd_ao_u, macd_ao_u_1, macd_ao_u_2, macd_ao_u_3,
            macd_ao_d, macd_ao_d_1, macd_ao_d_2, macd_ao_d_3
        )
    def _macd_aw(self, prices, fast=20, slow=30, signal=10):
        ema_fast = prices.ewm(span=fast, adjust=False).mean()
        ema_slow = prices.ewm(span=slow, adjust=False).mean()
        macd_line = ema_fast - ema_slow
        signal_line = macd_line.ewm(span=signal, adjust=False).mean()
        return macd_line, signal_line
    
    def _rsi_3(self, prices):
        rsi_3 = self._rsi(prices, period=3)
        rsi_3_20 = (rsi_3 < 20)
        rsi_3_20 = rsi_3_20.fillna(0).astype("float32")
        rsi_3_30 = (rsi_3 < 30)
        rsi_3_30 = rsi_3_30.fillna(0).astype("float32")
        rsi_3_80 = (rsi_3 > 80)
        rsi_3_80 = rsi_3_80.fillna(0).astype("float32")
        rsi_3_70 = (rsi_3 > 70)
        rsi_3_70 = rsi_3_70.fillna(0).astype("float32")    
        rsi_3_20_1 = rsi_3_20.shift(1).fillna(0).astype("float32")
        rsi_3_20_2 = rsi_3_20.shift(2).fillna(0).astype("float32")
        rsi_3_20_3 = rsi_3_20.shift(3).fillna(0).astype("float32")
        rsi_3_30_1 = rsi_3_30.shift(1).fillna(0).astype("float32")
        rsi_3_30_2 = rsi_3_30.shift(2).fillna(0).astype("float32")
        rsi_3_30_3 = rsi_3_30.shift(3).fillna(0).astype("float32")
        rsi_3_80_1 = rsi_3_80.shift(1).fillna(0).astype("float32")
        rsi_3_80_2 = rsi_3_80.shift(2).fillna(0).astype("float32")
        rsi_3_80_3 = rsi_3_80.shift(3).fillna(0).astype("float32")
        rsi_3_70_1 = rsi_3_70.shift(1).fillna(0).astype("float32")
        rsi_3_70_2 = rsi_3_70.shift(2).fillna(0).astype("float32")
        rsi_3_70_3 = rsi_3_70.shift(3).fillna(0).astype("float32")

        return (
            #rsi_3,
            rsi_3_20,rsi_3_20_1,rsi_3_20_2,rsi_3_20_3,
            rsi_3_30,rsi_3_30_1,rsi_3_30_2,rsi_3_30_3,
            rsi_3_80,rsi_3_80_1,rsi_3_80_2,rsi_3_80_3,
            rsi_3_70,rsi_3_70_1,rsi_3_70_2,rsi_3_70_3
        )

    def _rsi(self, series, period=14):
        delta = series.diff()
        gain = delta.clip(lower=0)
        loss = -delta.clip(upper=0)
        avg_gain = gain[:period].mean()
        avg_loss = loss[:period].mean()
        rsi_values = [None] * len(series)
        # aplicar Wilder
        for i in range(period, len(series)):
            current_gain = gain.iloc[i] if gain.iloc[i] > 0 else 0
            current_loss = loss.iloc[i] if loss.iloc[i] > 0 else 0

            avg_gain = (avg_gain * (period - 1) + current_gain) / period
            avg_loss = (avg_loss * (period - 1) + current_loss) / period

            if avg_loss == 0:
                rsi_values[i] = 100
            else:
                rs = avg_gain / avg_loss
                rsi_values[i] = 100 - (100 / (1 + rs))
        rsi_values = pd.Series(rsi_values, index=series.index, name=f"rsi").fillna(0)
        return rsi_values

    def _chand(self, high, low, close):
        chandb_sig = pd.Series(0, index=close.index)
        chands_sig = pd.Series(0, index=close.index)
        chandb = pd.Series(0, index=close.index)
        chands = pd.Series(0, index=close.index)

        atr_ch = self._atr(high, low, close, period=1)
        long_s = (high.shift(1) - atr_ch * 2).abs().fillna(high)
        short_s = (low.shift(1) + atr_ch * 2).abs().fillna(low)

        chandb_sig[close > short_s] = 1
        chands_sig[close < long_s] = 1

        chandb[chandb_sig > chandb_sig.shift(1)] = chandb_sig
        chands[chands_sig > chands_sig.shift(1)] = chands_sig

        chandb_1 = chandb.shift(1).fillna(0).astype("float32")
        chandb_2 = chandb.shift(2).fillna(0).astype("float32")
        chandb_3 = chandb.shift(3).fillna(0).astype("float32")
        chands_1 = chands.shift(1).fillna(0).astype("float32")
        chands_2 = chands.shift(2).fillna(0).astype("float32")
        chands_3 = chands.shift(3).fillna(0).astype("float32")
        chandb_sig_1 = chandb_sig.shift(1).fillna(0).astype("float32")
        chandb_sig_2 = chandb_sig.shift(2).fillna(0).astype("float32")
        chandb_sig_3 = chandb_sig.shift(3).fillna(0).astype("float32")
        chands_sig_1 = chands_sig.shift(1).fillna(0).astype("float32")
        chands_sig_2 = chands_sig.shift(2).fillna(0).astype("float32")
        chands_sig_3 = chands_sig.shift(3).fillna(0).astype("float32")
        
        return (
            chandb, chands, chandb_sig,  chands_sig,
            chandb_1, chandb_2, chandb_3,
            chands_1, chands_2, chands_3,
            chandb_sig_1, chandb_sig_2, chandb_sig_3,
            chands_sig_1, chands_sig_2, chands_sig_3
        )
    
    def _zlsma(self, close):
        zlsma = self._zlsma_calc(close, 32)
        zlsmau = close > zlsma
        zlsmau = zlsmau.fillna(0).astype("float32")
        zlsmad = close < zlsma
        zlsmad = zlsmad.fillna(0).astype("float32")
        zlsmau_1 = zlsmau.shift(1).fillna(0).astype("float32")
        zlsmau_2 = zlsmau.shift(2).fillna(0).astype("float32")
        zlsmau_3 = zlsmau.shift(3).fillna(0).astype("float32")
        zlsmad_1 = zlsmad.shift(1).fillna(0).astype("float32")
        zlsmad_2 = zlsmad.shift(2).fillna(0).astype("float32")
        zlsmad_3 = zlsmad.shift(3).fillna(0).astype("float32")
        return (
            #zlsma,
            zlsmau,zlsmau_1,zlsmau_2,zlsmau_3,
            zlsmad,zlsmad_1,zlsmad_2,zlsmad_3
            )
    def _zlsma_calc(self, prices, length=32):
        n = length
        lsma = np.zeros(len(prices))
        lsma2 = np.zeros(len(prices))
        zlsma = np.zeros(len(prices))
        # ---- LSMA ----
        for i in range(n - 1, len(prices)):
            sum_x = sum_y = sum_xy = sum_x2 = 0
            for j in range(n):
                idx = i - j
                x = n - 1 - j
                #y = prices[idx]
                y = prices.iloc[idx]
                sum_x += x
                sum_y += y
                sum_xy += x * y
                sum_x2 += x * x
            slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
            intercept = (sum_y - slope * sum_x) / n
            lsma[i] = slope * (n - 1) + intercept
        # ---- LSMA2 ----
        for i in range(2 * n - 1, len(prices)):
            sum_x = sum_y = sum_xy = sum_x2 = 0
            for j in range(n):
                idx = i - j
                x = n - 1 - j
                y = lsma[idx]
                sum_x += x
                sum_y += y
                sum_xy += x * y
                sum_x2 += x * x
            slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
            intercept = (sum_y - slope * sum_x) / n
            lsma2[i] = slope * (n - 1) + intercept
            zlsma[i] = lsma[i] + (lsma[i] - lsma2[i])
        zlsma = pd.Series(zlsma, index=prices.index, name=f"zlsma")
        #
        return zlsma

    def _ema_50_an(self, close):
        ema_50 = self._ema(close, 50)
        ema_50u = close > ema_50
        ema_50u = ema_50u.astype("float32").fillna(0)
        ema_50d = close < ema_50
        ema_50d = ema_50d.astype("float32").fillna(0)

        ema_50u_1 = ema_50u.shift(1).fillna(0).astype("float32")
        ema_50u_2 = ema_50u.shift(2).fillna(0).astype("float32")
        ema_50u_3 = ema_50u.shift(3).fillna(0).astype("float32")
        ema_50d_1 = ema_50d.shift(1).fillna(0).astype("float32")
        ema_50d_2 = ema_50d.shift(2).fillna(0).astype("float32")
        ema_50d_3 = ema_50d.shift(3).fillna(0).astype("float32")
        return (
            #ema_50,
            ema_50u,ema_50u_1,ema_50u_2,ema_50u_3,
            ema_50d,ema_50d_1,ema_50d_2,ema_50d_3
        )
    def _ema(self, prices, period):
        ema = prices.ewm(span=period, adjust=False).mean()
        ema = pd.Series(ema, index=prices.index, name=f"ema")
        return ema
    
    def _tema(self, prices, period):
        ema1 = self._ema(prices, period)
        ema2 = self._ema(ema1, period)
        ema3 = self._ema(ema2, period)
        tema_val = 3 * (ema1 - ema2) + ema3
        tema_val = pd.Series(tema_val, index=prices.index, name=f"tema")
        return tema_val
    

    def _adx(self, high, low, close, period=5):
        up_move   = (high - high.shift(1)).clip(lower=0).fillna(0)
        down_move = (low.shift(1) - low).clip(lower=0).fillna(0)
        pos_dm = up_move.where((up_move > down_move) & (up_move > 0), 0.0)
        neg_dm = down_move.where((down_move > up_move) & (down_move > 0), 0.0)
        tr = self._tr(high, low, close)
        # Suavizado de Wilder (EMA con alpha = 1/period)
        alpha = 1 / period
        tr_sm  = tr.ewm(alpha=alpha, adjust=False).mean().fillna(tr)
        pos_sm = pos_dm.ewm(alpha=alpha, adjust=False).mean().fillna(pos_dm)
        neg_sm = neg_dm.ewm(alpha=alpha, adjust=False).mean().fillna(neg_dm)
        plus_di  = 100 * (pos_sm / tr_sm)
        minus_di = 100 * (neg_sm / tr_sm)
        dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan)
        dx = dx.fillna(0)
        adx = dx.ewm(alpha=alpha, adjust=False).mean()
        adx_30 = (adx > 30).astype("float32").fillna(0)
        adx_25 = (adx > 25).astype("float32").fillna(0)
        adx_30_1 = adx_30.shift(1).fillna(0).astype("float32")
        adx_30_2 = adx_30.shift(2).fillna(0).astype("float32")
        adx_30_3 = adx_30.shift(3).fillna(0).astype("float32")
        adx_25_1 = adx_25.shift(1).fillna(0).astype("float32")
        adx_25_2 = adx_25.shift(2).fillna(0).astype("float32")
        adx_25_3 = adx_25.shift(3).fillna(0).astype("float32")

        return (
            #adx,
            adx_30, adx_30_1, adx_30_2, adx_30_3,
            adx_25, adx_25_1, adx_25_2, adx_25_3
        )
    
    def get_feature_matrix(self, df):
        df_with_indicators = self.calculate_all(df)
        df_with_indicators.to_csv("datos.csv", index=True)
        feature_columns = []
        
        for indicator in self.indicators:
            if indicator == 'str_cdl':
                feature_columns.extend(['str_cdl'])
            elif indicator == 'aw_os':
                feature_columns.extend(['macd_ao_u','macd_ao_u_1','macd_ao_u_2','macd_ao_u_3','macd_ao_d',
                                        'macd_ao_d_1','macd_ao_d_2','macd_ao_d_3'])
            elif indicator == 'rsi_3':
                feature_columns.extend(['rsi_3_20','rsi_3_20_1','rsi_3_20_2','rsi_3_20_3',
                                        'rsi_3_30','rsi_3_30_1','rsi_3_30_2','rsi_3_30_3',
                                        'rsi_3_80','rsi_3_80_1','rsi_3_80_2','rsi_3_80_3',
                                        'rsi_3_70','rsi_3_70_1','rsi_3_70_2','rsi_3_70_3'])
            elif indicator == 'chand':
                feature_columns.extend(['chandb','chands','chandb_sig','chands_sig',
                                        'chandb_1','chandb_2','chandb_3','chands_1',
                                        'chands_2','chands_3','chandb_sig_1','chandb_sig_2',
                                        'chandb_sig_3','chands_sig_1', 'chands_sig_2', 'chands_sig_3'])
            elif indicator == 'zlsma':
                feature_columns.extend(['zlsmau','zlsmau_1','zlsmau_2','zlsmau_3','zlsmad','zlsmad_1','zlsmad_2','zlsmad_3'])                         
            elif indicator == 'ema_50_an':
                feature_columns.extend(['ema_50u','ema_50u_1','ema_50u_2','ema_50u_3','ema_50d','ema_50d_1','ema_50d_2','ema_50d_3'])             
            elif indicator == 'rsi_3_ind':
                feature_columns.extend(['rsi_3'])
            elif indicator == 'ema_50_ind':
                feature_columns.extend(['ema_50'])                    
            elif indicator == 'zlsma_ind':
                feature_columns.extend(['zlsma'])                     
            elif indicator == 'adx':
                feature_columns.extend(['adx_30','adx_30_1','adx_30_2','adx_30_3','adx_25','adx_25_1','adx_25_2','adx_25_3'])   
            elif indicator == 'macd':
                feature_columns.extend(['macd', 'macd_signal'])
            elif indicator in ['bb_upper', 'bb_lower']:
                feature_columns.extend(['bb_upper', 'bb_lower'])
            elif indicator in ['stoch_k', 'stoch_d']:
                feature_columns.extend(['stoch_k', 'stoch_d'])
            else:
                feature_columns.append(indicator)
        
        return df_with_indicators[feature_columns].dropna()

    def _macd(self, prices):
        ema12 = prices.ewm(span=12).mean()
        ema26 = prices.ewm(span=26).mean()
        macd = ema12 - ema26
        signal = macd.ewm(span=9).mean()
        return macd, signal
    
    def _bollinger_bands(self, prices, period=20, std=2):
        sma = prices.rolling(period).mean()
        std_dev = prices.rolling(period).std()
        upper = sma + (std_dev * std)
        lower = sma - (std_dev * std)
        return upper, lower
    
    def _stochastic(self, high, low, close, k_period=14, d_period=3):
        lowest_low = low.rolling(k_period).min()
        highest_high = high.rolling(k_period).max()
        k_percent = 100 * ((close - lowest_low) / (highest_high - lowest_low))
        d_percent = k_percent.rolling(d_period).mean()
        return k_percent, d_percent
    
    def _atr(self, high, low, close, period=14):
        tr = self._tr(high, low, close)
        return tr.rolling(period).mean()
    
    def _tr(self, high, low, close):
        tr1 = high - low
        tr2 = (high - close.shift(1)).abs()
        tr3 = (low - close.shift(1)).abs()
        tr = pd.concat([tr1, tr2, tr3], axis=1).max(axis=1).fillna(0)
        return tr    
    
    def _williams_r(self, high, low, close, period=14):
        highest_high = high.rolling(period).max()
        lowest_low = low.rolling(period).min()
        return -100 * ((highest_high - close) / (highest_high - lowest_low))
    
    def _cci(self, high, low, close, period=20):
        tp = (high + low + close) / 3
        sma_tp = tp.rolling(period).mean()
        mad = tp.rolling(period).apply(lambda x: np.abs(x - x.mean()).mean())
        return (tp - sma_tp) / (0.015 * mad)
    
    def _momentum(self, prices, period=10):
        return prices / prices.shift(period) * 100
    
    def _roc(self, prices, period=10):
        return ((prices - prices.shift(period)) / prices.shift(period)) * 100