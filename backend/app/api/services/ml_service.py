import joblib
import os

# Get current file directory
BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# Go up to project root → then into ml folder
MODEL_PATH = os.path.join(BASE_DIR, "..", "..", "ml", "model_rf.joblib")

artifact = joblib.load(MODEL_PATH)
print("Loading model from:", MODEL_PATH)

model = artifact["model"]
label_encoder = artifact["label_encoder"]

def predict(data):
    input_data = [[
        data.temperature,
        data.humidity,
        data.gas
    ]]

    pred = model.predict(input_data)
    label = label_encoder.inverse_transform(pred)[0]

    return label