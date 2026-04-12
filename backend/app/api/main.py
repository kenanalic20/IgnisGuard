from contextlib import asynccontextmanager
import logging

from fastapi import FastAPI
from api.routes.predict import router as predict_router
from api.services.sensor_worker import SensorWorker


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    worker = SensorWorker()
    worker.start()
    app.state.sensor_worker = worker
    try:
        yield
    finally:
        worker.stop()


app = FastAPI(lifespan=lifespan)

app.include_router(predict_router)