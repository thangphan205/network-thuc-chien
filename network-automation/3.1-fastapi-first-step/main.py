# https://fastapi.tiangolo.com/tutorial/first-steps/
from fastapi import FastAPI

app = FastAPI()


@app.get("/")
async def root():
    # Xử lý root ở đây
    return {"message": "Network Thực Chiến"}


# fastapi dev main.py
# uvicorn main:app --reload
