from typing import Any
from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()


class Item(BaseModel):
    name: str
    description: str | None = None
    price: float
    tax: float | None = None
    tags: list[str] = []
    password: str | None = None


@app.post("/items/")
async def create_item(item: Item) -> Any:
    # Here we could add logic to save the item to a database
    # luu vao co so du lieu item
    return {
        "name": "Thang",
        "price": 1000.0,
        "tags": ["Thegioi", "VietNam"],
        "description": "Mo ta",
        "tax": 10.5,
        "password": "123456",
        "id": 1,
        "owner_id": 1,
    }


@app.get("/items/")
async def read_items() -> list[Item]:
    return [
        Item(name="Portal Gun", price=42.0),
        Item(name="Plumbus", price=32.0),
    ]
