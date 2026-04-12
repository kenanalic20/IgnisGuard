from fastapi import APIRouter
from api.models.request_model import SensorData
from api.models.response_model import PredictionResponse
from api.services.ml_service import predict

router = APIRouter()

@router.post("/predict", response_model=PredictionResponse)
def get_prediction(data: SensorData):
    result = predict(data)
    return {"prediction": result}