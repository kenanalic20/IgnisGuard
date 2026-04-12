import random
from openpyxl import Workbook

wb = Workbook()
ws = wb.active
ws.title = "data"

ws.append(["temperature", "humidity", "gas", "class"])

rows = []

for _ in range(1000):
    temp = random.uniform(15, 55)
    hum = random.uniform(20, 95)
    gas = random.uniform(200, 1500)

    score = 0

    # 🔥 GAS (most important)
    if gas > 1000:
        score += 3
    elif gas > 700:
        score += 2
    elif gas > 400:
        score += 1

    # 🌡 TEMPERATURE
    if temp > 45:
        score += 2
    elif temp > 30:
        score += 1

    # 💧 HUMIDITY (NOW MATTERS)
    if hum < 30:
        score += 1  # dry air → more fire risk
    elif hum > 80:
        score -= 1  # humid → less risk

    # 🎲 NOISE (IMPURITY)
    if random.random() < 0.1:
        score += random.choice([-1, 1])

    # 🎯 CLASSIFICATION (with overlap)
    if score <= 1:
        label = "Good"
    elif score <= 3:
        label = "Warning"
    else:
        label = "Danger"

    rows.append([round(temp, 2), round(hum, 2), int(gas), label])

for row in rows:
    ws.append(row)

wb.save("training_data_realistic.xlsx")